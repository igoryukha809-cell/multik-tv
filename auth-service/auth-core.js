import { createHash, randomBytes, timingSafeEqual } from "node:crypto";

export const SESSION_COOKIE = "__Secure-vkid_session";
export const SESSION_TTL_SECONDS = 60 * 60 * 24 * 7;

export function sha256(value) {
  return createHash("sha256").update(String(value), "utf8").digest("hex");
}

export function randomToken(bytes = 32) {
  return randomBytes(bytes).toString("base64url");
}

export function safeEqual(a, b) {
  const left = Buffer.from(String(a ?? ""));
  const right = Buffer.from(String(b ?? ""));
  return left.length === right.length && left.length > 0 && timingSafeEqual(left, right);
}

export function parseCookies(header = "") {
  const result = Object.create(null);
  for (const part of String(header).split(";")) {
    const index = part.indexOf("=");
    if (index < 1) continue;
    const key = part.slice(0, index).trim();
    const value = part.slice(index + 1).trim();
    if (!Object.hasOwn(result, key)) {
      try { result[key] = decodeURIComponent(value); }
      catch { result[key] = ""; }
    }
  }
  return result;
}

export function parseAdminIds(value = "") {
  return new Set(String(value).split(",").map(x => x.trim()).filter(x => /^\d+$/.test(x)));
}

export function getVerifiedVkUserId(payload) {
  const id = payload?.user?.user_id;
  if ((typeof id !== "string" && typeof id !== "number") || !/^\d+$/.test(String(id))) {
    throw new Error("VK ID did not return a valid numeric user ID");
  }
  return String(id);
}

export function sessionCookie(value, domain, maxAge = SESSION_TTL_SECONDS) {
  const cookieDomain = String(domain || "").trim();
  if (!/^\.[a-z0-9.-]+$/i.test(cookieDomain) || cookieDomain.includes("..")) throw new Error("SESSION_COOKIE_DOMAIN must be a shared parent domain such as .example.com");
  return `${SESSION_COOKIE}=${encodeURIComponent(value)}; Domain=${cookieDomain}; Path=/; Max-Age=${maxAge}; HttpOnly; Secure; SameSite=Lax`;
}

export function clearSessionCookie(domain) {
  const cookieDomain = String(domain || "").trim();
  if (!/^\.[a-z0-9.-]+$/i.test(cookieDomain) || cookieDomain.includes("..")) throw new Error("Invalid session cookie domain");
  return `${SESSION_COOKIE}=; Domain=${cookieDomain}; Path=/; Max-Age=0; HttpOnly; Secure; SameSite=Lax`;
}
