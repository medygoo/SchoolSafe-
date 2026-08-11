// ════════════════════════════════════════════════════════════════════════════
//  SchoolSafe — Service Worker  v4
//  Cache offline + Background Sync
// ════════════════════════════════════════════════════════════════════════════

const CACHE_PREFIX = 'schoolsafe-';
const CACHE = `${CACHE_PREFIX}v69`;

// Ressources à mettre en cache au démarrage
const PRECACHE = [
  './index.html',
  './manifest.json',
  './icon-192.png',
  './icon-512.png',
  // Librairies CDN critiques — disponibles hors-ligne après 1er chargement
  'https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js',
  'https://cdn.jsdelivr.net/npm/jsqr@1.4.0/dist/jsQR.min.js',
  'https://cdnjs.cloudflare.com/ajax/libs/jszip/3.10.1/jszip.min.js',
  'https://cdnjs.cloudflare.com/ajax/libs/html2pdf.js/0.10.1/html2pdf.bundle.min.js',
  'https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js',
];

// Domaines CDN servis en Cache-First (stale-while-revalidate)
const CDN_HOSTS = ['cdnjs.cloudflare.com', 'cdn.jsdelivr.net'];

// Domaines qui ne passent jamais par le cache
const BYPASS_HOSTS = [
  'supabase.co',
  'script.google.com',
  'script.googleusercontent.com',
  'fonts.googleapis.com',
  'fonts.gstatic.com',
];

// Extensions qui ne sont jamais mises en cache (toujours réseau)
const BYPASS_EXTENSIONS = ['.mp4', '.webm', '.mov', '.avi'];

// Fichiers toujours servis du réseau : un outil de diagnostic mis en cache
// diagnostiquerait sa propre version périmée.
const BYPASS_PATHS = ['diagnostic.html', 'auth.html'];

// ── Installation ──────────────────────────────────────────────────────────────
self.addEventListener('install', evt => {
  evt.waitUntil(
    caches.open(CACHE)
      .then(cache => cache.addAll(PRECACHE).catch(err => {
        console.warn('[SW] precache partial:', err.message);
      }))
      .then(() => self.skipWaiting())
  );
});

// ── Activation : supprime uniquement les anciens caches SchoolSafe ──────────
self.addEventListener('activate', evt => {
  evt.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys.filter(k => k.startsWith(CACHE_PREFIX) && k !== CACHE).map(k => {
          console.log('[SW] suppression ancien cache:', k);
          return caches.delete(k);
        })
      ))
      .then(() => self.clients.claim())
  );
});

// ── Fetch : Network-First pour l'interface, Cache-First pour le reste ─────────
self.addEventListener('fetch', evt => {
  const url = new URL(evt.request.url);

  // Bypass pour les API externes
  if (BYPASS_HOSTS.some(h => url.hostname.includes(h))) return;

  // Cache-First pour les librairies CDN — disponibles hors-ligne, mises à jour en arrière-plan
  if (CDN_HOSTS.some(h => url.hostname.includes(h))) {
    evt.respondWith(
      caches.match(evt.request).then(cached => {
        const netFetch = fetch(evt.request).then(resp => {
          if (resp.ok) caches.open(CACHE).then(c => c.put(evt.request, resp.clone()));
          return resp;
        }).catch(() => cached);
        return cached || netFetch;
      })
    );
    return;
  }

  // Bypass pour POST/PATCH/DELETE
  if (evt.request.method !== 'GET') return;

  // Bypass pour les vidéos — toujours chargées du réseau, jamais cachées
  if (BYPASS_EXTENSIONS.some(ext => url.pathname.endsWith(ext))) return;

  // Bypass pour les pages outil (diagnostic/auth) — jamais servies du cache
  if (BYPASS_PATHS.some(p => url.pathname.endsWith(p))) return;

  // Network-First réel pour toute navigation / index.html.
  // Une ancienne interface ne doit jamais être préférée quand le réseau fonctionne.
  if (evt.request.mode === 'navigate' || url.pathname.endsWith('/') || url.pathname.endsWith('index.html')) {
    // AMÉLIORÉ, PAS REMPLACÉ — 11 août 2026.
    //
    // Le Network-First de ChatGPT corrige une vraie panne : le cache resservait
    // l'ancienne interface, donc des corrections publiées n'atteignaient
    // personne. On le garde entier.
    //
    // Ce qu'il coûte, et qu'on lui ajoute : sur un réseau de Kinshasa qui
    // répond en dix secondes, `fetch` ne rend la main qu'au bout de dix
    // secondes — l'application reste sur un écran blanc alors qu'une version
    // parfaitement utilisable dort dans le cache. Un `catch` ne s'en aperçoit
    // pas : une requête LENTE n'est pas une requête en ÉCHEC.
    //
    // On borne donc l'attente à 4 secondes : passé ce délai on sert le cache
    // pour que l'école travaille, ET on laisse la requête réseau finir pour
    // que le cache soit à jour au prochain démarrage. La fraîcheur est
    // préservée, l'attente ne l'est plus.
    const AVEC_DELAI = (requete, ms) => {
      const reseau = fetch(requete).then(async response => {
        if (response.ok) {
          const cache = await caches.open(CACHE);
          await cache.put(requete, response.clone());
        }
        return response;
      });
      const repli = new Promise(resolve => setTimeout(async () => {
        const cached = await caches.match(requete) || await caches.match('./index.html');
        resolve(cached || null);
      }, ms));
      return Promise.race([reseau, repli]).then(r => r || reseau);
    };
    evt.respondWith(
      AVEC_DELAI(evt.request, 4000)
        .then(async response => {
          if (response.ok) {
            const cache = await caches.open(CACHE);
            await cache.put(evt.request, response.clone());
          }
          return response;
        })
        .catch(async () => {
          const direct = await caches.match(evt.request);
          if (direct) return direct;
          return caches.match('./index.html');
        })
    );
    return;
  }

  // Cache-First avec fallback réseau pour les autres ressources
  evt.respondWith(
    caches.match(evt.request).then(cached => {
      if (cached) return cached;
      return fetch(evt.request).then(response => {
        if (response.ok && url.origin === self.location.origin) {
          const clone = response.clone();
          caches.open(CACHE).then(cache => cache.put(evt.request, clone));
        }
        return response;
      }).catch(() => {
        if (evt.request.mode === 'navigate') {
          return caches.match('./index.html');
        }
      });
    })
  );
});

// ── Messages du client ────────────────────────────────────────────────────────
self.addEventListener('message', evt => {
  if (evt.data?.type === 'SKIP_WAITING') self.skipWaiting();
  if (evt.data?.type === 'CACHE_BUST') {
    caches.delete(CACHE).then(() => self.skipWaiting());
  }
});

// ── Background Sync : flush différé quand la connexion revient (même onglet fermé) ──
self.addEventListener('sync', evt => {
  if (evt.tag === 'schoolsafe-sync') {
    evt.waitUntil(
      clients.matchAll({ type: 'window', includeUncontrolled: true }).then(cs => {
        // Déléguer au premier onglet ouvert — il a accès au cache chiffré et à pushSync
        if (cs.length > 0) cs[0].postMessage({ type: 'BG_SYNC_REQUEST' });
        // Si aucun onglet ouvert, flush au prochain démarrage via l'event 'online'
      })
    );
  }
});

// ── Web Push : afficher la notification reçue depuis le serveur ──────────────
self.addEventListener('push', evt => {
  let data = { title: 'SchoolSafe', body: 'Nouvelle notification', url: './', urgent: false };
  try { if (evt.data) data = { ...data, ...evt.data.json() }; } catch(_) {}
  evt.waitUntil(
    self.registration.showNotification(data.title, {
      body: data.body,
      icon: './icon-192.png',
      badge: './icon-192.png',
      tag: data.tag || 'schoolsafe-notif',
      data: { url: data.url || './' },
      requireInteraction: !!data.urgent,
      vibrate: data.urgent ? [200, 100, 200] : [100],
    })
  );
});

// ── Clic sur une notification push : ouvrir ou focuser l'app ────────────────
self.addEventListener('notificationclick', evt => {
  evt.notification.close();
  const url = evt.notification.data?.url || './';
  evt.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then(cs => {
      const existing = cs.find(c => /index\.html|^\/$/.test(new URL(c.url).pathname));
      if (existing) { existing.focus(); return; }
      return clients.openWindow(url);
    })
  );
});
