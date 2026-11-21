import { chromium } from "playwright";
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { extname, resolve, sep } from "node:path";

const root = process.cwd();
const server = createServer(async (req, res) => {
  try {
    const pathname = decodeURIComponent(new URL(req.url, "http://127.0.0.1").pathname);
    const file = resolve(root, "." + pathname);
    if (!file.startsWith(root + sep) && file !== resolve(root, "ai-studio.html")) {
      res.writeHead(403).end(); return;
    }
    let body = await readFile(file);
    if (pathname === "/ai-studio.html") {
      body = Buffer.from(body.toString("utf8").replace(
        '<script type="module" src="./admin-guard.js"></script>', ""
      ));
    }
    const types = { ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8" };
    res.writeHead(200, { "Content-Type": types[extname(file)] || "application/octet-stream" });
    res.end(body);
  } catch {
    res.writeHead(404).end("Not found");
  }
});
await new Promise(resolveListen => server.listen(4173, "127.0.0.1", resolveListen));

const browser = await chromium.launch({ headless: true, args: ["--autoplay-policy=no-user-gesture-required", "--disable-web-security"] });
try {
  const page = await browser.newPage();
  page.on("pageerror", error => console.error("PAGE_ERROR", error.message));
  await page.addInitScript(() => {
    const originalPlay = HTMLMediaElement.prototype.play;
    HTMLMediaElement.prototype.play = function (...args) {
      window.__lastAudio = this;
      return originalPlay.apply(this, args);
    };
  });
  await page.goto("http://127.0.0.1:4173/ai-studio.html", { waitUntil: "domcontentloaded" });
  await page.locator('.tab[data-tab="voice"]').click();
  await page.locator("#voice-text").fill("Проверка воспроизведения русского голоса Piper.");
  await page.locator("#speak").click();
  await page.waitForFunction(() => {
    const audio = window.__lastAudio;
    return audio && !audio.paused && audio.currentTime > 0.35;
  }, null, { timeout: 45000 });
  const result = await page.evaluate(() => ({
    currentTime: Number(window.__lastAudio.currentTime.toFixed(2)),
    duration: Number(window.__lastAudio.duration.toFixed(2)),
    paused: window.__lastAudio.paused,
    source: window.__lastAudio.currentSrc.startsWith("blob:") ? "blob WAV" : "unexpected source"
  }));
  if (result.paused || result.source !== "blob WAV") throw new Error(JSON.stringify(result));
  console.log("PIPER_BROWSER_PLAYBACK_OK", result);
} finally {
  await browser.close();
  await new Promise(resolveClose => server.close(resolveClose));
}
