// ══════════════════════════════════════════════════════════════════════════
//  verif-coherence.mjs — la chaîne de calcul, exécutée
//
//  « Imagine un parent voie les cotes de devoirs de son enfant et les cotes
//    des interros, et à la fin son enfant ne réussit pas. »
//
//  Tout le reste de l'application peut être juste : si les cotes affichées ne
//  font pas la moyenne affichée, ou si deux écrans classent le même enfant
//  différemment, la famille cesse d'y croire. Cet outil charge les vraies
//  fonctions de `index.html` dans Node, leur donne un jeu d'essai dont on
//  connaît la réponse à la main, et confronte les trois chemins :
//
//    matAvgPct       la moyenne d'une matière, à partir des cotes saisies
//    _totalSection   la sommation d'une section au bulletin
//    _classer        le palmarès — classe, cycle, parent
//    getSchoolTop10  le Top 10 de l'école
//
//  Ce qu'il a trouvé la première fois : `getSchoolTop10` réimplémentait la
//  formule de `_classer` au lieu de l'appeler, et les deux copies avaient
//  divergé — 6 points d'écart sur le même enfant, et un élève diplômé l'an
//  dernier encore en tête du classement de l'école.
//
//  Usage : node tools/verif-coherence.mjs
// ══════════════════════════════════════════════════════════════════════════
import fs from 'fs';

const html = fs.readFileSync(new URL('../dist/index.html', import.meta.url), 'utf8');
const blocs = [...html.matchAll(/<script(?![^>]*src)[^>]*>([\s\S]*?)<\/script>/g)].map(m => m[1]);

// ── Un navigateur juste assez présent pour que le script se charge ─────────
const noop = () => {};
const style = () => ({ setProperty:noop, removeProperty:noop, getPropertyValue:()=>'' });
const elem = () => ({ style:style(), classList:{add:noop,remove:noop,contains:()=>false},
  addEventListener:noop, appendChild:noop, querySelector:()=>null, querySelectorAll:()=>[],
  getContext:()=>({getImageData:()=>({data:[]}), fillRect:noop, drawImage:noop}),
  toDataURL:()=>'', textContent:'', innerHTML:'', value:'', focus:noop, remove:noop });

globalThis.window = globalThis;
globalThis.addEventListener = noop; globalThis.removeEventListener = noop; globalThis.dispatchEvent = noop;
globalThis.document = { getElementById:()=>null, querySelector:()=>null, querySelectorAll:()=>[],
  createElement:elem, addEventListener:noop, body:elem(), documentElement:elem(),
  head:{appendChild:noop}, readyState:'complete' };
globalThis.localStorage = { _d:{}, getItem(k){return this._d[k]??null;}, setItem(k,v){this._d[k]=String(v);},
  removeItem(k){delete this._d[k];}, clear(){this._d={};} };
Object.defineProperty(globalThis,'navigator',{configurable:true,value:{ userAgent:'node', onLine:true,
  serviceWorker:{ register:()=>Promise.resolve({addEventListener:noop}), addEventListener:noop,
                  ready:Promise.resolve({sync:{register:noop}}), controller:null } }});
Object.defineProperty(globalThis,'location',{configurable:true,value:{ href:'http://localhost/',
  hostname:'localhost', pathname:'/', protocol:'http:', origin:'http://localhost' }});
globalThis.fetch = () => Promise.reject(new Error('hors ligne'));
globalThis.alert = noop; globalThis.confirm = () => true;
globalThis.setInterval = () => 0;              // aucune minuterie dans un test
globalThis.matchMedia = () => ({ matches:false, addListener:noop, addEventListener:noop });
globalThis.Image = function(){ return { addEventListener:noop, set src(_v){}, get src(){return '';} }; };
globalThis.FileReader = function(){ return { readAsDataURL:noop, addEventListener:noop }; };
globalThis.indexedDB = { open:()=>({ addEventListener:noop }) };
globalThis.Notification = { permission:'default', requestPermission:()=>Promise.resolve('default') };

let charges = 0, refus = [];
for (const b of blocs) { try { (0, eval)(b); charges++; } catch (e) { refus.push(e.message); } }
if (typeof window._classer !== 'function' || typeof window.getSchoolTop10 !== 'function') {
  console.error('✗ les fonctions de calcul ne se chargent pas :');
  refus.forEach(m => console.error('   ' + m));
  console.error('\n  Un stub de navigateur manque sans doute ci-dessus. Ce n\'est pas');
  console.error('  forcément un défaut de l\'application — mais tant que ce script ne');
  console.error('  tourne pas, la chaîne de calcul n\'est plus vérifiée par personne.');
  process.exit(2);
}

// ── Jeu d'essai : une classe, deux matières FR, une EN, trois élèves ───────
DB.classes = [{ id:'c1', name:'CE1', cycle:'primaire' }];
DB.matieres = [
  { id:'m1', cid:'c1', name:'Mathématiques', lang:'fr', coeff:2, active:true },
  { id:'m2', cid:'c1', name:'Français',      lang:'fr', coeff:1, active:true },
  { id:'m3', cid:'c1', name:'English',       lang:'en', coeff:1, active:true },
];
DB.students = [
  { id:'e1', name:'Amina',   cid:'c1' },
  { id:'e2', name:'Bakala',  cid:'c1' },
  // Diplômé l'an dernier. Ses notes sont encore en base : elles ne doivent
  // plus le faire figurer dans un classement de l'année en cours.
  { id:'e3', name:'Chadrac', cid:'c1', archived:true, diplome:true },
];
const note = (sid, mat, n, trim, type) =>
  ({ id:`g_${sid}_${mat}_${trim}_${type}_${n}`, sid, cid:'c1', matiere:mat,
     note:n, max:20, weight:1, trimester:trim, type, date:'2025-11-10' });
DB.grades = [
  note('e1','Mathématiques',16,'T1','devoir'), note('e1','Mathématiques',14,'T1','devoir'),
  note('e1','Mathématiques',18,'T1','interro'),
  note('e1','Français',12,'T1','devoir'),      note('e1','Français',14,'T1','interro'),
  note('e1','English',15,'T1','devoir'),
  note('e2','Mathématiques',10,'T1','devoir'), note('e2','Mathématiques',12,'T1','interro'),
  note('e2','Français',16,'T1','devoir'),      note('e2','Français',18,'T1','interro'),
  note('e2','English',11,'T1','devoir'),
  note('e3','Mathématiques',19,'T1','devoir'), note('e3','Français',19,'T1','devoir'),
  note('e3','English',19,'T1','devoir'),
];
// Amina : excellente au T1, mauvaise au T2. Un classement du T1 ne doit pas
// tenir compte du T2 — c'est là que les deux formules avaient divergé.
DB.conduct = [
  { id:'k1', sid:'e1', score:'Excellent', trimestre:'T1', date:'2025-11-01' },
  { id:'k2', sid:'e1', score:'Mauvais',   trimestre:'T2', date:'2026-02-01' },
];
DB.settings.currentTrimestre = 'T1';
if (typeof _rebuildIdx === 'function') _rebuildIdx();

let ko = 0;
const verdict = (ok, txt) => { console.log(`   ${ok?'✓':'✗'} ${txt}`); if(!ok) ko++; };

// ── 1. Les cotes saisies font-elles la moyenne affichée ? ──────────────────
console.log(`\n${charges}/${blocs.length} blocs chargés\n`);
console.log('── 1. Les cotes de devoirs et d\'interros font-elles la moyenne affichée ?\n');
const attendu = {
  'Mathématiques': Math.round(((16+14+18)/3)/20*100),   // 80
  'Français':      Math.round(((12+14)/2)/20*100),      // 65
  'English':       Math.round((15/20)*100),             // 75
};
for (const [mat, att] of Object.entries(attendu)) {
  const obtenu = matAvgPct('e1', mat, 'T1');
  verdict(obtenu === att, `${mat.padEnd(16)} cotes → ${att}%   application → ${obtenu}%`);
}

// ── 2. Bulletin par section = recalcul à la main ? ─────────────────────────
console.log('\n── 2. La sommation du bulletin suit-elle les coefficients ?\n');
const secFR = _totalSection('e1', DB.matieres.filter(m=>m.lang==='fr'), 'T1');
const secEN = _totalSection('e1', DB.matieres.filter(m=>m.lang==='en'), 'T1');
const mainFR = Math.round((attendu['Mathématiques']*2 + attendu['Français'])/3);
verdict(secFR.pct === mainFR, `section FR : bulletin ${secFR.pct}%   à la main ${mainFR}% (coeff 2 + 1)`);
verdict(secEN.pct === attendu['English'], `section EN : bulletin ${secEN.pct}%   à la main ${attendu['English']}%`);

// ── 3. Palmarès et Top 10 classent-ils pareil ? ───────────────────────────
console.log('\n── 3. Le palmarès et le Top 10 de l\'école s\'accordent-ils ?\n');
const classement = _classer(DB.students.filter(s=>!s.archived), s=>getClassMatieres(s.cid), 'T1');
const top10 = getSchoolTop10();
classement.forEach(l => console.log(`     palmarès ${l.rang}. ${l.nom.padEnd(9)} moy ${String(l.moyPct).padStart(3)}%  conduite ${String(l.condPct).padStart(3)}%  total ${l.total}`));
top10.forEach((l,i) => console.log(`     Top 10   ${i+1}. ${l.name.padEnd(9)} moy ${String(l.moyPct).padStart(3)}%                 total ${l.score}`));
console.log('');
for (const l of classement) {
  const t = top10.find(x => x.id === l.id);
  verdict(!!t && t.score === l.total,
    t ? `${l.nom.padEnd(9)} palmarès ${l.total} · Top 10 ${t.score}`
      : `${l.nom.padEnd(9)} classé au palmarès mais absent du Top 10`);
}
verdict(!top10.some(t => (DB.students.find(x=>x.id===t.id)||{}).archived),
  'aucun élève archivé (diplômé) au Top 10 de l\'école');
// Deux tableaux de bord filtrent le podium d'une classe sur `cid`.
verdict(top10.every(t => t.cid),
  '`cid` présent dans la réponse — le podium de classe des tableaux de bord en dépend');

// ── 4. Les deux générations de fiches de préparation se lisent-elles ? ─────
//
//  `cahier_prep` porte deux vocabulaires nés à des époques différentes. Les
//  colonnes des deux existent, donc rien n'est rejeté — mais chaque écran ne
//  lisait que la moitié de sa table, et une fiche remplie dans le profil
//  paraissait au suivi de la Direction sans titre, sans contenu, datée
//  « Invalid Date ». `_prepLire` réconcilie à la lecture.
console.log('\n── 4. Les deux générations de fiches de préparation se lisent-elles ?\n');
const fiches = [
  { id:'p1', cid:'c1', matiere:'Mathématiques', content:'Introduction aux fractions',
    date_prevue:'2026-02-10', by:'t1', status:'planifie', validated:true },          // écran de navigation
  { id:'p2', cid:'c1', matiere:'Français', titre:'L\'accord du participe passé',
    date_lesson:'2026-02-12', teacher_id:'t1', statut:'brouillon',
    revision:'Rappel du participe', developpement:'Les trois cas', synthese:'Règle au tableau' },
];
for (const f of fiches) {
  const l = _prepLire(f);
  const dateOk  = !!l._date && !isNaN(new Date(l._date + 'T12:00'));
  const titreOk = !!l._titre && l._titre !== 'Sans titre';
  const auteurOk = l._auteur === 't1';
  const corpsOk = !!l._corps;
  verdict(dateOk && titreOk && auteurOk && corpsOk,
    `${f.id} (${f.content ? 'ancien' : 'EPST'}) → « ${l._titre.slice(0,34)} » · ${l._date} · auteur ${l._auteur||'?'}`);
}

console.log(ko ? `\n✗ ${ko} incohérence(s) — un parent verrait deux chiffres différents pour le même enfant`
               : '\n✓ Les cotes, le bulletin et les deux classements donnent les mêmes nombres');
process.exit(ko ? 1 : 0);
