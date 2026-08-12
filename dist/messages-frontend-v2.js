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

  window._ensureAuthClient = async () => {
    const ready = bindClient();
    if (ready) return ready;
    if (navigator.onLine === false) return null;

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

// Le travail Messages de Claude/SchoolSafe est conservé dans son fichier séparé.
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

// Politique documents officiels : chargée ASYNCHRONEMENT, sans bloquer l'écran
// d'accueil ni la saisie de connexion.
(function loadOfficialDocumentsPolicy() {
  'use strict';
  if (window.__SS_DOCUMENTS_POLICY_LOADING__) return;
  window.__SS_DOCUMENTS_POLICY_LOADING__ = true;
  const load = () => {
    const s = document.createElement('script');
    s.src = 'documents-officiels-policy.js?v=20260812-1';
    s.async = true;
    s.onload = () => { window.__SS_DOCUMENTS_POLICY_LOADED__ = true; };
    s.onerror = () => { console.warn('[SchoolSafe] politique documents PDF non chargée'); };
    document.head.appendChild(s);
  };
  if ('requestIdleCallback' in window) requestIdleCallback(load, { timeout:1500 });
  else setTimeout(load, 0);
})();

// Fiche d'accès WhatsApp : ne jamais construire la fiche à partir d'une copie
// locale qui n'a pas encore reçu `login_name`. La colonne existe côté serveur
// et ROLE_LOAD la demande, mais juste après une création de compte la fiche
// locale peut encore être antérieure à la génération/synchronisation de l'alias.
// On ne fait AUCUN appel au démarrage : la relecture ciblée n'a lieu qu'au
// moment d'ouvrir la fiche, et seulement si `login_name` manque localement.
(function hardenWhatsAppCredentialsCard() {
  'use strict';
  if (window.__SS_WHATSAPP_CREDENTIALS_V2__) return;
  window.__SS_WHATSAPP_CREDENTIALS_V2__ = true;

  if (typeof window.ouvrirCarteAcces === 'function' && !window.ouvrirCarteAcces.__ssLoginNameRefresh) {
    const originalOpenCard = window.ouvrirCarteAcces;
    const wrappedOpenCard = async function(uid, ...args) {
      try {
        const store = (typeof DB !== 'undefined' && DB) ? DB : window.DB;
        const u = (store?.users || []).find(x => x.id === uid);
        if (u && !u.login_name) {
          const getter = typeof _get === 'function' ? _get : window._get;
          if (typeof getter === 'function') {
            const q = 'select=id,initials,login_name,phone&id=eq.' + encodeURIComponent(uid) + '&limit=1';
            const rows = await getter('users', q);
            if (Array.isArray(rows) && rows[0]) Object.assign(u, rows[0]);
          }
        }
      } catch (e) {
        console.warn('[SchoolSafe] relecture login_name WhatsApp', e && e.message);
      }
      return originalOpenCard.apply(this, [uid, ...args]);
    };
    wrappedOpenCard.__ssLoginNameRefresh = true;
    window.ouvrirCarteAcces = wrappedOpenCard;
  }

  // Pour la famille, ce code est bien le mot de passe temporaire Auth. Le
  // message WhatsApp le nomme donc explicitement, sans changer sa valeur.
  if (typeof window._messageAccesWhatsApp === 'function' && !window._messageAccesWhatsApp.__ssPasswordLabel) {
    const originalMessage = window._messageAccesWhatsApp;
    const wrappedMessage = function(ids, code, expiresAt) {
      const message = String(originalMessage.call(this, ids, code, expiresAt));
      return message.replace('Code temporaire : ' + code, 'Mot de passe temporaire : ' + code);
    };
    wrappedMessage.__ssPasswordLabel = true;
    window._messageAccesWhatsApp = wrappedMessage;
  }
})();
