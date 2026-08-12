/*
 * SchoolSafe — bootstrap de connexion après chargement différé de Supabase.
 *
 * Le SDK Supabase est chargé avec `defer` dans index.html pour ne pas bloquer
 * l'écran d'accueil. Les scripts inline sont toutefois évalués AVANT les
 * scripts `defer` : au moment où index.html essayait de créer `_authClient`,
 * `window.supabase` n'existait donc pas encore et `_authClient` restait null.
 * Le bouton Connexion tombait alors sur le faux message « serveur indisponible »
 * sans appeler school-login.
 *
 * Ce bootstrap s'exécute après le SDK différé, crée le client manquant, puis
 * recharge à l'identique le frontend Messages conservé dans
 * messages-frontend-v2-core.js. Aucun appel réseau n'est ajouté au démarrage.
 */
(function installSchoolSafeAuthBootstrap() {
  'use strict';
  if (window.__SS_AUTH_BOOTSTRAP__) return;
  window.__SS_AUTH_BOOTSTRAP__ = { version:'2026-08-12.2', initialized:false };

  const bindClient = () => {
    if (window._authClient) {
      window.__SS_AUTH_BOOTSTRAP__.initialized = true;
      return window._authClient;
    }
    if (typeof OPS_SUPA_URL === 'undefined' || typeof OPS_SUPA_KEY === 'undefined') return null;
    if (!OPS_SUPA_URL || !OPS_SUPA_KEY || !window.supabase?.createClient) return null;

    const client = window.supabase.createClient(OPS_SUPA_URL, OPS_SUPA_KEY, {
      auth: { persistSession:true, autoRefreshToken:true, detectSessionInUrl:true }
    });
    window._authClient = client;
    window.__SS_AUTH_BOOTSTRAP__.initialized = true;

    // Même contrat que l'initialisation historique de index.html : on garde
    // le JWT courant pour REST/RPC et les sessions invitation/récupération.
    client.auth.onAuthStateChange((_event, session) => {
      if (session?.access_token && typeof window._updateSupabase === 'function') {
        window._updateSupabase(OPS_SUPA_URL, OPS_SUPA_KEY, session.access_token);
      }
      if (session && (_event === 'PASSWORD_RECOVERY' || window._authCallbackType === 'invite' || window._authCallbackType === 'recovery')) {
        window._pendingAuthSession = session;
      }
    });
    return client;
  };

  // Chemin normal : le SDK `defer` placé dans <head> s'est exécuté avant ce
  // script `defer` placé en fin de document. Zéro requête supplémentaire.
  window._ensureAuthClient = async () => {
    const ready = bindClient();
    if (ready) return ready;
    if (navigator.onLine === false) return null;

    // Secours uniquement AU CLIC : si le CDN a réellement échoué au premier
    // chargement, on retente le SDK sans ralentir l'ouverture de SchoolSafe.
    if (!window.__SS_AUTH_BOOTSTRAP__.sdkRetry) {
      window.__SS_AUTH_BOOTSTRAP__.sdkRetry = new Promise(resolve => {
        const s = document.createElement('script');
        s.src = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.111.0/dist/umd/supabase.js';
        s.crossOrigin = 'anonymous';
        const timer = setTimeout(() => { cleanup(); resolve(null); }, 6000);
        const cleanup = () => { clearTimeout(timer); s.onload = s.onerror = null; };
        s.onload = () => { cleanup(); resolve(bindClient()); };
        s.onerror = () => { cleanup(); resolve(null); };
        document.head.appendChild(s);
      });
    }
    return window.__SS_AUTH_BOOTSTRAP__.sdkRetry;
  };

  bindClient();

  // Le bouton attend l'initialisation locale du client AVANT d'exécuter le
  // tryLogin existant. Aucun changement aux règles d'authentification.
  if (typeof window.tryLogin === 'function' && !window.tryLogin.__ssAuthWrapped) {
    const originalTryLogin = window.tryLogin;
    const wrapped = async function(...args) {
      await window._ensureAuthClient();
      return originalTryLogin.apply(this, args);
    };
    wrapped.__ssAuthWrapped = true;
    window.tryLogin = wrapped;
  }
})();

// Le travail Messages de Claude/SchoolSafe est conservé octet pour octet dans
// ce fichier séparé et chargé ensuite. Ainsi la correction Auth reste isolée.
(function loadPreservedMessagesFrontend() {
  'use strict';
  if (window.__SS_MESSAGES_CORE_LOADING__) return;
  window.__SS_MESSAGES_CORE_LOADING__ = true;
  const s = document.createElement('script');
  s.src = 'messages-frontend-v2-core.js?v=20260812-core1';
  s.async = true;
  s.onload = () => { window.__SS_MESSAGES_CORE_LOADED__ = true; };
  s.onerror = () => { console.warn('[SchoolSafe] frontend Messages V2 non chargé'); };
  document.head.appendChild(s);
})();
