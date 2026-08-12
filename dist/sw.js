// ════════════════════════════════════════════════════════════════════════════
//  SchoolSafe — Service Worker  v4
//  Cache offline + Background Sync
// ════════════════════════════════════════════════════════════════════════════

const CACHE_PREFIX = 'schoolsafe-';
const CACHE = `${CACHE_PREFIX}v71`;

// Ressources à mettre en cache au démarrage
const PRECACHE = [
  './index.html',
  './manifest.json',
  './icon-192.png',
  './icon-512.png',
  // Librairies CDN critiques — disponibles hors-ligne après 1er chargement
  'https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js',
  'https://cdn.jsdelivr.net/npm/jsqr@1.4.0/dist/jsQR.min.js',
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

// ── A-T-ELLE CHANGÉ ? ────────────────────────────────────────────────────────
// On ne compare pas les corps : télécharger 2,4 Mo pour les relire octet par
// octet coûterait plus que ce qu'on économise. GitHub Pages rend un `ETag` sur
// chaque fichier ; à défaut, `Last-Modified`, puis la longueur. Si aucun des
// trois n'est là, on ne prétend PAS savoir — on ne dérange personne.
async function _aChange(ancienne, nouvelle) {
  for (const cle of ['etag', 'last-modified', 'content-length']) {
    const a = ancienne.headers.get(cle), b = nouvelle.headers.get(cle);
    if (a && b) return a !== b;
  }
  return false;
}

// Prévenir les pages ouvertes. C'est la moitié qui manquait au
// Stale-While-Revalidate : il mettait à jour et ne le disait pas.
async function _prevenirLesPages() {
  const pages = await self.clients.matchAll({ type: 'window' });
  for (const p of pages) p.postMessage({ type: 'SS_MAJ_DISPONIBLE' });
}

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

  // ── L'INTERFACE : SERVIE TOUT DE SUITE, VÉRIFIÉE DERRIÈRE ────────────────
  //
  // Trois stratégies se sont succédé ici, et chacune corrigeait la précédente
  // en cassant autre chose. La leçon est dans la succession :
  //
  //  1. Stale-While-Revalidate. Le cache d'abord, mise à jour silencieuse.
  //     Conséquence : à chaque publication, l'école voyait **l'ancienne
  //     interface au premier chargement**. Loms nous disait que ses
  //     corrections n'étaient pas en ligne — elles l'étaient, c'était le
  //     téléphone qui lui resservait la veille.
  //
  //  2. Network-First. Le réseau d'abord, cache en secours. La fraîcheur
  //     revient — et l'application reste blanche tant que le réseau n'a pas
  //     rendu 2,4 Mo. Un `catch` ne le voit pas : **une requête LENTE n'est
  //     pas une requête en ÉCHEC.**
  //
  //  3. Network-First borné à 4 s. L'écran blanc est borné, mais il reste :
  //     sur un réseau de Kinshasa, **les 4 secondes s'écoulent en entier à
  //     chaque ouverture**, alors qu'une version parfaitement utilisable
  //     dormait dans le cache depuis le début.
  //
  // Ce qui manquait aux trois : la fraîcheur et l'attente étaient traitées
  // comme un seul curseur, alors que ce sont deux problèmes.
  //
  //   · **L'attente** se règle en servant le cache IMMÉDIATEMENT. Zéro seconde.
  //   · **La fraîcheur** ne se règle pas en faisant attendre quelqu'un : elle
  //     se règle en allant chercher la nouvelle version DERRIÈRE, et en le
  //     DISANT quand elle est là.
  //
  // Le défaut du n° 1 n'était pas de servir le cache — c'était de **se taire**.
  // Une mise à jour silencieuse qui arrive au prochain démarrage est un échec
  // silencieux, celui-là même que tous nos audits traquent.
  if (evt.request.mode === 'navigate' || url.pathname.endsWith('/') || url.pathname.endsWith('index.html')) {
    evt.respondWith((async () => {
      const cache  = await caches.open(CACHE);
      const cached = await cache.match(evt.request) || await cache.match('./index.html');

      // Ce qui part au réseau, quoi qu'il arrive — mais sans que personne
      // l'attende quand une copie existe déjà.
      const reseau = fetch(evt.request).then(async reponse => {
        if (reponse && reponse.ok) {
          await cache.put(evt.request, reponse.clone());
          if (cached && await _aChange(cached, reponse)) await _prevenirLesPages();
        }
        return reponse;
      }).catch(() => null);

      if (cached) { evt.waitUntil(reseau); return cached; }

      // Premier chargement, ou cache vidé : là, il faut bien attendre.
      return (await reseau) || Response.error();
    })());
    return;
  }

  // ── LE CODE DE L'ÉCOLE, SERVI VITE MAIS JAMAIS FIGÉ ─────────────────────
  //
  // `messages-frontend-v2.js` est du CODE de production, comme `index.html` —
  // 445 lignes qui décident du routage des messages entre parents, Direction et
  // enseignants. Le Cache-First générique en dessous ne réinterroge JAMAIS le
  // réseau une fois le fichier en cache : une correction n'atteindrait personne
  // tant que son `?v=` n'est pas changé à la main.
  //
  // C'est exactement la panne qu'on vient de réparer pour l'interface, prête à
  // se reproduire sur un fichier voisin. **Une règle qui ne vaut que pour un
  // fichier ne protège que ce fichier.**
  //
  // Même traitement, donc : le cache répond tout de suite, le réseau vérifie
  // derrière, et si la version a changé on le DIT — la page propose de
  // recharger, elle ne se recharge pas toute seule.
  if (url.origin === self.location.origin && url.pathname.endsWith('.js')
      && !url.pathname.endsWith('sw.js')) {
    evt.respondWith((async () => {
      const cache  = await caches.open(CACHE);
      const cached = await cache.match(evt.request);
      const reseau = fetch(evt.request).then(async reponse => {
        if (reponse && reponse.ok) {
          await cache.put(evt.request, reponse.clone());
          if (cached && await _aChange(cached, reponse)) await _prevenirLesPages();
        }
        return reponse;
      }).catch(() => null);
      if (cached) { evt.waitUntil(reseau); return cached; }
      return (await reseau) || Response.error();
    })());
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
