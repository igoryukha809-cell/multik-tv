import express from "express";
import helmet from "helmet";
import multer from "multer";
import path from "node:path";
import os from "node:os";
import fs from "node:fs/promises";
import { createReadStream } from "node:fs";
import { randomUUID, timingSafeEqual } from "node:crypto";
import { S3Client, ListObjectsV2Command, DeleteObjectCommand, GetObjectCommand } from "@aws-sdk/client-s3";
import { Upload } from "@aws-sdk/lib-storage";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

const app = express();
app.disable("x-powered-by");
app.use(helmet({ crossOriginResourcePolicy: { policy: "cross-origin" } }));
app.use(express.json({ limit: "64kb" }));

const PORT = Number(process.env.PORT || 10000);
const TOKEN = process.env.UPLOAD_API_TOKEN || "";
const BUCKET = process.env.TIGRIS_BUCKET || process.env.AWS_S3_BUCKET || "";
const ENDPOINT = process.env.TIGRIS_ENDPOINT || "https://t3.storage.dev";
const ACCESS_KEY = process.env.AWS_ACCESS_KEY_ID || process.env.TIGRIS_ACCESS_KEY_ID || "";
const SECRET_KEY = process.env.AWS_SECRET_ACCESS_KEY || process.env.TIGRIS_SECRET_ACCESS_KEY || "";
const ORIGINS = (process.env.ALLOWED_ORIGINS || "https://igoryukha809-cell.github.io").split(",").map(x => x.trim()).filter(Boolean);
const TMP = path.join(os.tmpdir(), "multik-tv-uploads");
await fs.mkdir(TMP, { recursive: true });

const configured = Boolean(BUCKET && ACCESS_KEY && SECRET_KEY);
const s3 = configured ? new S3Client({
  endpoint: ENDPOINT,
  region: "auto",
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

function auth(req, res, next) {
  const got = (req.headers.authorization || "").replace(/^Bearer /, "");
  if (!TOKEN || got.length !== TOKEN.length || !timingSafeEqual(Buffer.from(got), Buffer.from(TOKEN))) {
    return res.status(401).json({ error: "Неверный пароль загрузчика." });
  }
  next();
}
function requireStorage(_req, res, next) {
  if (!configured || !s3) return res.status(503).json({ error: "Tigris ещё не настроен. Проверьте переменные окружения сервера." });
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
  storage: "tigris",
  configured,
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

app.get("/api/videos", requireStorage, async (_req, res, next) => {
  try { res.json(await listVideos()); } catch (err) { next(err); }
});

app.get("/api/playlist", requireStorage, async (_req, res, next) => {
  try { res.json({ channel: "МУЛЬТИК ТВ", items: await listVideos() }); } catch (err) { next(err); }
});

app.post("/api/upload", auth, requireStorage, upload.single("video"), async (req, res, next) => {
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

app.delete("/api/videos/:id", auth, requireStorage, async (req, res, next) => {
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

app.listen(PORT, "0.0.0.0", () => console.log("МУЛЬТИК ТВ API с Tigris запущен на порту " + PORT));
