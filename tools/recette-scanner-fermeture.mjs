// ══════════════════════════════════════════════════════════════════════════
//  RECETTE — LES POINTS DE FERMETURE DU SCANNER (audit ChatGPT, issue #102)
//
//  Quatre défauts nommés par son audit, et chacun se voit par une famille :
//
//   3. l'annulation d'une préparation annonçait « le parent est prévenu » sans
//      lire ce que le serveur dit de l'envoi — un parent qui vient pour rien ;
//   5. le cache d'accès gardait un REFUS cinq minutes : enfant refusé → la
//      famille régularise à la Caisse → elle revient → le gardien relisait
//      l'ancien refus. Vider le cache après l'encaissement ne suffit pas :
//      **le cache qui ment vit sur le téléphone du gardien, l'encaissement se
//      fait sur celui de la Caisse.** D'où le remède : on ne met plus un refus
//      en cache du tout ;
//   6. les écrans de consultation listaient les personnes autorisées avec le
//      seul `active !== false`, quand le portail applique actif ET approuvé ET
//      dans ses dates. Une accréditation expirée y passait pour autorisée ;
//   7. l'espace Parent promettait « ajoutez jusqu'à 3 tutelles » et offrait
//      « ➕ Ajouter », que le serveur refuse — le parent croyait avoir fait le
//      nécessaire.
//
//  Éprouvée dans l'autre sens : `--preuve` remet les quatre défauts d'origine
//  dans la source réelle et vérifie que la recette les revoit, nommément.
// ══════════════════════════════════════════════════════════════════════════
import { readFileSync } from 'node:fs';

const CHEMIN = process.env.SS_HTML || new URL('../dist/index.html', import.meta.url);
let html = readFileSync(CHEMIN, 'utf8');
const PREUVE = process.argv.includes('--preuve');

if (PREUVE) {
  const avant = html;
  // 5 · le refus revient dans le cache
  html = html.replace(
    "      if (d.allowed === true) window._cacheAcces[sid] = { r: d, at: Date.now() };\n      else delete window._cacheAcces[sid];",
    "      window._cacheAcces[sid] = { r: d, at: Date.now() };");
  // 6 · la vue parallèle reprend son propre filtre
  html = html.replace(
    "window._apsValides = (sid) => {\n  const auj = today();\n  return (DB.aps || []).filter(a => a.sid === sid\n    && a.active\n    && a.approval_status === 'approved'\n    && (!a.valid_until || a.valid_until >= auj));\n};",
    "window._apsValides = (sid) => (DB.aps || []).filter(a => a.sid === sid && a.active !== false);");
  // 3 · l'annulation réaffirme sans preuve
  html = html.replace(
    "  toast('Préparation annulée — ' + _libelleNotif(r.data && r.data.notification), 'success');",
    "  toast('Préparation annulée — le parent est prévenu', 'success');");
  // 7 · le bouton que le serveur refuse revient dans l'espace Parent
  html = html.replace(
    "${tuts.length<3?`<span class=\"pill\" style=\"background:#dbeafe;color:#1e40af;font-size:10px\">${3-tuts.length} place${3-tuts.length>1?'s':''} — au bureau</span>`:`<span class=\"pill pill-orange\">Max 3</span>`}",
    "${tuts.length<3?`<button class=\"btn btn-primary btn-sm\" onclick=\"openTutelleForm('${s.id}')\">➕ Ajouter</button>`:`<span class=\"pill pill-orange\">Max 3</span>`}");
  if (html === avant) { console.log('\n✗ PREUVE IMPOSSIBLE — les points à réinjecter sont introuvables.\n'); process.exit(1); }
}

// ── Navigateur en carton ─────────────────────────────────────────────────
const faux = () => ({ style:{}, value:'', innerHTML:'', dataset:{}, focus(){}, addEventListener(){},
  parentNode:{querySelector:()=>null, appendChild(){}}, scrollIntoView(){}, closest:()=>null });
globalThis.window = globalThis;
const champs = {};
globalThis.document = {
  getElementById:(id)=> (id in champs) ? Object.assign(faux(), {value:champs[id]}) : null,
  querySelector:()=>null, querySelectorAll:()=>[], createElement:()=>faux(),
  addEventListener(){}, body:{style:{}}, styleSheets:[] };
globalThis.localStorage = { getItem:()=>null, setItem(){}, removeItem(){} };
globalThis.setTimeout = (f)=>{ if(typeof f==='function') try{f();}catch(_){} return 0; };
globalThis.clearTimeout = ()=>{};
console.warn = () => {};

// ── Dépendances ──────────────────────────────────────────────────────────
const toasts = [], audits = [];
globalThis.S = { user:null, lockdown:false, page:'authorized' };
globalThis.DB = { students:[], classes:[], users:[], aps:[], scan_log:[], notifs:[],
  attendance:[], student_exit_events:[], settings:{ year:'2026-2027', gate_label:'Portail principal' } };
globalThis.DB_ONLINE = true;
globalThis.esc = (s)=>String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
globalThis.ini = (n)=>String(n||'?').slice(0,2).toUpperCase();
globalThis.toast = (m,t)=>toasts.push({m,t});
globalThis.logAudit = (a,d)=>audits.push({a,d});
globalThis.pushSync = ()=>true;
globalThis.saveToCrypt = ()=>{}; globalThis.render = ()=>{};
globalThis.closeModal = ()=>{}; globalThis.openM = ()=>{};
globalThis.markFieldError = (id,m)=>toasts.push({m:'CHAMP '+id,t:'field',msg:m});
globalThis.today = ()=>'2026-08-11';
globalThis.nowTime = ()=>'07:20';
globalThis._uid = (p='')=>p+Math.random().toString(36).slice(2,9);
globalThis.$ = (id)=>document.getElementById(id);
globalThis.gc = (id)=>DB.classes.find(c=>c.id===id);
globalThis.gu = (id)=>DB.users.find(u=>u.id===id);
globalThis.clsColor = ()=>['#333','#eee'];
globalThis._wrapDark = (h)=>h;
globalThis._estBloque = (s)=>!!(s&&(s.access_blocked||s.blocked));
globalThis.go = ()=>{};

// ── Serveur en carton ────────────────────────────────────────────────────
const appels = [];
let ACCES = 'blocked';           // ce que le serveur répond au portail
globalThis._rpc = async (nom, p) => {
  appels.push({ nom, p });
  if (nom === 'check_gate_access_status') {
    return ACCES === 'ok'
      ? { ok:true, data:{ access_status:'ok', allowed:true } }
      : { ok:true, data:{ access_status:'blocked', allowed:false, instruction:'Orienter vers la Caisse' } };
  }
  if (nom === 'cancel_student_exit_preparation') {
    // Le serveur dit que RIEN n'est parti dehors : aucun appareil enregistré.
    return { ok:true, data:{ code:'EXIT_PREPARATION_CANCELLED',
      notification:{ ok:true, channels:['app'], push_status:'none', push_device_count:0 } } };
  }
  return { ok:false, code:'PGRST202' };
};

// ── Le code réel ─────────────────────────────────────────────────────────
function extraire(debut, fin) {
  const i = html.indexOf(debut); if (i < 0) throw new Error('introuvable : ' + debut);
  const j = html.indexOf(fin, i); if (j < 0) throw new Error('fin introuvable : ' + fin);
  return html.slice(i, j);
}
globalThis.R = {};
new Function(extraire('window.ROLES_SCAN_PHYSIQUE = [', '// ── DASHBOARDS ──'))();
// `_ACCES_TTL` est un `const` du bloc : sans cette ligne il reste enfermé dans
// la portée de ce `new Function`, et `_statutPortail` — chargé plus bas — le
// lit hors de portée. Le défaut ne se voyait QUE quand le cache est non vide,
// donc seulement en mode `--preuve`. C'est la faute du harnais, pas du produit.
new Function(extraire('window._cacheAcces = {}', "// `orient` N'ADMET PAS")
             + '\nglobalThis._ACCES_TTL = _ACCES_TTL;')();
new Function(extraire('window._normAcces = (d)', 'window.processScanEntry'))();
new Function('R', extraire('window._apsValides = (sid)', "window._apQG = '';"))(globalThis.R);
new Function(extraire('window._sortieRefus =', 'R.preparer_sortie'))();
new Function(extraire('window._libelleNotif = (n)', 'R.scanner_exit'))();

// ── Jeu d'essai ──────────────────────────────────────────────────────────
DB.classes.push({ id:'c1', name:'3ᵉ Primaire A', cycle:'primaire' });
DB.students.push({ id:'s1', name:'Enfant Un', mat:'LS-0001', cid:'c1', pid:'p1' });
DB.users.push({ id:'p1', name:'Maman Un', role:'parent', phone:'+243810000111' });
// Quatre personnes : une seule est vraiment autorisée au portail.
DB.aps.push({ id:'a1', sid:'s1', name:'Tante Bonne',   active:true,  approval_status:'approved', valid_until:'2027-06-30' });
DB.aps.push({ id:'a2', sid:'s1', name:'Oncle Expiré',  active:true,  approval_status:'approved', valid_until:'2026-01-01' });
DB.aps.push({ id:'a3', sid:'s1', name:'Voisin Attente',active:true,  approval_status:'pending',  valid_until:null });
DB.aps.push({ id:'a4', sid:'s1', name:'Cousin Suspendu',active:false, approval_status:'approved', valid_until:null });
// Un second enfant, avec UNE SEULE personne, expirée. Il sert au point 7 : sous
// le filtre permissif il reste des places, donc le bouton refusé par le serveur
// se montrerait. Avec le bon filtre, il n'y a plus de bouton du tout.
DB.students.push({ id:'s2', name:'Enfant Deux', mat:'LS-0002', cid:'c1', pid:'p1' });
DB.aps.push({ id:'b1', sid:'s2', name:'Ami Expiré', active:true, approval_status:'approved', valid_until:'2026-01-01' });

const Rz = []; const ok = (q,v,d='') => Rz.push({ q, v:!!v, d });

// ═══ 5 · UN REFUS NE SE MET PLUS EN CACHE ════════════════════════════════
S.user = { id:'g1', name:'Gardien', role:'gardien' };
window._cacheAcces = {};
ACCES = 'blocked';
const d1 = await _statutPortail('s1');
ok('le portail refuse un élève bloqué', d1.allowed === false, JSON.stringify(d1.access_status));
ok('et ce refus n’entre PAS en mémoire', !window._cacheAcces['s1'], JSON.stringify(Object.keys(window._cacheAcces)));

// La famille régularise à la Caisse — sur un AUTRE appareil. Rien n'atteint
// celui du gardien : c'est le non-cache qui doit sauver l'enfant.
ACCES = 'ok';
const nAvant = appels.filter(a=>a.nom==='check_gate_access_status').length;
const d2 = await _statutPortail('s1');
ok('au rescan, le gardien REDEMANDE au serveur',
   appels.filter(a=>a.nom==='check_gate_access_status').length === nAvant + 1, '');
ok('et l’enfant régularisé passe tout de suite', d2.allowed === true, JSON.stringify(d2.access_status));
ok('la décision FAVORABLE, elle, se garde — la file avance', !!window._cacheAcces['s1'], '');

// L'inverse doit tenir aussi : un blocage tout neuf ne doit pas être masqué
// cinq minutes par une décision favorable en cache.
ACCES = 'blocked';
window._oublierAcces('s1');
const d3 = await _statutPortail('s1');
ok('un déblocage/blocage sur CE téléphone oublie la décision', d3.allowed === false, '');
ok('_oublierAcces() sans argument vide tout',
   (window._cacheAcces['x']={r:1,at:Date.now()}, window._oublierAcces(), Object.keys(window._cacheAcces).length === 0), '');

// ═══ 6 · UNE SEULE VÉRITÉ SUR « QUI PEUT RÉCUPÉRER » ═════════════════════
const valides = _apsValides('s1');
ok('seule la personne active, approuvée et dans ses dates est autorisée',
   valides.length === 1 && valides[0].id === 'a1', valides.map(a=>a.name).join(', '));
ok('une accréditation EXPIRÉE n’est pas autorisée', !valides.some(a=>a.id==='a2'), '');
ok('une personne NON APPROUVÉE n’est pas autorisée', !valides.some(a=>a.id==='a3'), '');
ok('une personne SUSPENDUE n’est pas autorisée', !valides.some(a=>a.id==='a4'), '');

const horsJeu = _apsHorsJeu('s1');
ok('les trois écartées restent VISIBLES — une fiche vide ferait croire à un oubli',
   horsJeu.length === 3, horsJeu.length + '');
ok('et chacune porte sa raison',
   horsJeu.some(x=>/expirée/i.test(x.raison)) && horsJeu.some(x=>/approbation/i.test(x.raison))
   && horsJeu.some(x=>/suspendue/i.test(x.raison)), JSON.stringify(horsJeu.map(x=>x.raison)));

// L'écran du gardien — celui que ChatGPT a nommé
S.user = { id:'g1', name:'Gardien', role:'gardien' };
const vueG = R.authorized();
ok('l’écran du gardien montre la personne autorisée', vueG.includes('Tante'), '');
ok('il ne la présente PAS comme autorisée si elle est expirée',
   !/border:2px solid #2fbf8f55[\s\S]{0,400}Expiré/.test(vueG), '');
ok('les écartées y paraissent, sous « n’ouvrent PAS le portail »',
   /n’ouvrent PAS le portail/.test(vueG) && vueG.includes('Expiré'), '');
ok('et l’écran dit qu’il n’autorise rien — la sortie se fait au portail',
   /Il n’autorise rien/.test(vueG), '');

// ═══ 7 · L'ESPACE PARENT NE PROMET PLUS CE QUE LE SERVEUR REFUSE ═════════
S.user = { id:'p1', name:'Maman Un', role:'parent' };
const vueP = R.authorized();
ok('le parent voit ses personnes autorisées', vueP.includes('Bonne'), '');
ok('aucun bouton « ➕ Ajouter » ne lui est proposé', !/➕ Ajouter/.test(vueP), '');
ok('aucun geste que le serveur refuse — ni ajout, ni suspension, ni modification',
   !/openTutelleForm\(|suspendreTutelle\(|reactiverTutelle\(/.test(vueP), '');
ok('et l’écran DIT qui enregistre, avec le geste qui marche',
   /la Direction qui les enregistre/i.test(vueP) && /bureau/i.test(vueP), '');
ok('le compte des places restantes reste juste — 3 moins les VALIDES',
   /2 places/.test(vueP), '');

// La Direction, elle, garde tous ses gestes
S.user = { id:'d1', name:'Direction', role:'direction' };
const vueD = R.authorized();
ok('la Direction garde le bouton d’ajout', /openTutelleForm\(/.test(vueD), '');
ok('et voit elle aussi ce qui n’ouvre pas le portail', /n’ouvrent pas le portail/i.test(vueD), '');

// ═══ 3 · L'ANNULATION NE PROMET PAS UN MESSAGE QUI N'EST PAS PARTI ═══════
S.user = { id:'ens1', name:'Mme Luyeye', role:'enseignant' };
DB.student_exit_events.push({ id:'ev1', sid:'s1', status:'prepared' });
champs.annulSortieMotif = 'la maman est finalement venue elle-même';
toasts.length = 0;
await confirmerAnnulationSortie('ev1');
const tA = toasts.map(t=>t.m).join(' | ');
ok('l’annulation passe bien par la RPC',
   appels.some(a=>a.nom==='cancel_student_exit_preparation'), '');
ok('elle n’annonce PAS « le parent est prévenu » sans preuve',
   !/le parent est prévenu/.test(tA), tA);
ok('elle dit ce qui est vrai — aucun appareil enregistré',
   /aucun appareil/i.test(tA), tA);

// ── Verdict ──────────────────────────────────────────────────────────────
console.log('\n═══ RECETTE — LES POINTS DE FERMETURE DU SCANNER ═══\n');
for (const r of Rz) console.log(`  ${r.v?'✓':'✗'} ${r.q}${r.v?'':'   → '+r.d}`);
const ko = Rz.filter(r=>!r.v);

if (PREUVE) {
  const cache  = Rz.find(r => /ce refus n’entre PAS en mémoire/.test(r.q));
  const verite = Rz.find(r => /seule la personne active, approuvée/.test(r.q));
  const parent = Rz.find(r => /aucun bouton « ➕ Ajouter »/.test(r.q));
  const notif  = Rz.find(r => /n’annonce PAS « le parent est prévenu »/.test(r.q));
  const vus = [['le cache',cache],['la vérité serveur',verite],
               ['la promesse au parent',parent],['la notification',notif]]
              .filter(([,r]) => r && !r.v).map(([n]) => n);
  if (vus.length === 4) {
    console.log('\n✔ PREUVE TENUE — les quatre défauts réinjectés sont revus :');
    console.log('  ' + vus.join(' · ') + '\n');
    process.exit(0);
  }
  console.log('\n✗ PREUVE MANQUÉE — seuls ' + vus.length + '/4 ont été revus (' + (vus.join(', ')||'aucun') + ').\n');
  process.exit(1);
}

console.log(`\n${ko.length ? '✗ '+ko.length+' sur '+Rz.length+' en échec'
                           : '✓ les '+Rz.length+' points passent'}\n`);
process.exit(ko.length ? 1 : 0);
