// GeminiVPN Service Worker v1.0.0
const CACHE_NAME = 'geminivpn-v1';
const STATIC_ASSETS = [
  '/',
  '/index.html',
  '/manifest.json',
  '/geminivpn-logo.png',
  '/hero_city.jpg',
  '/tunnel_road.jpg',
  '/hooded_figure.jpg',
  '/server_room.jpg',
  '/neon_corridor.jpg',
  '/server_lock.jpg',
  '/devices_city.jpg',
  '/headset_support.jpg',
  '/final_city.jpg',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(STATIC_ASSETS))
  );
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((cacheNames) =>
      Promise.all(
        cacheNames.filter((name) => name !== CACHE_NAME).map((name) => caches.delete(name))
      )
    )
  );
  self.clients.claim();
});

self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);

  if (request.method !== 'GET' || url.origin !== location.origin) return;

  // Images: cache-first
  if (request.destination === 'image') {
    event.respondWith(
      caches.match(request).then(
        (cached) =>
          cached ||
          fetch(request).then((response) => {
            const clone = response.clone();
            caches.open(CACHE_NAME).then((cache) => cache.put(request, clone));
            return response;
          })
      )
    );
    return;
  }

  // JS/CSS: network-first
  if (request.destination === 'script' || request.destination === 'style') {
    event.respondWith(
      fetch(request)
        .then((response) => {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(request, clone));
          return response;
        })
        .catch(() => caches.match(request))
    );
    return;
  }

  // HTML: network-first, fallback to index.html (SPA)
  if (request.destination === 'document') {
    event.respondWith(fetch(request).catch(() => caches.match('/index.html')));
  }
});
