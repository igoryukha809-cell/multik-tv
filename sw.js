const CACHE = 'multik-tv-shell-v5';
const CORE = [
  './',
  './index.html',
  './manifest.webmanifest',
  './icon.svg',
  './styles.css',
  './tv.html',
  './station.html',
  './channel.html',
  './cloud.html',
  './online-catalog.html',
  './free-broadcast.html',
  './stream.html',
  './montage-studio.html',
  './voice-studio.html',
  './ai-studio.html'
];
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(CORE)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key !== CACHE).map(key => caches.delete(key)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET' || new URL(request.url).origin !== self.location.origin) return;
  const url = new URL(request.url);
  if (url.pathname.endsWith('/broadcast/status.json')) {
    event.respondWith(fetch(request).catch(() => caches.match(request)));
    return;
  }
  event.respondWith(caches.match(request).then(cached => cached || fetch(request).then(response => {
    if (response.ok && response.type === 'basic') {
      const copy = response.clone();
      caches.open(CACHE).then(cache => cache.put(request, copy));
    }
    return response;
  })));
});
