// МУЛЬТИК ТВ — minimal zero-dependency Node.js server.
// Serves a read-only channel status/playlist API and static HLS output.
// FFmpeg/SRS remain responsible for producing the actual live stream.
'use strict';

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');

const PORT = Number(process.env.PORT || 8080);
const ROOT = path.resolve(__dirname);
const HLS_DIR = path.resolve(process.env.HLS_DIR || path.join(ROOT, 'hls'));

function send(res, status, body, type = 'application/json; charset=utf-8') {
  res.writeHead(status, {
    'Content-Type': type,
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    'Access-Control-Allow-Origin': '*'
  });
  res.end(res.req && res.req.method === 'HEAD' ? undefined : body);
}

function safeFile(base, requestPath) {
  let decoded;
  try { decoded = decodeURIComponent(requestPath); } catch { return null; }
  const candidate = path.resolve(base, '.' + decoded);
  return candidate.startsWith(base + path.sep) ? candidate : null;
}

const server = http.createServer(async (req, res) => {
  let url;
  try { url = new URL(req.url, 'http://localhost'); } catch {
    return send(res, 400, JSON.stringify({ error: 'Bad request URL' }));
  }

  if (req.method !== 'GET' && req.method !== 'HEAD') {
    return send(res, 405, JSON.stringify({ error: 'Method not allowed' }));
  }

  if (url.pathname === '/health') {
    return send(res, 200, JSON.stringify({
      service: 'МУЛЬТИК ТВ Cloud',
      status: 'online',
      stream: fs.existsSync(path.join(HLS_DIR, 'live.m3u8')) ? 'playlist-found' : 'waiting-for-stream',
      note: 'Online means this Node process is running; it does not guarantee a live video signal.'
    }));
  }

  if (url.pathname === '/api/channel') {
    const playlist = path.join(HLS_DIR, 'live.m3u8');
    const exists = fs.existsSync(playlist);
    return send(res, 200, JSON.stringify({
      channel: 'МУЛЬТИК ТВ',
      server: 'online',
      broadcast: exists ? 'playlist-found' : 'offline',
      playlist: exists ? '/hls/live.m3u8' : null,
      updatedAt: new Date().toISOString()
    }));
  }

  if (req.method === 'GET' && url.pathname === '/api/discovery') {
    const query = (url.searchParams.get('q') || 'русские мультфильмы общественное достояние').trim().slice(0, 100);
    if (!query) return send(res, 400, JSON.stringify({ error: 'Укажите поисковый запрос q' }));
    try {
      const params = new URLSearchParams({
        q: 'mediatype:movies AND (' + query.replace(/[+{}\\[\\]^"~*?:\\\\]/g, ' ') + ')',
        fl: 'identifier,title,description,year,creator,licenseurl,rights',
        rows: '20', page: '1', output: 'json'
      });
      const response = await fetch('https://archive.org/advancedsearch.php?' + params.toString(), {
        headers: { 'User-Agent': 'MultikTV-Catalog/1.0 (metadata discovery)' },
        signal: AbortSignal.timeout(10000)
      });
      if (!response.ok) throw new Error('Каталог временно недоступен');
      const payload = await response.json();
      const docs = payload.response && Array.isArray(payload.response.docs) ? payload.response.docs : [];
      return send(res, 200, JSON.stringify({
        source: 'Internet Archive metadata search',
        results: docs.map(item => ({
          title: item.title || item.identifier,
          year: item.year || null,
          creator: item.creator || null,
          identifier: item.identifier,
          page: 'https://archive.org/details/' + encodeURIComponent(item.identifier),
          rights: item.rights || null,
          license: item.licenseurl || null,
          requiresRightsReview: true,
          note: 'Метаданные не доказывают право на публичную трансляцию. Проверьте лицензию и условия конкретного материала.'
        }))
      }));
    } catch (error) {
      return send(res, 502, JSON.stringify({ error: 'Не удалось выполнить поиск в каталоге', detail: error.message }));
    }
  }

  if (url.pathname.startsWith('/hls/')) {
    const file = safeFile(HLS_DIR, url.pathname.slice(4));
    if (!file) return send(res, 400, JSON.stringify({ error: 'Invalid path' }));
    fs.stat(file, (err, stat) => {
      if (err || !stat.isFile()) return send(res, 404, JSON.stringify({ error: 'Stream not found' }));
      const ext = path.extname(file).toLowerCase();
      const type = ext === '.m3u8' ? 'application/vnd.apple.mpegurl'
        : ext === '.ts' ? 'video/mp2t'
        : ext === '.m4s' ? 'video/iso.segment'
        : 'application/octet-stream';
      res.writeHead(200, {
        'Content-Type': type,
        'Cache-Control': ext === '.m3u8' ? 'no-store' : 'public, max-age=30',
        'Access-Control-Allow-Origin': '*',
        'X-Content-Type-Options': 'nosniff'
      });
      if (req.method === 'HEAD') return res.end();
      fs.createReadStream(file).pipe(res);
    });
    return;
  }

  send(res, 200, JSON.stringify({
    name: 'МУЛЬТИК ТВ Cloud',
    endpoints: ['/health', '/api/channel', '/api/discovery?q=cartoons', '/hls/live.m3u8'],
    message: 'Server is ready. Add a valid HLS output to the hls directory to serve a stream.'
  }));
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`МУЛЬТИК ТВ Cloud listening on port ${PORT}`);
  console.log(`HLS directory: ${HLS_DIR}`);
});
