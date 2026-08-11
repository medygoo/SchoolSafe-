// ══════════════════════════════════════════════════════════════════════════
//  RECETTE — SCANNER PHYSIQUE ≠ ACCÈS QR DE LA CAISSE (issue #94)
//
//  Charge les VRAIES fonctions de dist/index.html dans Node avec un serveur en
//  carton qui répond comme les RPC de ChatGPT, et confronte le parcours profil
//  par profil.
//
//  Elle garde DEUX choses, et la seconde est la vraie.
//
//  1. La liste des rôles. Elle était écrite trois fois et les trois copies
//     divergeaient : l'écran admettait la Caisse, `processScanEntry` admettait
//     « tout sauf parent », `_enregistrerPassage` admettait la Caisse. Le
//     serveur, lui, sépare le droit de scanner de l'accès QR financier.
//
//  2. CE QU'UN REFUS DEVIENT. `_rpcData` rendait `null` pour tout échec — refus
//     du serveur comme réseau muet. `_enregistrerPassage` lisait donc un REFUS
//     comme un SILENCE, retombait sur la file hors ligne, et l'écran annonçait
//     « entrée enregistrée » pour un scan que le serveur venait de refuser —
//     avec une présence à la clé. Le DRAFT de ChatGPT lève un 42501 : sans
//     cette correction, la séparation aurait produit exactement ce mensonge.
//
//  Et elle garde le contraire avec la même force : un serveur MUET doit
//  toujours passer par la file. Un gardien devant un portail de Kinshasa ne
//  peut pas attendre le réseau.
//
//  Éprouvée dans l'autre sens : `--preuve` réinjecte les DEUX défauts d'origine
//  dans la source réelle — la Caisse dans la liste, et le refus qui retombe
//  dans la file — et vérifie que la recette les revoit.
// ══════════════════════════════════════════════════════════════════════════
import { readFileSync } from 'node:fs';

const CHEMIN = process.env.SS_HTML || new URL('../dist/index.html', import.meta.url);
let html = readFileSync(CHEMIN, 'utf8');
const PREUVE = process.argv.includes('--preuve');

// ── La preuve : on remet les deux défauts d'origine dans le VRAI code ─────
if (PREUVE) {
  const avant = html;
  html = html.replace(
    `window.ROLES_SCAN_PHYSIQUE = ['gardien','enseignant','direction','direction2'];`,
    `window.ROLES_SCAN_PHYSIQUE = ['gardien','enseignant','direction','direction2','direction3'];`);
  html = html.replace(
    `    if (r && r.refus) return { ok:false, raison:'forbidden', code:r.code };`, '');
  if (html === avant) { console.log('\n✗ PREUVE IMPOSSIBLE — les deux points à réinjecter sont introuvables.\n'); process.exit(1); }
}

// ── Navigateur en carton ─────────────────────────────────────────────────
const faux = () => ({ style:{}, value:'', innerHTML:'', dataset:{}, focus(){}, addEventListener(){},
  parentNode:{querySelector:()=>null, appendChild(){}}, scrollIntoView(){}, closest:()=>null });
globalThis.window = globalThis;
globalThis.document = { getElementById:()=>null, querySelector:()=>null, querySelectorAll:()=>[],
  createElement:()=>faux(), addEventListener(){}, body:{style:{}}, styleSheets:[] };
try{Object.defineProperty(globalThis,'navigator',{value:{onLine:true},configurable:true});}catch(_){}
globalThis.localStorage = { getItem:()=>null, setItem(){}, removeItem(){} };
// `_rpcData` trace chaque échec par `console.warn`. C'est utile au dépannage
// dans un navigateur, et c'est du bruit ici : la recette provoque exprès des
// refus et des silences. Seul son verdict doit parler.
console.warn = () => {};
globalThis.setTimeout = (f)=>{ if(typeof f==='function') try{f();}catch(e){} return 0; };
globalThis.clearTimeout = ()=>{};

// ── Dépendances de l'application ─────────────────────────────────────────
const toasts = [], audits = [], file = [], ecrans = [];
globalThis.S = { user:null, lockdown:false, page:'scanner' };
globalThis.DB = { students:[], classes:[], users:[], aps:[], scan_log:[], notifs:[],
  attendance:[], approbations:[],
  settings:{ year:'2026-2027', qr_secret:null, horaires:{ primaire:{ontime:1440, late:1440} } } };
globalThis.DB_ONLINE = true;
globalThis.esc = (s)=>String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
globalThis.toast = (m,t)=>toasts.push({m,t});
globalThis.logAudit = (a,d)=>audits.push({a,d});
globalThis.pushSync = (t,op,row)=>{ file.push({t,op,row}); return true; };
globalThis.saveToCrypt = ()=>{};
globalThis.render = ()=>{};
globalThis.today = ()=>'2026-08-11';
globalThis.nowTime = ()=>'07:20';          // 440 min → « à l'heure »
globalThis._uid = (p='')=>p+Math.random().toString(36).slice(2,9);
globalThis.$ = ()=>null;
globalThis.gc = (id)=>DB.classes.find(c=>c.id===id);
globalThis.gu = (id)=>DB.users.find(u=>u.id===id);
globalThis.pushNotif = async ()=>{};
globalThis._hmacSign = async ()=>'sig';
globalThis._resoudreCarteQR = async ()=>({ ok:false, titre:'—' });
globalThis.startScan = ()=>{}; globalThis.stopScan = ()=>{};
globalThis.showScanResult = (couleur,ic,titre,nom,detail)=>ecrans.push({couleur,titre,nom,detail});

// ── Le serveur en carton ─────────────────────────────────────────────────
// Il répond comme PostgREST : `error.code` porte le SQLSTATE quand PostgreSQL
// a parlé, et rien du tout quand le réseau s'est tu. C'est cette différence-là
// que le navigateur doit savoir lire.
let MODE = 'ok';
const appels = [];
globalThis._authClient = {
  rpc: async (nom, p) => {
    appels.push({ nom, p });
    if (MODE === 'refus')   return { data:null, error:{ code:'42501', message:'Accès refusé — scanner physique' } };
    if (MODE === 'muet')    return { data:null, error:{ message:'Failed to fetch' } };   // aucun SQLSTATE
    if (MODE === 'exception') throw new Error('NetworkError');
    if (MODE === 'duplicate') return { data:{ recorded:false, reason:'duplicate' }, error:null };
    return { data:{ recorded:true, id:'srv_'+p.p_sid }, error:null };
  }
};
globalThis._rpc = async (nom, p) => { appels.push({ nom, p }); return { ok:true, data:{ access_status:'ok', allowed:true } }; };

// ── Le code réel ─────────────────────────────────────────────────────────
function extraire(debut, fin) {
  const i = html.indexOf(debut); if (i < 0) throw new Error('introuvable : ' + debut);
  const j = html.indexOf(fin, i); if (j < 0) throw new Error('fin introuvable : ' + fin);
  return html.slice(i, j);
}
globalThis.R = {};
// les gardes de rôle et la liste unique
new Function(extraire('window.ROLES_SCAN_PHYSIQUE = [', '// ── DASHBOARDS ──'))();
globalThis.go = ()=>{};
// _SQLSTATE et _rpcData
new Function(extraire('window._SQLSTATE = ', 'window._edgeFn'))();
// le niveau d'arrivée, réel. Il lit l'heure de la machine : les horaires du
// jeu d'essai sont donc poussés à la dernière minute possible pour que tout
// scan tombe « à l'heure », quelle que soit l'heure à laquelle on le lance.
new Function(extraire('function getArrivalStatus(cycle)', 'function showScanResult') +
             '\nglobalThis.getArrivalStatus = getArrivalStatus;')();
// l'écran d'entrée, la file, le passage, et processScanEntry
new Function('R', extraire('window._estBloque = ', 'window._SORTIE_REFUS'))(globalThis.R);
// l'écran de contrôle des frais
globalThis._cfEtat = { sid:null, dossier:null, chargement:false, msg:'' };
new Function('R', extraire('R.controle_frais = ', 'R.frais_parent'))(globalThis.R);

// ── Jeu d'essai ──────────────────────────────────────────────────────────
DB.classes.push({ id:'c1', name:'3ᵉ Primaire A', cycle:'primaire' });
DB.students.push({ id:'s1', name:'Enfant Un', mat:'LS-0001', cid:'c1', pid:'p1' });

const Rz = []; const ok = (q,v,d='') => Rz.push({ q, v:!!v, d });
const RAZ = () => { DB.scan_log.length=0; DB.attendance.length=0; file.length=0;
                    appels.length=0; ecrans.length=0; toasts.length=0;
                    window._scanBusy=false; window._badScans={}; window._cacheAcces={}; };

const PROFILS = [['gardien',true],['enseignant',true],['direction',true],
                 ['direction2',true],['direction3',false],['parent',false]];

// ═══ 1 · UNE SEULE LISTE, ET C'EST CELLE DU SERVEUR ══════════════════════
ok('la liste des scanneurs physiques existe et est unique',
   Array.isArray(window.ROLES_SCAN_PHYSIQUE));
ok('la Caisse n’est PAS un scanneur physique — can_physical_scan() de ChatGPT',
   !window.ROLES_SCAN_PHYSIQUE.includes('direction3'),
   window.ROLES_SCAN_PHYSIQUE.join(','));
ok('le parent non plus', !window.ROLES_SCAN_PHYSIQUE.includes('parent'));
for (const r of ['gardien','enseignant','direction','direction2'])
  ok(`${r} garde le droit de scanner`, window.ROLES_SCAN_PHYSIQUE.includes(r));

// ═══ 2 · L'ÉCRAN D'ENTRÉE, PROFIL PAR PROFIL ═════════════════════════════
for (const [role, permis] of PROFILS) {
  S.user = { id:'u_'+role, name:role, role };
  const vu = R.scanner();
  const passe = !/Accès refusé/.test(vu);
  ok(`${role} ${permis?'ouvre':'n’ouvre PAS'} l’écran Scanner Entrée`, passe === permis);
}

// ═══ 3 · L'ENREGISTREMENT, PROFIL PAR PROFIL ═════════════════════════════
// Cacher un écran ne protège rien : c'est ici que ça compte.
for (const [role, permis] of PROFILS) {
  RAZ(); MODE = 'ok';
  S.user = { id:'u_'+role, name:role, role };
  await processScanEntry('LS-0001');
  const aAppele = appels.some(a => a.nom === 'record_entry_scan');
  ok(`${role} ${permis?'enregistre':'n’enregistre PAS'} une entrée`, aAppele === permis);
  if (!permis) {
    ok(`${role} : rien dans le registre local`, DB.scan_log.length === 0, String(DB.scan_log.length));
    ok(`${role} : rien dans la file d’attente`, file.length === 0, String(file.length));
    ok(`${role} : aucune présence`, DB.attendance.length === 0, String(DB.attendance.length));
  }
}

// ═══ 4 · UN REFUS DU SERVEUR N'EST PAS UNE ENTRÉE ════════════════════════
// Le cœur de la reprise. Le serveur lève 42501 — comme le DRAFT de ChatGPT.
RAZ(); MODE = 'refus';
S.user = { id:'g1', name:'Gardien', role:'gardien' };
await processScanEntry('LS-0001');
ok('sur un refus 42501, le serveur a bien été appelé',
   appels.some(a => a.nom === 'record_entry_scan'));
ok('un refus n’écrit RIEN dans le registre local',
   DB.scan_log.length === 0, JSON.stringify(DB.scan_log.map(l=>l.status)));
ok('un refus ne part PAS dans la file d’attente',
   file.length === 0, JSON.stringify(file.map(f=>f.t)));
ok('un refus ne crée AUCUNE présence',
   DB.attendance.length === 0, String(DB.attendance.length));
ok('et l’écran dit le refus, il n’annonce pas une entrée',
   ecrans.length === 1 && /refus/i.test(ecrans[0].titre),
   JSON.stringify(ecrans.map(e=>e.titre)));
ok('le refus porte son code serveur, pour le dépannage',
   ecrans.length === 1 && /42501/.test(ecrans[0].detail || ''),
   ecrans[0] ? String(ecrans[0].detail) : '—');

// ═══ 5 · UN SERVEUR MUET, LUI, PASSE TOUJOURS PAR LA FILE ════════════════
// L'inverse du précédent, et il compte autant : un gardien hors ligne doit
// pouvoir travailler. Confondre les deux dans un sens fabrique un mensonge ;
// les confondre dans l'autre bloque un portail.
RAZ(); MODE = 'muet';
await processScanEntry('LS-0001');
ok('un serveur MUET n’est pas un refus — le passage est gardé',
   DB.scan_log.length === 1, String(DB.scan_log.length));
ok('et il part dans la file d’attente',
   file.some(f => f.t === 'scan_log'), JSON.stringify(file.map(f=>f.t)));
ok('la présence est inscrite hors ligne',
   DB.attendance.length === 1, String(DB.attendance.length));
ok('l’écran n’annonce pas un refus', !ecrans.some(e => /refus/i.test(e.titre)));

RAZ(); MODE = 'exception';
await processScanEntry('LS-0001');
ok('une panne de transport se comporte comme un silence, pas comme un refus',
   DB.scan_log.length === 1 && file.length > 0);

// ═══ 6 · LE SERVEUR QUI ACCEPTE, ET CELUI QUI DIT NON MÉTIER ═════════════
RAZ(); MODE = 'ok';
await processScanEntry('LS-0001');
ok('un passage accepté est inscrit une seule fois',
   DB.scan_log.length === 1, String(DB.scan_log.length));
ok('et il ne repart PAS dans la file — le serveur l’a déjà enregistré',
   !file.some(f => f.t === 'scan_log'), JSON.stringify(file.map(f=>f.t)));
ok('une seule présence pour une seule arrivée',
   DB.attendance.length === 1, String(DB.attendance.length));

RAZ(); MODE = 'duplicate';
await processScanEntry('LS-0001');
ok('un refus métier reste lisible dans les mots de l’école',
   ecrans.length === 1 && /déjà enregistré/i.test(ecrans[0].detail || ''),
   ecrans[0] ? String(ecrans[0].detail) : '—');
ok('et lui non plus ne crée pas de présence', DB.attendance.length === 0);

// ═══ 7 · PAS DE BOUTON MORT SUR L'ÉCRAN DE LA CAISSE ═════════════════════
// Un bouton qui répond « Accès refusé » est un défaut, pas une protection.
S.user = { id:'d3', name:'Caisse', role:'direction3' };
const vueCaisse = R.controle_frais();
ok('la Caisse garde son contrôle des frais',
   !/Accès refusé/.test(vueCaisse) && /Contrôle des frais/.test(vueCaisse));
ok('mais son écran ne porte plus de bouton vers le scanner',
   !/go\('scanner'\)/.test(vueCaisse));
ok('et la consigne ne lui promet plus de scanner',
   !/Scannez la carte/.test(vueCaisse) && /Saisissez le matricule/.test(vueCaisse));
S.user = { id:'d1', name:'Direction', role:'direction' };
const vueDir = R.controle_frais();
ok('la Direction, elle, garde le bouton — elle a le droit de scanner',
   /go\('scanner'\)/.test(vueDir));

// ── Verdict ──────────────────────────────────────────────────────────────
console.log('\n═══ RECETTE — SCANNER PHYSIQUE ≠ ACCÈS QR CAISSE ═══\n');
for (const r of Rz) console.log(`  ${r.v?'✓':'✗'} ${r.q}${r.v?'':'   → '+r.d}`);
const ko = Rz.filter(r => !r.v);

if (PREUVE) {
  // Les deux défauts sont réinjectés dans le vrai code : la recette DOIT les
  // revoir, et pas seulement en nombre — chacun des deux nommément.
  const laCaisse = Rz.find(r => /la Caisse n’est PAS un scanneur/.test(r.q));
  const leRefus  = Rz.find(r => /un refus ne part PAS dans la file/.test(r.q));
  const vusCaisse = laCaisse && !laCaisse.v;
  const vuRefus   = leRefus  && !leRefus.v;
  if (vusCaisse && vuRefus) {
    console.log('\n✔ PREUVE TENUE — la Caisse remise dans la liste et le refus retombé');
    console.log('  dans la file sont revus tous les deux.\n');
    process.exit(0);
  }
  console.log('\n✗ PREUVE MANQUÉE — ' +
    (!vusCaisse ? 'la Caisse est repassée sans être vue. ' : '') +
    (!vuRefus   ? 'un refus serveur est reparti dans la file sans être vu.' : '') + '\n');
  process.exit(1);
}

console.log(`\n${ko.length ? '✗ '+ko.length+' sur '+Rz.length+' en échec'
                           : '✓ les '+Rz.length+' points passent'}\n`);
process.exit(ko.length ? 1 : 0);
