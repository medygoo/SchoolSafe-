// ═══ RECETTE NAVIGATEUR — P0-8 REGISTRE DES CARTES ═══
// Charge les VRAIES fonctions de dist/index.html dans Node, avec un navigateur
// en carton, et confronte le parcours complet. Le stub de createElement sait
// échapper — sans quoi tout texte échappé disparaît du test et deux
// diagnostics faux en sortent (leçon du harnais, CLAUDE.md).
import { readFileSync } from 'node:fs';
import { webcrypto } from 'node:crypto';
const _crypto = globalThis.crypto || webcrypto;

let html = readFileSync(process.env.SS_HTML || new URL('../dist/index.html', import.meta.url), 'utf8');

// ── ÉPROUVER L'OUTIL DANS L'AUTRE SENS ────────────────────────────────────
// `--preuve` retire l'invalidation de l'ancienne carte : la panne exacte que
// l'application avait avant P0-8, où un duplicata laissait la carte perdue
// valable au portail. La recette DOIT refuser. Une recette qui ne sait dire
// que « oui » ne vérifie rien.
const PREUVE = process.argv.includes('--preuve');
if (PREUVE) {
  html = html.replace(
    "    _carteInvalider(ancienne, etat, motif || _CARTE_TYPES[type].l, carte.id);",
    "    /* sabotage de la preuve : on n'invalide plus rien */");
}

// ── Le navigateur en carton ───────────────────────────────────────────────
const toasts = [], audits = [], sync = [];
let modalTitre = '', modalCorps = '', modalPied = '';
const champs = {};

const doc = {
  createElement: (tag) => {
    const el = { tagName: tag.toUpperCase(), style: {}, children: [], _text: '', innerHTML: '',
      appendChild(c){ this.children.push(c); }, setAttribute(){}, addEventListener(){},
      getContext: () => ({ fillRect(){}, fillText(){}, drawImage(){}, getImageData:()=>({data:[]}) }),
      scrollIntoView(){}, focus(){}, closest:()=>null, querySelector:()=>null,
      get textContent(){ return this._text; },
      set textContent(v){ this._text = String(v);
        this.innerHTML = String(v).replace(/&/g,'&amp;').replace(/</g,'&lt;')
          .replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;'); },
    };
    return el;
  },
  getElementById: (id) => (id in champs ? { value: champs[id], style:{}, parentNode:{querySelector:()=>null,appendChild(){}}, focus(){}, addEventListener(){}, dataset:{} } : null),
  querySelector: () => null, querySelectorAll: () => [], addEventListener(){},
  body:{appendChild(){},style:{}}, documentElement:{style:{setProperty(){}}}, styleSheets:[],
};
globalThis.document = doc;
globalThis.window = globalThis;
globalThis.localStorage = { getItem:()=>null, setItem(){}, removeItem(){} };
try{Object.defineProperty(globalThis,'navigator',{value:{onLine:true,userAgent:'node'},configurable:true});}catch(_){}
globalThis.location = { href:'http://x/', search:'', hostname:'localhost' };
globalThis.matchMedia = () => ({matches:false, addEventListener(){}, addListener(){}});
globalThis.requestAnimationFrame = (f)=>setTimeout(f,0);
globalThis.fetch = async () => ({ ok:false, status:0, json:async()=>({}), text:async()=>'' });
globalThis.open = () => null;
globalThis.alert = () => {};
globalThis.setTimeout = (f)=>{ if(typeof f==='function') try{f();}catch(e){} return 0; };
globalThis.setInterval = ()=>0; globalThis.clearTimeout=()=>{}; globalThis.clearInterval=()=>{};

// ── Le code réel : on ne prend QUE le registre des cartes et ses voisins ──
// Charger 30 000 lignes dans un navigateur en carton échouerait sur le
// premier écran ; on isole les fonctions dont la recette parle, telles
// qu'elles sont écrites dans le fichier — pas une copie.
function extraire(nom, finMarqueur) {
  const i = html.indexOf(nom);
  if (i < 0) throw new Error('introuvable : ' + nom);
  const j = html.indexOf(finMarqueur, i);
  if (j < 0) throw new Error('fin introuvable après ' + nom);
  return html.slice(i, j);
}
const bloc = extraire('window._CARTE_ETATS = {', '// ── CARDS STUDIO — Renderer ──');
const decodeQR  = extraire('function _decodeQR(raw) {', '// ── LE QR PERMANENT AU PORTAIL');
const resolveur = extraire('window._resoudreCarteQR = async', 'function _startDecodeLoop(video)');

// ── Les dépendances, écrites ici parce qu'elles sont ailleurs dans le fichier
globalThis.S = { user:{ id:'u_dir', name:'Mme la Directrice', role:'direction' } };
globalThis.DB = { students:[], classes:[], users:[], student_cards:[], settings:{ year:'2026-2027', qr_secret:'secret-de-test' } };
globalThis.esc = (s) => String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
globalThis.toast = (m,t) => toasts.push({m,t});
globalThis.logAudit = (a,d) => audits.push({a,d});
globalThis.pushSync = (table,op,data,q) => { sync.push({table,op,data,q}); return true; };
globalThis.saveToCrypt = () => {};
globalThis.render = () => {};
globalThis.closeModal = () => {};
globalThis.openM = (t,b,f) => { modalTitre=t; modalCorps=b; modalPied=f; };
globalThis.markFieldError = (id,msg) => { toasts.push({m:'ERREUR CHAMP '+id+': '+msg, t:'field'}); };
globalThis.today = () => '2026-08-10';
globalThis.nowTime = () => '07:30';
globalThis._uid = (p='') => p + Math.random().toString(36).slice(2,10);
globalThis._acteur = () => (S.user.name + ' (Direction)');
globalThis.showScanResult = (...a) => { globalThis._dernierScan = a; };
globalThis.ssClassType = () => ({type:'carte'});
globalThis.ssGetClassPat = () => 'auto';
globalThis.ssBuildCarte = () => ({recto:'<div>recto</div>', verso:'<div>verso</div>'});
globalThis.ssBuildBadge = () => ({recto:'<div>r</div>', verso:'<div>v</div>'});
globalThis.ssRenderPreview = () => {};
async function _hmacSign(secret, message) {
  const key = await _crypto.subtle.importKey('raw', new TextEncoder().encode(secret), {name:'HMAC',hash:'SHA-256'}, false, ['sign']);
  const sig = await _crypto.subtle.sign('HMAC', key, new TextEncoder().encode(message));
  return Array.from(new Uint8Array(sig)).map(b=>b.toString(16).padStart(2,'0')).join('').slice(0,8);
}
globalThis._hmacSign = _hmacSign;

// eslint-disable-next-line no-new-func
new Function('_hmacSign', bloc + '\n' + decodeQR + '\n' + resolveur + '\nglobalThis._decodeQR = _decodeQR;')(_hmacSign);

// ── Le jeu d'essai ────────────────────────────────────────────────────────
DB.classes.push({id:'c1', name:'3ᵉ Primaire A', cycle:'primaire'});
DB.students.push({id:'s1', name:'Enfant Un', mat:'LS-0001', cid:'c1', dob:'2017-04-02', photo:'data:,x'});
DB.students.push({id:'s2', name:'Enfant Deux', mat:'LS-0002', cid:'c1', dob:'2017-09-11', photo:'data:,y'});

const R = []; const ok = (q,v,d) => R.push({q, v:!!v, d});

// ═══ 1 · L'APERÇU N'ÉCRIT RIEN ═══════════════════════════════════════════
apercuCarte('s1');
ok("l'aperçu n'écrit aucune carte au registre", DB.student_cards.length === 0, DB.student_cards.length + ' carte(s)');

// ═══ 2 · CARTE INITIALE ══════════════════════════════════════════════════
ouvrirEmissionCarte('s1');
champs.carteType = 'initiale'; champs.carteNote = 'remise à la maman';
await confirmerEmissionCarte('s1');
const c1 = _carteActive('s1');
ok('la carte initiale est émise et active', c1 && c1.status === 'active', c1 ? c1.card_no : 'aucune');
ok('elle porte un numéro séquentiel de l’année', c1 && c1.card_no === 'LS-2026-2027-0001', c1 && c1.card_no);
ok('elle garde son auteur', c1 && c1.issued_by_name.includes('Directrice'), c1 && c1.issued_by_name);
ok('elle fige la photo utilisée', c1 && c1.photo === 'data:,x', c1 && c1.photo);
ok('elle porte un QR permanent signé', c1 && /^schoolsafe:\/\/card\/LS-2026-2027-0001\/[0-9a-f]{8}$/.test(c1.qr_payload||''), c1 && c1.qr_payload);
ok('le QR permanent n’a pas la forme du QR quotidien', c1 && (c1.qr_payload||'').split('/').length === 5, (c1.qr_payload||'').split('/').length + ' segments');

// ═══ 3 · UN MOTIF VIDE EST REFUSÉ ════════════════════════════════════════
const avant = DB.student_cards.length;
champs.carteType = 'duplicata_perte'; champs.carteMotif = '   '; champs.carteNote = '';
await confirmerEmissionCarte('s1');
ok('un duplicata sans motif est refusé', DB.student_cards.length === avant, DB.student_cards.length + ' vs ' + avant);
ok('et le champ est désigné', toasts.some(t => t.t === 'field'), '');

// ═══ 4 · DUPLICATA POUR PERTE ════════════════════════════════════════════
champs.carteMotif = 'perdue au marché, signalée par le papa';
await confirmerEmissionCarte('s1');
const c2 = _carteActive('s1');
const c1apres = _cartesDe('s1').find(c => c.id === c1.id);
ok('le duplicata devient la carte active', c2 && c2.id !== c1.id && c2.status === 'active', c2 && c2.card_no);
ok('l’ANCIENNE carte est invalidée — statut perdue', c1apres.status === 'perdue', c1apres.status);
ok('l’invalidation garde son auteur', !!c1apres.invalidated_by_name, c1apres.invalidated_by_name);
ok('l’invalidation garde son motif', (c1apres.invalidated_reason||'').includes('marché'), c1apres.invalidated_reason);
ok('l’ancienne pointe vers la nouvelle', c1apres.replaced_by === c2.id, c1apres.replaced_by);
ok('rien n’est effacé — les deux cartes restent', _cartesDe('s1').length === 2, _cartesDe('s1').length);
ok('une seule carte active par élève et par année', _cartesDe('s1','2026-2027').filter(c=>c.status==='active').length === 1, '');
ok('les numéros ne se réutilisent pas', c2.card_no !== c1.card_no, c2.card_no);

// ═══ 5 · LE PORTAIL ══════════════════════════════════════════════════════
const bonQR = _decodeQR(c2.qr_payload);
ok('le portail reconnaît un QR permanent', bonQR && bonQR.carteNo === c2.card_no, bonQR && bonQR.carteNo);
const vNouvelle = await _resoudreCarteQR(c2.card_no, bonQR.carteSig);
ok('la carte ACTIVE ouvre le portail', vNouvelle.ok && vNouvelle.mat === 'LS-0001', JSON.stringify(vNouvelle.titre||vNouvelle.mat));

const perduQR = _decodeQR(c1.qr_payload);
const vPerdue = await _resoudreCarteQR(c1.card_no, perduQR.carteSig);
ok('la carte PERDUE est refusée au portail', !vPerdue.ok, vPerdue.titre);
ok('et le gardien lit POURQUOI', /PERDUE/.test(vPerdue.titre||''), vPerdue.titre);

const vFausse = await _resoudreCarteQR(c2.card_no, 'deadbeef');
ok('une signature fausse est refusée', !vFausse.ok && /FALSIFI/.test(vFausse.titre), vFausse.titre);

const vInconnue = await _resoudreCarteQR('LS-2026-2027-9999', await _hmacSign('secret-de-test','card:LS-2026-2027-9999'));
ok('un numéro absent du registre est refusé', !vInconnue.ok && /INCONNUE/.test(vInconnue.titre), vInconnue.titre);

// Carte d'une autre année
DB.settings.year = '2027-2028';
const vAnnee = await _resoudreCarteQR(c2.card_no, bonQR.carteSig);
ok('une carte d’une autre année est refusée', !vAnnee.ok && /ANNÉE/.test(vAnnee.titre), vAnnee.titre);
DB.settings.year = '2026-2027';

// Élève archivé
DB.students[0].archived = true;
const vArch = await _resoudreCarteQR(c2.card_no, bonQR.carteSig);
ok('un élève archivé est refusé', !vArch.ok && /ARCHIV/.test(vArch.titre), vArch.titre);
DB.students[0].archived = false;

// ═══ 6 · DÉCLARER PERDUE, SANS ÉMETTRE ═══════════════════════════════════
champs.perteMotif = 'oubliée dans le taxi';
confirmerPerteCarte('s1');
ok('la déclaration de perte invalide immédiatement', _carteActive('s1') === null, '');
ok('la carte déclarée perdue ne passe plus', !(await _resoudreCarteQR(c2.card_no, bonQR.carteSig)).ok, '');

// ═══ 7 · LES DROITS ══════════════════════════════════════════════════════
const nAvant = DB.student_cards.length;
S.user = { id:'u_par', name:'Un parent', role:'parent' };
ok('un parent ne peut pas émettre', !_peutCarte(), '');
champs.carteType = 'initiale'; champs.carteMotif=''; champs.carteNote='';
await confirmerEmissionCarte('s2');
ok('et sa tentative n’écrit rien', DB.student_cards.length === nAvant, DB.student_cards.length);
confirmerPerteCarte('s2');
ok('un parent ne peut pas déclarer une perte', DB.student_cards.every(c => c.invalidated_reason !== 'oubliée dans le taxi' || c.sid === 's1'), '');
S.user = { id:'u_d2', name:'Direction 2', role:'direction2' };
ok('Direction 2 a les mêmes droits — décision de Loms', _peutCarte(), '');
S.user = { id:'u_ens', name:'Enseignant', role:'enseignant' };
ok('un enseignant ne peut pas émettre', !_peutCarte(), '');
S.user = { id:'u_dir', name:'Mme la Directrice', role:'direction' };

// ═══ 8 · LE REGISTRE PART VERS LE SERVEUR ════════════════════════════════
ok('chaque émission est poussée vers student_cards',
  sync.filter(x => x.table === 'student_cards' && x.op === 'post').length === 2,
  sync.filter(x => x.table === 'student_cards' && x.op === 'post').length + ' post');
ok('chaque invalidation est poussée aussi',
  sync.filter(x => x.table === 'student_cards' && x.op === 'patch').length >= 2, '');
ok('l’audit garde la trace de chaque acte', audits.length >= 3, audits.length + ' lignes');

// ═══ 9 · SANS SECRET, PAS DE FAUX QR ═════════════════════════════════════
DB.settings.qr_secret = null;
champs.carteType = 'initiale'; champs.carteMotif=''; champs.carteNote='';
await confirmerEmissionCarte('s2');
const cSansSecret = _carteActive('s2');
ok('sans secret posé, aucun QR n’est fabriqué', cSansSecret && cSansSecret.qr_payload === null, String(cSansSecret && cSansSecret.qr_payload));

// ── Verdict ───────────────────────────────────────────────────────────────
console.log('\n═══ RECETTE — LE REGISTRE DES CARTES ═══\n');
for (const r of R) console.log(`  ${r.v?'✓':'✗'} ${r.q}${r.v?'':'   → '+r.d}`);
const ko = R.filter(r=>!r.v);
if (PREUVE) {
  if (ko.length) {
    console.log(`\n✔ PREUVE TENUE — sans l'invalidation, ${ko.length} point(s) tombent.`);
    console.log('  Dont : « ' + ko[0].q + ' »\n');
    process.exit(0);
  }
  console.log("\n✗ PREUVE MANQUÉE — la recette a laissé passer un duplicata");
  console.log('  qui n\'invalide pas l\'ancienne carte. Elle ne vérifie rien.\n');
  process.exit(1);
}
console.log(`\n${ko.length?'✗ '+ko.length+' sur '+R.length+' en échec':'✓ les '+R.length+' points passent'}\n`);
process.exit(ko.length?1:0);
