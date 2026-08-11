// ══════════════════════════════════════════════════════════════════════════
//  RECETTE — LE CENTRE UNIQUE DE NOTIFICATIONS (P0-30, issue #66)
//
//  Charge les VRAIES fonctions de dist/index.html avec un serveur en carton
//  qui répond comme les six RPC de ChatGPT.
//
//  Ce qu'elle garde, et qui a coûté la reprise :
//   · « Effacer tout » SUPPRIMAIT les notifications. Le jour où une famille
//     dit « on ne m'a jamais prévenu », c'est cette ligne-là qu'on relit ;
//   · tout ce qui s'affichait passait « lu » d'office — donc la prise de
//     connaissance d'une convocation ne voulait plus rien dire ;
//   · l'abonnement au Web Push écrivait dans une table en refus total :
//     l'appareil se croyait enregistré, et personne n'était prévenu.
//
//  `--preuve` fait refuser le serveur et vérifie que l'écran dit « je n'ai
//  pas pu regarder » au lieu de « vous n'avez rien reçu ».
// ══════════════════════════════════════════════════════════════════════════
import { readFileSync } from 'node:fs';

const CHEMIN = process.env.SS_HTML || new URL('../dist/index.html', import.meta.url);
const html = readFileSync(CHEMIN, 'utf8');

// Les contrôles « plus aucune écriture de ce type » doivent regarder le CODE,
// pas les commentaires — sinon la note qui EXPLIQUE le retrait fait échouer
// le contrôle qui vérifie le retrait. La faute a été commise en écrivant
// cette recette : elle refusait le fichier à cause de ses propres
// explications. Un outil doit tester la condition, jamais une chaîne.
const code = html
  .split('\n')
  .map(l => l.replace(/^\s*\/\/.*$/, ''))   // ligne entièrement en commentaire
  .join('\n');
const PREUVE = process.argv.includes('--preuve');

const champs = {}, toasts = [], audits = [];
let modal = null, confirmCb = null;
const faux = () => ({ style:{}, value:'', innerHTML:'', dataset:{}, focus(){}, addEventListener(){},
  parentNode:{querySelector:()=>null, appendChild(){}}, scrollIntoView(){}, closest:()=>null });
globalThis.window = globalThis;
globalThis.document = {
  getElementById: (id) => (id in champs ? Object.assign(faux(), {value:champs[id]}) : null),
  querySelector:()=>null, querySelectorAll:()=>[], createElement:()=>faux(),
  addEventListener(){}, body:{style:{}}, styleSheets:[],
};
try{Object.defineProperty(globalThis,'navigator',{value:{onLine:true},configurable:true});}catch(_){}
globalThis.setTimeout = (f)=>{ if(typeof f==='function') try{f();}catch(e){} return 0; };
globalThis.clearTimeout = ()=>{};

globalThis.S = { user:{ id:'u_par', name:'Un parent', role:'parent' }, page:'notifications' };
globalThis.DB = { notifs:[], users:[], classes:[], students:[], settings:{} };
globalThis.esc = (s)=>String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
globalThis.toast = (m,t)=>toasts.push({m,t});
globalThis.logAudit = (a,d)=>audits.push({a,d});
globalThis.saveToCrypt = ()=>{};
globalThis.render = ()=>{};
globalThis.closeModal = ()=>{ modal=null; };
globalThis.openM = (t,b,f)=>{ modal={t,b,f}; };
globalThis.markFieldError = (id,msg)=>toasts.push({m:'CHAMP '+id,t:'field'});
globalThis.showC = (t,m,cb)=>{ confirmCb=cb; };
globalThis.$ = (id)=>document.getElementById(id);
globalThis._roleUI = (r)=>r;
globalThis.NAV = { parent:{nav:[{id:'notifications'}]}, direction:{nav:[{id:'notifications'}]} };
globalThis.go = ()=>{};
globalThis.pushSync = ()=>true;

// ── Le serveur en carton ─────────────────────────────────────────────────
const appels = [];
let base = [
  { id:'n1', category:'convocation', title:'Convocation', message:'Merci de passer à la Direction.',
    priority:'high', requires_ack:true, acknowledged_at:null, read:false, opened_at:null,
    created_at:'2026-08-10T09:00:00Z', created_by_name:'La Direction', push_status:'queued' },
  { id:'n2', category:'exit_confirmed', title:'Sortie confirmée', message:'Récupéré par sa tante.',
    priority:'normal', requires_ack:false, acknowledged_at:null, read:true, opened_at:'2026-08-10T08:00:00Z',
    created_at:'2026-08-10T08:00:00Z', created_by_name:'Gardien', push_status:'no_device' },
  { id:'n3', category:'homework', title:'Nouveau devoir', message:'Mathématiques pour vendredi.',
    priority:'normal', requires_ack:false, acknowledged_at:null, read:true, opened_at:null,
    created_at:'2026-08-09T15:00:00Z', created_by_name:'Mme Luyeye', push_status:'sent' },
];
globalThis._rpc = async (nom, p) => {
  appels.push({ nom, p });
  if (PREUVE) return { ok:false, code:'RPC_REFUSED' };
  if (nom === 'get_my_notification_center') {
    const cat = p.p_category;
    const items = cat ? base.filter(n => n.category === cat) : base.slice();
    return { ok:true, data:{ ok:true, items,
      unread_count: base.filter(n=>!n.read).length,
      ack_required_count: base.filter(n=>n.requires_ack && !n.acknowledged_at).length,
      active_device_count: 0 } };
  }
  if (nom === 'mark_my_notification_read') {
    const n = base.find(x=>x.id===p.p_notification_id); if(!n) return {ok:false,code:'NOTIFICATION_NOT_FOUND'};
    n.read = true; return { ok:true, data:{code:'NOTIFICATION_READ'} };
  }
  if (nom === 'mark_my_notification_opened') {
    const n = base.find(x=>x.id===p.p_notification_id); if(!n) return {ok:false,code:'NOTIFICATION_NOT_FOUND'};
    n.opened_at = '2026-08-10T10:00:00Z'; return { ok:true, data:{code:'NOTIFICATION_OPENED'} };
  }
  if (nom === 'acknowledge_my_notification') {
    const n = base.find(x=>x.id===p.p_notification_id);
    if(!n || !n.requires_ack) return {ok:false,code:'ACK_NOT_AVAILABLE'};
    n.acknowledged_at='2026-08-10T10:00:00Z'; n.read=true; return { ok:true, data:{code:'NOTIFICATION_ACKNOWLEDGED'} };
  }
  if (nom === 'archive_my_notification') {
    const i = base.findIndex(x=>x.id===p.p_notification_id);
    if(i<0) return {ok:false,code:'NOTIFICATION_NOT_FOUND'};
    base.splice(i,1); return { ok:true, data:{code:'NOTIFICATION_ARCHIVED'} };
  }
  if (nom === 'send_school_notification') {
    if (!p.title || !p.message) return { ok:false, code:'VALIDATION_ERROR' };
    if (p.target_role && S.user.role !== 'direction') return { ok:false, code:'DIRECTION1_REQUIRED_FOR_ROLE_BROADCAST' };
    return { ok:true, data:{ code:'NOTIFICATION_SENT', sent_count:12 } };
  }
  return { ok:false, code:'PGRST202' };
};

const vraiRpc = globalThis._rpc;
function extraire(a,b){ const i=html.indexOf(a); if(i<0) throw new Error(a); const j=html.indexOf(b,i); if(j<0) throw new Error(b); return html.slice(i,j); }
const bloc = extraire('window._notifTexte = (n) =>', '// `clearAllNotifs` est retirée');
const diff = extraire('window.sendBroadcast = async () => {', '\n// ═══════════════════════════════════════════\n//  DIRECTION — INSCRIPTIONS');
globalThis.R = {};
new Function('R', bloc + '\n' + diff)(globalThis.R);

const Rz=[]; const ok=(q,v,d)=>Rz.push({q,v:!!v,d});

// ═══ 1 · LE CENTRE VIENT DU SERVEUR ══════════════════════════════════════
await chargerCentreNotifs('');
ok('le centre est lu par get_my_notification_center',
   appels.some(a=>a.nom==='get_my_notification_center'), appels.map(a=>a.nom).join(','));
ok('les compteurs viennent du serveur, pas d’un calcul local',
   _centreEtat.unread===1 && _centreEtat.ack===1, `${_centreEtat.unread}/${_centreEtat.ack}`);

const vue = R.notifications();
ok('l’écran affiche les trois notifications', /Convocation/.test(vue)&&/Nouveau devoir/.test(vue), '');
ok('il compte les non lues', /1 non lue/.test(vue), '');
ok('et celles à confirmer', /1 à confirmer/.test(vue), '');

// ═══ 2 · ARCHIVER, JAMAIS SUPPRIMER ══════════════════════════════════════
ok('« Effacer tout » a disparu de l’écran', !/Effacer/.test(vue), '');
ok('« Archiver » l’a remplacé', /Archiver/.test(vue), '');
ok('et l’écran dit que rien n’est effacé', /n’efface rien/.test(vue), '');
ok('clearAllNotifs n’existe plus dans le fichier',
   !/window\.clearAllNotifs\s*=/.test(code), '');
ok('plus aucune suppression de notification n’est envoyée',
   !/pushSync\('notifs','delete'/.test(code), '');

// ═══ 3 · LA PRISE DE CONNAISSANCE ════════════════════════════════════════
ok('une notification qui l’exige porte « À CONFIRMER »', /À CONFIRMER/.test(vue), '');
ok('et son bouton « J’ai pris connaissance »', /pris connaissance/.test(vue), '');
ok('les autres ne l’ont PAS', (vue.match(/pris connaissance/g)||[]).length === 1, '');
const avantAck = appels.length;
await accuserNotif('n1');
ok('accuser appelle acknowledge_my_notification',
   appels.some(a=>a.nom==='acknowledge_my_notification'), '');
ok('après l’accusé, plus rien à confirmer', _centreEtat.ack===0, _centreEtat.ack);
await accuserNotif('n3');
ok('une notification sans accusé refuse, avec sa raison',
   toasts.some(t=>/ne demande pas de prise de connaissance/.test(t.m)), '');

// ═══ 4 · RIEN N'EST MARQUÉ LU D'OFFICE ═══════════════════════════════════
base = [{ id:'n9', category:'information', title:'Info', message:'Test', priority:'normal',
  requires_ack:false, acknowledged_at:null, read:false, opened_at:null,
  created_at:'2026-08-10T09:00:00Z', created_by_name:'Direction', push_status:'no_device' }];
_centreEtat.charge=false;
await chargerCentreNotifs('');
R.notifications();
ok('afficher une notification ne la marque PAS lue', !base[0].read, base[0].read);
await marquerNotifLue('n9');
ok('elle ne passe lue que sur un geste explicite', base[0].read, '');

// ═══ 5 · L'ÉTAT D'ENVOI EXTÉRIEUR, DIT HONNÊTEMENT ═══════════════════════
base = [
  { id:'a', category:'information', title:'A', message:'a', read:false, requires_ack:false,
    created_at:'2026-08-10T09:00:00Z', push_status:'no_device', priority:'normal' },
  { id:'b', category:'information', title:'B', message:'b', read:false, requires_ack:false,
    created_at:'2026-08-10T09:00:00Z', push_status:'queued', priority:'normal' },
];
_centreEtat.charge=false; await chargerCentreNotifs('');
window._notifOuverte='a'; const vA=R.notifications();
ok('« aucun appareil enregistré » se lit tel quel', /Aucun appareil enregistré/.test(vA), '');
window._notifOuverte='b'; const vB=R.notifications();
ok('« en file d’envoi » aussi', /En file d’envoi/.test(vB), '');
ok('jamais « envoyée » sur une notification en file',
   !/Envoyée sur le téléphone/.test(vB), '');
window._notifOuverte=null;

// ═══ 6 · UNE LECTURE QUI ÉCHOUE N'EST PAS UN CENTRE VIDE ════════════════
const vrai_rpc = globalThis._rpc;
globalThis._rpc = async () => ({ ok:false, code:'PGRST202' });
_centreEtat.charge=false;
await chargerCentreNotifs('');
const vErr = R.notifications();
ok('un échec de lecture est annoncé comme tel', /n’a pas pu être lu/.test(vErr), '');
ok('et il est distingué de « vous n’avez rien reçu »',
   /je n’ai pas pu regarder/.test(vErr), '');
ok('avec le motif du serveur', /n’est pas servi par ce serveur/.test(vErr), '');
globalThis._rpc = vrai_rpc;

// ═══ 7 · L'ANNONCE PASSE PAR LA PORTE UNIQUE ═════════════════════════════
S.user = { id:'d1', name:'Direction', role:'direction' };
champs.bc_target='parents'; champs.bc_msg='Réunion des parents vendredi.';
await sendBroadcast();
ok('l’annonce appelle send_school_notification',
   appels.some(a=>a.nom==='send_school_notification'), '');
const env = appels.filter(a=>a.nom==='send_school_notification').pop();
ok('elle DÉSIGNE le rôle, elle n’envoie pas une liste calculée',
   env.p.target_role==='parent' && !env.p.recipient_user_ids, JSON.stringify(env.p).slice(0,80));
ok('et elle porte un titre, exigé par le serveur', !!env.p.title, '');
ok('le nombre annoncé est celui du SERVEUR',
   toasts.some(t=>/12 destinataire/.test(t.m)), '');
champs.bc_msg='   ';
const avantVide = appels.filter(a=>a.nom==='send_school_notification').length;
await sendBroadcast();
ok('une annonce vide n’atteint pas le serveur',
   appels.filter(a=>a.nom==='send_school_notification').length===avantVide, '');
S.user = { id:'e1', name:'Enseignant', role:'enseignant' };
champs.bc_msg='essai';
await sendBroadcast();
ok('un enseignant ne diffuse pas une annonce',
   toasts.some(t=>/Accès non autorisé/.test(t.m)), '');

// ═══ 8 · PLUS AUCUN CHEMIN MORT VERS LE PUSH ═════════════════════════════
ok('plus aucune écriture directe dans push_subscriptions',
   !/pushSync\('push_subscriptions'/.test(code), '');

// ═══ 9 · L'ABONNEMENT WEB PUSH — il appelle le vrai contrat ══════════════
// Il ne s'agit plus de vérifier qu'il est ABSENT — il est là, et c'est bien.
// La condition qui compte : passe-t-il par la RPC, et dit-il la vérité quand
// le serveur refuse ? Un outil teste une condition, pas une chaîne.
S.user = { id:'u_par', name:'Un parent', role:'parent' };
let abonnementRetire = false;
const faireNavigateur = (permission, cleVapid) => {
  globalThis.Notification = { permission, requestPermission: async () => permission };
  globalThis.PushManager = function(){};
  const sub = { endpoint:'https://push.example/abc123', toJSON:()=>({endpoint:'https://push.example/abc123',
      keys:{p256dh:'BPabcdef0123456789', auth:'authsecret012345'}}),
    unsubscribe: async () => { abonnementRetire = true; return true; } };
  try{Object.defineProperty(globalThis,'navigator',{value:{ userAgent:'node-test', onLine:true,
    serviceWorker:{ ready: Promise.resolve({ pushManager:{
      getSubscription: async () => null, subscribe: async () => sub } }) } },configurable:true});}catch(_){}
  globalThis.atob = (s) => Buffer.from(s, 'base64').toString('binary');
  DB.settings.vapid_public_key = cleVapid;
};

// a · sans clé, on ne demande rien et on le dit
faireNavigateur('default', null);
ok('sans clé d’envoi, l’état est « sans_cle »', _pushEtat()==='sans_cle', _pushEtat());
const avantSansCle = appels.length;
await activerNotificationsExterieures();
ok('et aucun appel n’est fait au serveur', appels.length===avantSansCle, '');
ok('l’écran explique que c’est un réglage de l’école',
   modal && /clé d’envoi/.test(modal.b), '');

// b · avec clé, l'abonnement part vers la VRAIE fonction
faireNavigateur('granted', 'BEl62iUYgUivxIkv69yViEuiBIa1HI0kQ0BCZ0lHZ0lHZ0lHZ0lHZ0lHZ0lHZ0lHZ0lHZ0lHZ0lHZ0lHZ0k');
await activerNotificationsExterieures();
const reg = appels.filter(a=>a.nom==='register_push_device').pop();
ok('l’abonnement appelle register_push_device', !!reg, '');
ok('avec provider = webpush, pas fcm', reg && reg.p.p_provider==='webpush', reg && reg.p.p_provider);
ok('le triplet endpoint/p256dh/auth voyage dans le jeton',
   reg && /endpoint/.test(reg.p.p_token) && /p256dh/.test(reg.p.p_token) && /auth/.test(reg.p.p_token), '');
ok('et RIEN d’autre — ni élève, ni nom, ni numéro',
   reg && !/student|eleve|phone|\+243/.test(reg.p.p_token), reg && reg.p.p_token.slice(0,60));

// c · le serveur refuse : on le DIT, et on ne garde pas un abonnement mort
globalThis._rpc = async (nom, p) => { appels.push({nom,p});
  if (nom === 'register_push_device') return { ok:false, code:'UNSUPPORTED_PROVIDER' };
  return vraiRpc(nom, p); };
abonnementRetire = false;
faireNavigateur('granted', 'BEl62iUYgUivxIkv69yViEuiBIa1HI0kQ0BCZ0lHZ0lHZ0lHZ0lHZ0lHZ0lHZ0lHZ0lHZ0lHZ0lHZ0lHZ0k');
await activerNotificationsExterieures();
ok('un refus du serveur est annoncé dans les mots de l’école',
   modal && /n’accepte pas encore/.test(modal.b), modal?modal.b.slice(0,60):'aucune modale');
ok('le code serveur est donné pour le dépannage',
   modal && /UNSUPPORTED_PROVIDER/.test(modal.b), '');
ok('et l’abonnement mort est retiré du navigateur', abonnementRetire, '');
ok('l’état devient « serveur_non », pas « actif »', _pushEtat()==='serveur_non', _pushEtat());
_centreEtat.appareils = 3;
ok('même avec des appareils comptés, on n’annonce pas « actif »',
   _pushEtat()==='serveur_non', _pushEtat());
_centreEtat.appareils = 0; window._pushDernierRefus = null;
globalThis._rpc = vraiRpc;

// ── Verdict ──────────────────────────────────────────────────────────────
console.log('\n═══ RECETTE — LE CENTRE DE NOTIFICATIONS ═══\n');
for (const r of Rz) console.log(`  ${r.v?'✓':'✗'} ${r.q}${r.v?'':'   → '+r.d}`);
const ko = Rz.filter(r=>!r.v);
if (PREUVE) {
  const dit = Rz.find(r=>/échec de lecture est annoncé/.test(r.q));
  if (dit && dit.v) { console.log('\n✔ PREUVE TENUE — serveur muet, l’écran dit « je n’ai pas pu regarder ».\n'); process.exit(0); }
  console.log('\n✗ PREUVE MANQUÉE — le centre a présenté un échec comme une absence.\n'); process.exit(1);
}
console.log(`\n${ko.length?'✗ '+ko.length+' sur '+Rz.length+' en échec':'✓ les '+Rz.length+' points passent'}\n`);
process.exit(ko.length?1:0);
