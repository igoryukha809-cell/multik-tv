import express from "express";
import helmet from "helmet";
import multer from "multer";
import path from "node:path";
import os from "node:os";
import fs from "node:fs/promises";
import { createReadStream } from "node:fs";
import { randomUUID, randomBytes, createHash, timingSafeEqual } from "node:crypto";
import { S3Client, ListObjectsV2Command, DeleteObjectCommand, GetObjectCommand, PutObjectCommand } from "@aws-sdk/client-s3";
import { Upload } from "@aws-sdk/lib-storage";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { createRemoteJWKSet, jwtVerify } from "jose";

const app = express();
app.disable("x-powered-by");
app.use(helmet({ crossOriginResourcePolicy: { policy: "cross-origin" } }));
app.use(express.json({ limit: "64kb" }));

const PORT = Number(process.env.PORT || 10000);
const TOKEN = process.env.UPLOAD_API_TOKEN || "";
const ADMIN_EMAIL = (process.env.ADMIN_EMAIL || "").trim().toLowerCase();
const SUPABASE_URL = (process.env.SUPABASE_URL || "").replace(/\/$/, "");
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || "";
const LOGTO_ENDPOINT = (process.env.LOGTO_ENDPOINT || "").replace(/\/$/, "");
const LOGTO_ISSUER = LOGTO_ENDPOINT ? LOGTO_ENDPOINT + "/oidc" : "";
const LOGTO_API_RESOURCE = (process.env.LOGTO_API_RESOURCE || "").trim();
const LOGTO_JWKS = LOGTO_ENDPOINT ? createRemoteJWKSet(new URL(LOGTO_ENDPOINT + "/oidc/jwks")) : null;
const DATA_DIR = process.env.DATA_DIR || "./data";
const ACCESS_KEYS_FILE = process.env.ACCESS_KEYS_FILE || path.join(DATA_DIR, "access-keys.json");
await fs.mkdir(path.dirname(ACCESS_KEYS_FILE), { recursive: true });

async function readAccessKeys() {
  // Railway Object Storage keeps admin keys across deploys and restarts.
  if (configured && s3) {
    try {
      const result = await s3.send(new GetObjectCommand({ Bucket: BUCKET, Key: "system/access-keys.json" }));
      const raw = await result.Body.transformToString();
      const parsed = JSON.parse(raw);
      return Array.isArray(parsed) ? parsed : [];
    } catch (err) {
      if (err.name !== "NoSuchKey" && err.$metadata?.httpStatusCode !== 404) throw err;
    }
  }
  try {
    const raw = await fs.readFile(ACCESS_KEYS_FILE, "utf8");
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch (err) {
    if (err.code === "ENOENT") return [];
    throw err;
  }
}
async function writeAccessKeys(keys) {
  const body = JSON.stringify(keys, null, 2);
  if (configured && s3) {
    await s3.send(new PutObjectCommand({
      Bucket: BUCKET,
      Key: "system/access-keys.json",
      Body: body,
      ContentType: "application/json"
    }));
    return;
  }
  const temp = ACCESS_KEYS_FILE + ".tmp";
  await fs.writeFile(temp, body, { mode: 0o600 });
  await fs.rename(temp, ACCESS_KEYS_FILE);
}
function hashAccessKey(value) {
  return createHash("sha256").update(value).digest("hex");
}
function safeEqual(a, b) {
  const left = Buffer.from(String(a));
  const right = Buffer.from(String(b));
  return left.length === right.length && timingSafeEqual(left, right);
}
async function adminAuth(req, res, next) {
  const supplied = (req.headers.authorization || "").replace(/^Bearer /, "");
  if (!supplied || !ADMIN_EMAIL) return res.status(401).json({ error: "Вход администратора ещё не настроен." });
  try {
    if (LOGTO_ENDPOINT && LOGTO_API_RESOURCE && LOGTO_JWKS) {
      const { payload } = await jwtVerify(supplied, LOGTO_JWKS, {
        issuer: LOGTO_ISSUER,
        audience: LOGTO_API_RESOURCE,
        algorithms: ["RS256"]
      });
      const infoResponse = await fetch(LOGTO_ENDPOINT + "/oidc/me", {
        headers: { Authorization: "Bearer " + supplied }
      });
      if (!infoResponse.ok) return res.status(401).json({ error: "Logto не подтвердил профиль пользователя." });
      const user = await infoResponse.json();
      if (!user.email || user.email.toLowerCase() !== ADMIN_EMAIL || user.email_verified !== true) {
        return res.status(403).json({ error: "Эта подтверждённая почта не имеет прав администратора." });
      }
      req.adminUser = { id: payload.sub, email: user.email };
      return next();
    }
    if (!SUPABASE_URL || !SUPABASE_ANON_KEY) return res.status(401).json({ error: "Настройте Logto или Supabase Auth на сервере." });
    const response = await fetch(SUPABASE_URL + "/auth/v1/user", {
      headers: { apikey: SUPABASE_ANON_KEY, Authorization: "Bearer " + supplied }
    });
    if (!response.ok) return res.status(401).json({ error: "Сессия входа недействительна. Войдите снова." });
    const user = await response.json();
    if (!user.email || user.email.toLowerCase() !== ADMIN_EMAIL || !user.email_confirmed_at) {
      return res.status(403).json({ error: "Эта подтверждённая почта не имеет прав администратора." });
    }
    req.adminUser = { id: user.id, email: user.email };
    next();
  } catch (err) {
    if (LOGTO_ENDPOINT && LOGTO_API_RESOURCE) return res.status(401).json({ error: "Токен Logto недействителен или не предназначен для этого API." });
    next(err);
  }
}
const BUCKET = process.env.B2_BUCKET || process.env.AWS_S3_BUCKET || "";
const ENDPOINT = process.env.B2_ENDPOINT || process.env.AWS_S3_ENDPOINT || "";
const ACCESS_KEY = process.env.AWS_ACCESS_KEY_ID || "";
const SECRET_KEY = process.env.AWS_SECRET_ACCESS_KEY || "";
const ORIGINS = (process.env.ALLOWED_ORIGINS || "https://igoryukha809-cell.github.io").split(",").map(x => x.trim()).filter(Boolean);
const TMP = path.join(os.tmpdir(), "multik-tv-uploads");
await fs.mkdir(TMP, { recursive: true });

const REGION = process.env.B2_REGION || "";
const configured = Boolean(BUCKET && ENDPOINT && REGION && ACCESS_KEY && SECRET_KEY);
const s3 = configured ? new S3Client({
  endpoint: ENDPOINT,
  region: REGION,
  credentials: { accessKeyId: ACCESS_KEY, secretAccessKey: SECRET_KEY }
}) : null;

app.use((req, res, next) => {
  const origin = req.headers.origin;
  if (origin && ORIGINS.includes(origin)) {
    res.setHeader("Access-Control-Allow-Origin", origin);
    res.setHeader("Vary", "Origin");
    res.setHeader("Access-Control-Allow-Headers", "Authorization,Content-Type");
    res.setHeader("Access-Control-Allow-Methods", "GET,POST,DELETE,OPTIONS");
  }
  if (req.method === "OPTIONS") return res.sendStatus(204);
  next();
});

function auth(requiredScope = "upload") {
  return async (req, res, next) => {
    const got = (req.headers.authorization || "").replace(/^Bearer /, "");
    // Старый UPLOAD_API_TOKEN разрешён только для загрузки; удаление требует ключ scope=api.
    if (requiredScope === "upload" && TOKEN && safeEqual(got, TOKEN)) return next();
    if (!got) return res.status(401).json({ error: "Нужен ключ доступа." });
    try {
      const digest = hashAccessKey(got);
      const keys = await readAccessKeys();
      const record = keys.find(item => item.hash === digest && !item.revokedAt &&
        (item.scope === requiredScope || item.scope === "api"));
      if (!record) return res.status(401).json({ error: "Ключ недействителен или отключён." });
      record.lastUsedAt = new Date().toISOString();
      await writeAccessKeys(keys);
      next();
    } catch (err) { next(err); }
  };
}
function requireStorage(_req, res, next) {
  if (!configured || !s3) return res.status(503).json({ error: "Backblaze B2 ещё не настроен. Проверьте переменные окружения сервера." });
  next();
}

const upload = multer({
  dest: TMP,
  limits: { fileSize: 2 * 1024 * 1024 * 1024 },
  fileFilter: (_req, file, cb) => {
    const ok = new Set([".mp4", ".webm", ".mov"]).has(path.extname(file.originalname).toLowerCase());
    cb(ok ? null : new Error("Разрешены MP4, WebM и MOV."), ok);
  }
});

app.get("/", (_req, res) => res.json({ service: "МУЛЬТИК ТВ Storage API", health: "/health", videos: "/api/videos" }));

app.get("/health", (_req, res) => res.json({
  ok: true,
  storage: "backblaze-b2",
  configured,
  accessKeyManager: Boolean(ADMIN_EMAIL && ((LOGTO_ENDPOINT && LOGTO_API_RESOURCE) || (SUPABASE_URL && SUPABASE_ANON_KEY))),
  bucketConfigured: Boolean(BUCKET),
  credentialsConfigured: Boolean(ACCESS_KEY && SECRET_KEY)
}));

async function listVideos() {
  const rows = [];
  let ContinuationToken;
  do {
    const page = await s3.send(new ListObjectsV2Command({ Bucket: BUCKET, Prefix: "videos/", ContinuationToken }));
    for (const obj of page.Contents || []) {
      if (!obj.Key || obj.Key.endsWith("/")) continue;
      const command = new GetObjectCommand({ Bucket: BUCKET, Key: obj.Key });
      const url = await getSignedUrl(s3, command, { expiresIn: 3600 });
      rows.push({
        id: obj.Key,
        name: decodeURIComponent(obj.Key.split("/").pop()),
        size: obj.Size || 0,
        createdAt: obj.LastModified ? obj.LastModified.toISOString() : null,
        url
      });
    }
    ContinuationToken = page.IsTruncated ? page.NextContinuationToken : undefined;
  } while (ContinuationToken);
  return rows.sort((a, b) => (a.createdAt || "").localeCompare(b.createdAt || ""));
}


// Собственная система ключей доступа МУЛЬТИК ТВ.
// Полный ключ показывается только один раз; в файле хранится только SHA-256-хеш.
app.get("/api/admin/keys", adminAuth, async (_req, res, next) => {
  try {
    const keys = await readAccessKeys();
    res.json(keys.map(({ id, label, scope, createdAt, lastUsedAt, revokedAt }) =>
      ({ id, label, scope, createdAt, lastUsedAt: lastUsedAt || null, revokedAt: revokedAt || null })));
  } catch (err) { next(err); }
});

app.post("/api/admin/keys", adminAuth, async (req, res, next) => {
  try {
    const label = String(req.body?.label || "").trim().slice(0, 60);
    const scope = req.body?.scope;
    if (!label) return res.status(400).json({ error: "Укажите название ключа." });
    if (!["upload", "api"].includes(scope)) return res.status(400).json({ error: "Недопустимый тип ключа." });
    const keys = await readAccessKeys();
    const token = "mtv_" + randomBytes(32).toString("base64url");
    const record = {
      id: randomUUID(),
      label,
      scope,
      hash: hashAccessKey(token),
      createdAt: new Date().toISOString(),
      lastUsedAt: null,
      revokedAt: null
    };
    keys.push(record);
    await writeAccessKeys(keys);
    res.status(201).json({
      id: record.id,
      label: record.label,
      scope: record.scope,
      createdAt: record.createdAt,
      key: token,
      warning: "Скопируйте ключ сейчас: повторно показать его нельзя."
    });
  } catch (err) { next(err); }
});

app.delete("/api/admin/keys/:id", adminAuth, async (req, res, next) => {
  try {
    const keys = await readAccessKeys();
    const record = keys.find(item => item.id === req.params.id);
    if (!record) return res.status(404).json({ error: "Ключ не найден." });
    if (!record.revokedAt) record.revokedAt = new Date().toISOString();
    await writeAccessKeys(keys);
    res.json({ ok: true, id: record.id, revokedAt: record.revokedAt });
  } catch (err) { next(err); }
});

app.get("/api/videos", requireStorage, async (_req, res, next) => {
  try { res.json(await listVideos()); } catch (err) { next(err); }
});

app.get("/api/playlist", requireStorage, async (_req, res, next) => {
  try { res.json({ channel: "МУЛЬТИК ТВ", items: await listVideos() }); } catch (err) { next(err); }
});

app.post("/api/upload", auth("upload"), requireStorage, upload.single("video"), async (req, res, next) => {
  if (!req.file) return res.status(400).json({ error: "Файл не получен." });
  const ext = path.extname(req.file.originalname).toLowerCase();
  const key = "videos/" + randomUUID() + ext;
  try {
    await new Upload({
      client: s3,
      params: {
        Bucket: BUCKET,
        Key: key,
        Body: createReadStream(req.file.path),
        ContentLength: req.file.size,
        ContentType: req.file.mimetype || "application/octet-stream"
      },
      queueSize: 3,
      partSize: 8 * 1024 * 1024,
      leavePartsOnError: false
    }).done();
    const url = await getSignedUrl(s3, new GetObjectCommand({ Bucket: BUCKET, Key: key }), { expiresIn: 3600 });
    res.status(201).json({
      id: key,
      name: req.file.originalname,
      size: req.file.size,
      type: req.file.mimetype,
      createdAt: new Date().toISOString(),
      url
    });
  } catch (err) { next(err); }
  finally { await fs.rm(req.file.path, { force: true }).catch(() => {}); }
});

app.delete("/api/videos/:id", auth("api"), requireStorage, async (req, res, next) => {
  try {
    const key = req.params.id;
    if (!key.startsWith("videos/") || key.includes("..")) return res.status(400).json({ error: "Недопустимый идентификатор видео." });
    await s3.send(new DeleteObjectCommand({ Bucket: BUCKET, Key: key }));
    res.json({ ok: true });
  } catch (err) { next(err); }
});

app.use((err, _req, res, _next) => {
  const status = err.code === "LIMIT_FILE_SIZE" ? 413 : 400;
  res.status(status).json({ error: err.message || "Ошибка хранилища." });
});

app.listen(PORT, "0.0.0.0", () => console.log("МУЛЬТИК ТВ API с Backblaze B2 запущен на порту " + PORT));
