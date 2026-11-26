import express from "express";
import helmet from "helmet";
import pg from "pg";
import {
  SESSION_COOKIE, SESSION_TTL_SECONDS, clearSessionCookie, getVerifiedVkUserId,
  parseAdminIds, parseCookies, randomToken, safeEqual, sessionCookie, sha256
} from "./auth-core.js";

const { Pool } = pg;
const required = ["DATABASE_URL", "VKID_APP_ID", "VKID_API_ORIGIN", "PUBLIC_SITE_ORIGIN", "SESSION_COOKIE_DOMAIN", "AUTH_SERVICE_SECRET"];
for (const name of required) {
  if (!process.env[name]) throw new Error("Missing required environment variable: " + name);
}
if (!/^\d+$/.test(process.env.VKID_APP_ID)) throw new Error("VKID_APP_ID must be numeric");

const APP_ID = process.env.VKID_APP_ID;
const VKID_API_ORIGIN = new URL(process.env.VKID_API_ORIGIN);
if (VKID_API_ORIGIN.protocol !== "https:" || VKID_API_ORIGIN.pathname !== "/" || VKID_API_ORIGIN.search || VKID_API_ORIGIN.hash) {
  throw new Error("VKID_API_ORIGIN must be an HTTPS origin without a path");
}
const SITE_ORIGIN = new URL(process.env.PUBLIC_SITE_ORIGIN).origin;
const SESSION_COOKIE_DOMAIN = process.env.SESSION_COOKIE_DOMAIN.trim();
const cookieSuffix = SESSION_COOKIE_DOMAIN.slice(1).toLowerCase();
const siteHost = new URL(SITE_ORIGIN).hostname.toLowerCase();
if (!siteHost.endsWith("." + cookieSuffix) && siteHost !== cookieSuffix) throw new Error("PUBLIC_SITE_ORIGIN must be under SESSION_COOKIE_DOMAIN");
const ADMIN_IDS = parseAdminIds(process.env.VK_ADMIN_USER_IDS);
const PORT = Number(process.env.PORT || 8080);
const pool = new Pool({ connectionString: process.env.DATABASE_URL, ssl: process.env.PGSSLMODE === "disable" ? false : { rejectUnauthorized: true }, max: 10 });
const app = express();
app.disable("x-powered-by");
if (process.env.TRUST_PROXY === "1") app.set("trust proxy", 1);
app.use(helmet());
app.use(express.json({ limit: "8kb", strict: true }));

await pool.query(`
  CREATE TABLE IF NOT EXISTS vkid_sessions (
    session_hash TEXT PRIMARY KEY,
    vk_user_id TEXT NOT NULL,
    csrf_hash TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ
  );
  CREATE INDEX IF NOT EXISTS vkid_sessions_expiry_idx ON vkid_sessions (expires_at);
`);

const rateBuckets = new Map();
function rateLimit(req, res, next) {
  const now = Date.now();
  const key = req.ip || "unknown";
  const current = rateBuckets.get(key);
  if (!current || current.until <= now) rateBuckets.set(key, { count: 1, until: now + 60_000 });
  else if (++current.count > 20) return res.status(429).json({ error: "Слишком много попыток. Попробуйте позже." });
  if (rateBuckets.size > 5000) {
    for (const [k, v] of rateBuckets) if (v.until <= now) rateBuckets.delete(k);
  }
  next();
}

function originAllowed(req) {
  return req.headers.origin === SITE_ORIGIN;
}
function requireOrigin(req, res, next) {
  if (!originAllowed(req)) return res.status(403).json({ error: "Недопустимый источник запроса." });
  next();
}
function sessionId(req) {
  return parseCookies(req.headers.cookie)[SESSION_COOKIE] || "";
}
async function loadSession(req) {
  const raw = sessionId(req);
  if (!raw || raw.length > 200) return null;
  const result = await pool.query(
    "SELECT vk_user_id, csrf_hash, expires_at FROM vkid_sessions WHERE session_hash = $1 AND revoked_at IS NULL AND expires_at > NOW()",
    [sha256(raw)]
  );
  return result.rows[0] || null;
}
function isAdmin(userId) {
  return ADMIN_IDS.has(String(userId));
}
async function verifyVkAccessToken(accessToken) {
  const endpoint = new URL("/oauth2/user_info", VKID_API_ORIGIN);
  endpoint.searchParams.set("client_id", APP_ID);
  const response = await fetch(endpoint, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ access_token: accessToken }),
    signal: AbortSignal.timeout(8000)
  });
  if (!response.ok) throw new Error("VK ID rejected the access token");
  const data = await response.json();
  return getVerifiedVkUserId(data);
}
function requireInternal(req, res, next) {
  const supplied = String(req.headers.authorization || "").replace(/^Bearer\s+/i, "");
  if (!safeEqual(supplied, process.env.AUTH_SERVICE_SECRET)) return res.status(401).json({ error: "Unauthorized" });
  next();
}

app.use((req, res, next) => {
  if (req.headers.origin === SITE_ORIGIN) {
    res.setHeader("Access-Control-Allow-Origin", SITE_ORIGIN);
    res.setHeader("Access-Control-Allow-Credentials", "true");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type, X-CSRF-Token");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    res.setHeader("Vary", "Origin");
  }
  if (req.method === "OPTIONS") {
    if (req.headers.origin !== SITE_ORIGIN) return res.sendStatus(403);
    return res.sendStatus(204);
  }
  next();
});

app.get("/health", (_req, res) => res.json({ ok: true, service: "vkid-auth", databaseConfigured: true }));

app.post("/api/auth/vk/session", rateLimit, requireOrigin, async (req, res) => {
  const accessToken = req.body?.accessToken;
  if (typeof accessToken !== "string" || accessToken.length < 20 || accessToken.length > 8192) {
    return res.status(400).json({ error: "Некорректный токен VK ID." });
  }
  try {
    const vkUserId = await verifyVkAccessToken(accessToken);
    const rawSession = randomToken();
    const csrfToken = randomToken();
    await pool.query(
      "INSERT INTO vkid_sessions (session_hash, vk_user_id, csrf_hash, expires_at) VALUES ($1, $2, $3, NOW() + ($4 * INTERVAL '1 second'))",
      [sha256(rawSession), vkUserId, sha256(csrfToken), SESSION_TTL_SECONDS]
    );
    res.setHeader("Set-Cookie", sessionCookie(rawSession, SESSION_COOKIE_DOMAIN));
    return res.status(201).json({ authenticated: true, user: { id: vkUserId, isAdmin: isAdmin(vkUserId) }, csrfToken });
  } catch {
    return res.status(401).json({ error: "Не удалось подтвердить учётную запись VK ID." });
  }
});

app.get("/api/auth/session", async (req, res) => {
  try {
    const row = await loadSession(req);
    if (!row) return res.status(200).json({ authenticated: false, user: null });
    return res.json({ authenticated: true, user: { id: row.vk_user_id, isAdmin: isAdmin(row.vk_user_id) } });
  } catch {
    return res.status(503).json({ error: "Проверка сессии временно недоступна." });
  }
});

app.get("/api/auth/csrf", requireOrigin, async (req, res) => {
  try {
    const raw = sessionId(req);
    const row = await loadSession(req);
    if (!raw || !row) return res.status(401).json({ error: "Требуется вход." });
    const csrfToken = randomToken();
    await pool.query("UPDATE vkid_sessions SET csrf_hash = $1 WHERE session_hash = $2", [sha256(csrfToken), sha256(raw)]);
    return res.json({ csrfToken });
  } catch {
    return res.status(503).json({ error: "Не удалось обновить защитный токен." });
  }
});

app.post("/api/auth/logout", requireOrigin, async (req, res) => {
  try {
    const raw = sessionId(req);
    const row = await loadSession(req);
    const supplied = String(req.headers["x-csrf-token"] || "");
    if (!raw || !row || !supplied || !safeEqual(sha256(supplied), row.csrf_hash)) {
      res.setHeader("Set-Cookie", clearSessionCookie(SESSION_COOKIE_DOMAIN));
      return res.status(403).json({ error: "Сессия или CSRF-токен недействительны." });
    }
    await pool.query("UPDATE vkid_sessions SET revoked_at = NOW() WHERE session_hash = $1", [sha256(raw)]);
    res.setHeader("Set-Cookie", clearSessionCookie(SESSION_COOKIE_DOMAIN));
    return res.json({ ok: true });
  } catch {
    return res.status(503).json({ error: "Не удалось завершить сессию." });
  }
});

// Internal endpoint used by the storage and cloud APIs. It is not exposed to browsers.
app.post("/internal/authorize", requireInternal, async (req, res) => {
  try {
    const row = await loadSession(req);
    const supplied = String(req.headers["x-csrf-token"] || "");
    if (!row || !supplied || !safeEqual(sha256(supplied), row.csrf_hash)) {
      return res.status(403).json({ authenticated: false, error: "CSRF validation failed." });
    }
    return res.json({ authenticated: true, userId: row.vk_user_id, isAdmin: isAdmin(row.vk_user_id) });
  } catch {
    return res.status(503).json({ error: "Session authorization unavailable." });
  }
});

app.get("/internal/session", requireInternal, async (req, res) => {
  try {
    const row = await loadSession(req);
    if (!row) return res.status(401).json({ authenticated: false });
    return res.json({ authenticated: true, userId: row.vk_user_id, isAdmin: isAdmin(row.vk_user_id) });
  } catch {
    return res.status(503).json({ error: "Session verification unavailable." });
  }
});

const server = app.listen(PORT, "0.0.0.0", () => console.log("VK ID auth service listening on " + PORT));
async function shutdown() {
  server.close();
  await pool.end();
}
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
