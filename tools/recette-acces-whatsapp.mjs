// ══════════════════════════════════════════════════════════════════════════
//  RECETTE — L'INVITATION PAR CODE WHATSAPP
//
//  Loms, 12 août 2026 : « l'invitation avec code sur WhatsApp, ça ne
//  fonctionne pas ».
//
//  ── CE QUE LA LECTURE A DONNÉ ────────────────────────────────────────────
//  Le parcours était juste, et le défaut n'était pas dans le parcours : il
//  était dans ce qui l'entoure. Au moment où la carte s'affiche, **LE SERVEUR
//  A DÉJÀ AGI** — le code est posé comme mot de passe Auth, l'accès précédent
//  est invalidé, le délai d'une minute court, et le code n'est rendu QU'UNE
//  FOIS : il n'est enregistré nulle part, ni ici, ni là-bas.
//
//  Or toute la chaîne d'affichage était appelée **sans un seul `catch`** :
//  `_dessinerCarteAcces` (canvas 1120×1400, `toBlob`, deux images),
//  `createObjectURL`, puis la modale. `_envoyerLienWhatsApp` avait un
//  `try { … } finally` — **sans `catch`**.
//
//  Un seul incident — canvas contaminé, mémoire courte sur un téléphone
//  d'entrée de gamme, `toBlob` qui lève — et l'écran ne montrait RIEN. La
//  Direction rappuyait : `TOO_SOON`. La personne, elle, ne pouvait plus entrer
//  avec son ancien accès et n'avait pas le nouveau.
//
//  > **Un incident d'affichage ne doit jamais coûter ce que le serveur a déjà
//  > fait.** Ce qui est irréversible passe avant ce qui est décoratif.
//
//  Éprouvée dans l'autre sens : `--preuve` retire les filets et vérifie que le
//  code redevient perdu.
// ══════════════════════════════════════════════════════════════════════════
import { readFileSync } from 'node:fs';

let html = readFileSync(process.env.SS_HTML || new URL('../dist/index.html', import.meta.url), 'utf8');
const PREUVE = process.argv.includes('--preuve');

if (PREUVE) {
  const avant = html;
  // On retire les trois filets, un par un — la panne d'origine, telle quelle.
  html = html.replace(
    'window._dessinerCarteAcces = async (ids, code) => {\n  try { return await window._dessinerCarteAccesImpl(ids, code); }\n  catch (e) { console.warn(\'[carte accès]\', e && e.message); return null; }\n};',
    'window._dessinerCarteAcces = async (ids, code) => window._dessinerCarteAccesImpl(ids, code);');
  // Le bloc ENTIER — retirer le seul `catch` laisserait un `try` orphelin, et
  // la preuve échouerait sur une faute de syntaxe au lieu de montrer la panne.
  html = html.replace(
    `    try {
      await window.ouvrirCarteAcces(uid, code, r.data.expires_at, action);
    } catch (e) {
      console.warn('[accès WhatsApp] affichage', e && e.message);
      window._carteDeSecours(u, ids0(u), code, r.data.expires_at);
    }`,
    '    await window.ouvrirCarteAcces(uid, code, r.data.expires_at, action);');
  // Le troisième filet : celui qui entoure le dessin DANS `ouvrirCarteAcces`.
  html = html.replace(
    `  let blob = null, url = null;
  try {
    blob = await window._dessinerCarteAcces(ids, code);
    url = blob ? URL.createObjectURL(blob) : null;
  } catch (e) { console.warn('[carte accès]', e && e.message); }`,
    `  const blob = await window._dessinerCarteAcces(ids, code);
  const url = blob ? URL.createObjectURL(blob) : null;`);
  if (html === avant) { console.log('\n✗ PREUVE IMPOSSIBLE — les filets sont introuvables.\n'); process.exit(1); }
}

// ── Navigateur en carton ─────────────────────────────────────────────────
const faux = () => ({ style:{}, value:'', innerHTML:'', dataset:{}, focus(){}, addEventListener(){},
  parentNode:{querySelector:()=>null, appendChild(){}}, scrollIntoView(){}, closest:()=>null, click(){} });
globalThis.window = globalThis;

// Le canvas ÉCHOUE — c'est tout l'objet de cette recette. On reproduit la
// panne réelle : `toBlob` lève une SecurityError sur un canvas contaminé.
let CANVAS_CASSE = true;
globalThis.document = {
  createElement: (t) => {
    if (t === 'canvas') {
      return { width:0, height:0,
        getContext: () => CANVAS_CASSE ? (() => { throw new Error('SecurityError: tainted canvas'); })() : null,
        toBlob: (cb) => cb(null) };
    }
    return faux();
  },
  getElementById: () => null, querySelector: () => null, querySelectorAll: () => [],
  addEventListener(){}, body:{ style:{}, appendChild(){} }, styleSheets:[],
};
globalThis.localStorage = { getItem:()=>null, setItem(){}, removeItem(){} };
globalThis.setTimeout = (f)=>{ if(typeof f==='function') try{f();}catch(_){} return 0; };
globalThis.clearTimeout = ()=>{};
globalThis.URL = { createObjectURL: () => { throw new Error('createObjectURL indisponible'); } };
console.warn = () => {};

// ── Dépendances ──────────────────────────────────────────────────────────
const toasts = [], audits = [];
let modal = null, ouvert = null;
globalThis.S = { user:{ id:'d1', name:'Mme la Directrice', role:'direction' } };
globalThis.DB = { users:[], students:[], classes:[],
  settings:{ school:{ name:'Complexe Scolaire Le Sage' } } };
globalThis.esc = (s)=>String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
globalThis.toast = (m,t)=>toasts.push({m,t});
globalThis.logAudit = (a,d)=>audits.push({a,d});
globalThis.render = ()=>{}; globalThis.closeModal = ()=>{ modal=null; };
globalThis.openM = (t,b,f)=>{ modal={t,b,f}; };
globalThis.showC = (t,m,cb)=>cb();
globalThis.saveToCrypt = ()=>{};
globalThis._roleUI = r=>r;
globalThis._acteur = ()=>S.user.name;
globalThis._btnBusy = ()=>()=>{};
globalThis.open = (u)=>{ ouvert = u; return null; };
globalThis.SCHOOL_LOGO_DOC = null;
try{Object.defineProperty(globalThis,'navigator',{value:{canShare:()=>false},configurable:true});}catch(_){}

// ── Le serveur en carton ─────────────────────────────────────────────────
// Il fait ce que fait le vrai : il POSE le code et le rend UNE fois.
let CODE_SERVEUR = 'Sa-1234-5678';       // la forme actuelle, celle de #101
const appels = [];
globalThis._edgeFn = async (nom, corps) => {
  appels.push({ nom, corps });
  if (nom !== 'parent-phone-access') return { ok:false, code:'HTTP_404' };
  return { ok:true, data:{ temporary_code: CODE_SERVEUR,
    expires_at: new Date(Date.now() + 30*60000).toISOString() } };
};

// ── Le code réel ─────────────────────────────────────────────────────────
function extraire(debut, fin) {
  const i = html.indexOf(debut); if (i < 0) throw new Error('introuvable : ' + debut);
  const j = html.indexOf(fin, i); if (j < 0) throw new Error('fin introuvable : ' + fin);
  return html.slice(i, j);
}
new Function(extraire('window._telE164 = (raw)', 'window._telApercu ='))();
new Function(extraire('window.waLink = (phone, msg)', '// LE BOUTON WHATSAPP'))();
new Function(extraire('window._accesTelephone = async', '// ── RECHERCHE GLOBALE'))();

// ── Jeu d'essai ──────────────────────────────────────────────────────────
DB.users.push({ id:'p1', name:'Maman Kabila', role:'parent', phone:'0810000111',
                initials:'MK', email:'maman@example.cd', auth_user_id:null });

const R = []; const ok = (q,v,d='') => R.push({ q, v:!!v, d });
const texteVu = () => (modal ? String(modal.t) + ' ' + String(modal.b) : '') + ' ' + toasts.map(t=>t.m).join(' | ');

// ═══ 1 · LE CANVAS ÉCHOUE — LE CODE DOIT SURVIVRE ════════════════════════
CANVAS_CASSE = true;
// SANS les filets (`--preuve`), l'exception remonte jusqu'ici. C'est LA panne
// qu'on garde : on la constate, on ne se laisse pas tomber avec elle.
let aJete = false;
try { await window._envoyerLienWhatsApp('p1'); }
catch (e) { aJete = true; }
ok('l’envoi ne se laisse pas tomber par un incident d’affichage', !aJete,
   'l’exception est remontée : tout s’arrête après que le serveur a posé le code');

ok('le serveur a bien été appelé', appels.some(a => a.nom === 'parent-phone-access'),
   JSON.stringify(appels.map(a=>a.nom)));
ok('LE CODE EST AFFICHÉ malgré l’échec du dessin', texteVu().includes(CODE_SERVEUR),
   'le serveur a posé le code et l’écran ne le montre pas — il est PERDU');
ok('l’écran dit que la carte a échoué, sans accuser la Direction',
   /n’a pas pu être dessinée/i.test(texteVu()), '');
ok('et il prévient que ce code ne sera plus jamais réaffiché',
   /ne sera plus jamais réaffiché/i.test(texteVu()), '');
ok('le message WhatsApp complet est là, prêt à copier',
   texteVu().includes('Code temporaire : ' + CODE_SERVEUR), '');
ok('le numéro y est, à la forme du serveur', texteVu().includes('+243810000111'), '');
ok('l’acte est tracé', audits.some(a => a.a === 'acces_telephone'), '');
// On interroge LE MESSAGE, pas l'écran : c'est lui qui part chez la famille.
// (Viser l'écran entier faisait échouer sur « Notez le code » — un test qui se
// trompe de cible accuse du texte parfaitement sain.)
const msgEnvoye = window._messageAccesWhatsApp(
  window._identifiantsDe(DB.users[0]), CODE_SERVEUR, null);
ok('aucune donnée d’enfant ne part dans le message',
   !/\bélève\b|\bclasse\b|\bnote\b|\bmontant\b|\bsanté\b/i.test(msgEnvoye), msgEnvoye.slice(0,80));
ok('le message porte le code et l’identifiant, rien d’autre',
   msgEnvoye.includes(CODE_SERVEUR) && msgEnvoye.includes('+243810000111'), '');

// ═══ 1 bis · MÊME LA MODALE PEUT LÂCHER — le filet de dernier recours ════
// Si `openM` lui-même échoue, `ouvrirCarteAcces` jette. Sans `catch`, le code
// disparaissait pour de bon. Le filet doit alors le montrer par un chemin qui
// ne dessine rien et ne charge aucune image — pour ne pas échouer à son tour.
{
  const vraiOpenM = globalThis.openM;
  let premierAppel = true;
  globalThis.openM = (t,b,f) => {
    if (premierAppel) { premierAppel = false; throw new Error('modale indisponible'); }
    return vraiOpenM(t,b,f);
  };
  modal = null; toasts.length = 0; DB.users[0].auth_user_id = null;
  await window._envoyerLienWhatsApp('p1');
  ok('même si la modale lâche, le filet montre le code',
     texteVu().includes(CODE_SERVEUR), 'code PERDU');
  ok('le filet dit que ce code ne reviendra pas',
     /ne sera plus jamais réaffiché/i.test(texteVu()), '');
  globalThis.openM = vraiOpenM;
}

// ═══ 2 · LE LIEN WHATSAPP EST UTILISABLE ═════════════════════════════════
const lien = window.waLink('+243810000111', 'x');
ok('le lien wa.me se construit sans le « + »', lien === 'https://wa.me/243810000111?text=x', lien);

// ═══ 3 · LE FORMAT DU CODE NE BLOQUE RIEN — il n’est qu’un avertissement ══
// Le serveur rend encore `Sa-1234-5678` (point 1 de #101, sans réponse). Ce
// format n'empêche PAS de se connecter : c'est le mot de passe Auth. L'écran
// doit le remettre tel quel, jamais le corriger ni le refuser.
ok('un code à l’ancien format est transmis TEL QUEL, pas refusé',
   texteVu().includes('Sa-1234-5678'), '');

// ═══ 4 · LE CANVAS MARCHE — le parcours normal n’a pas changé ════════════
CANVAS_CASSE = false; modal = null; toasts.length = 0; appels.length = 0;
DB.users[0].auth_user_id = null;
CODE_SERVEUR = 'LS482731';               // la forme voulue par Loms
await window._envoyerLienWhatsApp('p1');
ok('au format voulu, le code passe aussi', texteVu().includes('LS482731'), texteVu().slice(0,120));
ok('et l’avertissement de format disparaît',
   !/2 lettres \+ 6 chiffres/.test(texteVu()), '');

// ═══ 5 · LES REFUS DU SERVEUR RESTENT NOMMÉS ═════════════════════════════
globalThis._edgeFn = async () => ({ ok:false, code:'TOO_SOON', raw:{ next_allowed_at:new Date(Date.now()+45000).toISOString() } });
modal = null; toasts.length = 0;
await window._envoyerLienWhatsApp('p1');
ok('un refus « trop tôt » se dit en secondes, pas en « réessayez »',
   /attendez \d+ seconde/i.test(texteVu()), texteVu().slice(0,120));

globalThis._edgeFn = async () => ({ ok:false, code:'HTTP_404' });
modal = null; toasts.length = 0;
await window._envoyerLienWhatsApp('p1');
ok('une fonction non déployée est nommée, pas cachée',
   /n’est pas déployée/i.test(texteVu()), texteVu().slice(0,120));

// ── Verdict ──────────────────────────────────────────────────────────────
console.log('\n═══ RECETTE — L’INVITATION PAR CODE WHATSAPP ═══\n');
for (const r of R) console.log(`  ${r.v?'✓':'✗'} ${r.q}${r.v?'':'   → '+r.d}`);

console.log('\n  CE QUE CETTE RECETTE NE PEUT PAS VÉRIFIER :');
console.log('    · que `parent-phone-access` réponde vraiment — pas d’accès réseau ici ;');
console.log('    · que le code ouvre vraiment la session au premier essai ;');
console.log('    · que WhatsApp s’ouvre sur un vrai téléphone.');
console.log('    Trois points serveur restent ouverts dans l’issue #101, sans réponse.');

const ko = R.filter(r=>!r.v);
if (PREUVE) {
  const perdu = R.find(r => /LE CODE EST AFFICHÉ malgré/.test(r.q));
  const tombe = R.find(r => /ne se laisse pas tomber/.test(r.q));
  const secours = R.find(r => /même si la modale lâche/.test(r.q));
  if ((perdu && !perdu.v) || (tombe && !tombe.v) || (secours && !secours.v)) {
    console.log('\n✔ PREUVE TENUE — sans les filets, le code posé par le serveur');
    console.log('  disparaît de l’écran : exactement la panne de Loms.\n');
    process.exit(0);
  }
  console.log('\n✗ PREUVE MANQUÉE — le code a survécu sans filet, la recette ne garde rien.\n');
  process.exit(1);
}
console.log(`\n${ko.length ? '✗ '+ko.length+' sur '+R.length+' en échec'
                           : '✓ les '+R.length+' points passent'}\n`);
process.exit(ko.length ? 1 : 0);
