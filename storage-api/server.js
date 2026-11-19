import express from "express";
import helmet from "helmet";
import { randomUUID } from "node:crypto";
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

const app = express();
app.disable("x-powered-by");
app.use(helmet({ crossOriginResourcePolicy: { policy: "cross-origin" } }));
app.use(express.json({ limit: "16kb" }));

const required = ["R2_ACCOUNT_ID","R2_ACCESS_KEY_ID","R2_SECRET_ACCESS_KEY","R2_BUCKET","UPLOAD_API_TOKEN","PUBLIC_MEDIA_BASE_URL"];
const missing = required.filter(k => !process.env[k]);
const port = Number(process.env.PORT || 10000);
const allowedOrigins = (process.env.ALLOWED_ORIGINS || "https://igoryukha809-cell.github.io").split(",").map(x => x.trim()).filter(Boolean);
const s3 = missing.length ? null : new S3Client({
  region: "auto",
  endpoint: `https://${process.env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com`,
  credentials: { accessKeyId: process.env.R2_ACCESS_KEY_ID, secretAccessKey: process.env.R2_SECRET_ACCESS_KEY }
});

app.use((req,res,next) => {
  const origin = req.headers.origin;
  if (origin && allowedOrigins.includes(origin)) {
    res.setHeader("Access-Control-Allow-Origin", origin);
    res.setHeader("Vary", "Origin");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
    res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  }
  if (req.method === "OPTIONS") return res.sendStatus(204);
  next();
});

app.get("/health", (_req,res) => res.json({
  ok: missing.length === 0,
  configured: missing.length === 0,
  missing: missing.map(x => x.replace(/ACCESS_KEY|SECRET|TOKEN/,"CREDENTIAL"))
}));

app.post("/upload-url", async (req,res) => {
  if (missing.length) return res.status(503).json({ error: "Хранилище ещё не настроено." });
  if (!req.headers.authorization || req.headers.authorization !== `Bearer ${process.env.UPLOAD_API_TOKEN}`) {
    return res.status(401).json({ error: "Нет разрешения на загрузку." });
  }
  const { filename, contentType, size } = req.body || {};
  const types = new Set(["video/mp4","video/webm","video/quicktime"]);
  if (typeof filename !== "string" || filename.length > 180 || !types.has(contentType) ||
      !Number.isSafeInteger(size) || size < 1 || size > 5 * 1024 * 1024 * 1024) {
    return res.status(400).json({ error: "Поддерживаются MP4, WebM и MOV размером до 5 ГБ." });
  }
  const ext = ({ "video/mp4":"mp4", "video/webm":"webm", "video/quicktime":"mov" })[contentType];
  const key = `uploads/${new Date().toISOString().slice(0,10)}/${randomUUID()}.${ext}`;
  try {
    const command = new PutObjectCommand({ Bucket: process.env.R2_BUCKET, Key: key, ContentType: contentType });
    const uploadUrl = await getSignedUrl(s3, command, { expiresIn: 900 });
    const base = process.env.PUBLIC_MEDIA_BASE_URL.replace(/\/$/,"");
    res.json({ uploadUrl, key, publicUrl: `${base}/${key}`, expiresIn: 900, maxBytes: 5 * 1024 * 1024 * 1024 });
  } catch (error) {
    console.error("presign_failed", error?.name || "unknown");
    res.status(500).json({ error: "Не удалось подготовить загрузку." });
  }
});

app.listen(port, "0.0.0.0", () => console.log(`storage-api listening on ${port}; configured=${missing.length === 0}`));
