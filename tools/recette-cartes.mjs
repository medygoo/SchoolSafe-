// ═══ RECETTE NAVIGATEUR — LE REGISTRE DES CARTES, BRANCHÉ AU SERVEUR ═══════
//
// Charge les VRAIES fonctions de dist/index.html dans Node, avec un navigateur
// en carton et un serveur en carton qui répond comme les RPC de ChatGPT (#102).
//
// ── CE QUE CETTE RECETTE GARDE, ET POURQUOI ELLE A CHANGÉ DE CAMP ─────────
// Elle vérifiait un registre tenu DANS LE NAVIGATEUR : numéro séquentiel
// calculé en local, QR signé en local avec `DB.settings.qr_secret`,
// invalidation écrite en local. C'était juste tant que le serveur ne tenait
// rien. Depuis #102 il tient tout, et ces invariants-là sont devenus faux :
//
//   · `length + 1` donne le MÊME numéro à deux Directions qui émettent en même
//     temps — un registre de délivrance dont deux pièces portent le n° 42 ne
//     prouve plus rien ;
//   · un secret de signature descendu dans le navigateur est un secret publié ;
//   · le GARDIEN n'a aucune lecture sur `student_cards` : le contrôle local lui
//     répondait « CARTE INCONNUE » sur une carte parfaitement valable.
//
// Ce qu'elle garde maintenant est l'inverse : **le navigateur ne décide rien.**
// Il appelle, il reflète, et quand il ne peut pas appeler, il le DIT.
//
// Éprouvée dans l'autre sens : `--preuve` remet la vérification de signature
// DANS le navigateur — le défaut d'origine — et vérifie que la recette voit le
// portail trancher sans avoir consulté le serveur.
import { readFileSync } from 'node:fs';

let html = readFileSync(process.env.SS_HTML || new URL('../dist/index.html', import.meta.url), 'utf8');
const PREUVE = process.argv.includes('--preuve');

if (PREUVE) {
  const avant = html;
  html = html.replace(
    "  const r = await _rpc('verify_student_card_qr', { p_payload: payload });",
    `  const _p = String(payload).split('/');
  const _c = (DB.student_cards || []).find(x => x.card_no === _p[3]);
  const r = _c && _c.status === 'active'
    ? { ok:true, data:{ mat:(DB.students.find(y=>y.id===_c.sid)||{}).mat } }
    : { ok:false, code:'CARD_PERDUE' };`);
  if (html === avant) {
    console.log('\n✗ PREUVE IMPOSSIBLE — l’appel à verify_student_card_qr est introuvable.\n');
    process.exit(1);
  }
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
  getElementById: (id) => (id in champs) ? { value: champs[id], style:{}, focus(){} } : null,
  querySelector: () => null, querySelectorAll: () => [],
  addEventListener(){}, body:{ style:{}, appendChild(){} }, styleSheets: [],
};
globalThis.window = globalThis;
globalThis.document = doc;
globalThis.setTimeout = (f) => { if (typeof f === 'function') { try { f(); } catch(_){} } return 0; };
globalThis.clearTimeout = () => {};
globalThis.open = () => ({ document:{ write(){}, close(){} }, focus(){}, print(){}, close(){} });

// ── Les dépendances, écrites ici parce qu'elles sont ailleurs dans le fichier
globalThis.S = { user:{ id:'u_dir', name:'Mme la Directrice', role:'direction' } };
globalThis.DB = { students:[], classes:[], users:[], student_cards:[],
                  settings:{ year:'2026-2027' } };
globalThis.DB_ONLINE = true;
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
globalThis._codeMsg = (c) => 'Refus du serveur : ' + (c || 'inconnu');
globalThis.showScanResult = (...a) => { globalThis._dernierScan = a; };
globalThis.ssClassType = () => ({type:'carte'});
globalThis.ssGetClassPat = () => 'auto';
globalThis.ssBuildCarte = () => ({recto:'<div>recto</div>', verso:'<div>verso</div>'});
globalThis.ssBuildBadge = () => ({recto:'<div>r</div>', verso:'<div>v</div>'});
globalThis.ssRenderPreview = () => {};
// Le navigateur ne signe plus rien pour les cartes. S'il appelle encore
// `_hmacSign` sur un `card:`, la recette doit le voir — pas le lui offrir.
let hmacCartes = 0;
globalThis._hmacSign = async (_secret, message) => {
  if (String(message).startsWith('card:')) hmacCartes++;
  return 'deadbeef';
};

// ── Le serveur en carton — les cinq RPC de #102 ───────────────────────────
// Il tient le registre : numéro séquentiel, signature, une seule carte active,
// invalidation de l'ancienne AVANT activation de la nouvelle, dans la même
// « transaction ». C'est ce que le navigateur doit se contenter de refléter.
const appels = [];
let SRV = 'ok';
let FORME = 'documentee';
let seq = 0;
const srvCards = [];
const SIG = 'a'.repeat(64);

globalThis._rpc = async (nom, p) => {
  appels.push({ nom, p });
  if (SRV === 'refus') return { ok:false, code:'CARD_ISSUE_FORBIDDEN' };

  if (nom === 'issue_student_card') {
    const no = 'LS-' + p.p_year + '-' + String(++seq).padStart(4,'0');
    const ancienne = srvCards.find(c => c.sid === p.p_sid && c.year === p.p_year && c.status === 'active');
    const carte = { id:'srv_' + no, sid:p.p_sid, year:p.p_year, card_no:no,
      class_id:p.p_class_id, status:'active', emission:p.p_emission,
      motif:p.p_motif, note:p.p_note, photo:p.p_photo,
      qr_payload:'schoolsafe://card/' + no + '/' + SIG,
      issued_by_name:'Mme la Directrice', issued_at:'2026-08-10T07:30:00Z',
      print_count:1, replaces: ancienne ? ancienne.id : null };
    let remplacee = null;
    if (ancienne) {                      // AVANT l'activation, même transaction
      ancienne.status = p.p_emission === 'duplicata_perte' ? 'perdue'
                      : p.p_emission === 'duplicata_deterioration' ? 'deterioree' : 'remplacee';
      ancienne.invalidated_by_name = 'Mme la Directrice';
      ancienne.invalidated_reason = p.p_motif;
      ancienne.replaced_by = carte.id;
      remplacee = { ...ancienne };
    }
    srvCards.push(carte);
    return { ok:true, data:{ card:{...carte}, replaced_card:remplacee } };
  }

  if (nom === 'declare_student_card_lost' || nom === 'revoke_student_card') {
    const c = srvCards.find(x => x.id === p.p_card_id);
    if (!c) return { ok:false, code:'CARD_NOT_FOUND' };
    if (c.status !== 'active') return { ok:false, code:'CARD_NOT_ACTIVE' };
    c.status = nom === 'revoke_student_card' ? 'revoquee' : 'perdue';
    c.invalidated_by_name = 'Mme la Directrice';
    c.invalidated_reason = p.p_motif;
    return { ok:true, data:{ card:{...c} } };
  }

  if (nom === 'count_student_card_print') {
    const c = srvCards.find(x => x.id === p.p_card_id);
    if (!c) return { ok:false, code:'CARD_NOT_FOUND' };
    c.print_count = (c.print_count || 1) + 1;
    return { ok:true, data:{ card:{...c} } };
  }

  if (nom === 'verify_student_card_qr') {
    const parts = String(p.p_payload).split('/');
    if (parts.length !== 5)   return { ok:false, code:'CARD_NOT_FOUND' };
    if (parts[4] !== SIG)     return { ok:false, code:'CARD_INVALID_SIGNATURE' };
    const c = srvCards.find(x => x.card_no === parts[3]);
    if (!c)                   return { ok:false, code:'CARD_NOT_FOUND' };
    if (c.status === 'perdue')     return { ok:false, code:'CARD_PERDUE' };
    if (c.status === 'remplacee')  return { ok:false, code:'CARD_REMPLACEE' };
    if (c.status === 'revoquee')   return { ok:false, code:'CARD_REVOQUEE' };
    if (c.year !== DB.settings.year) return { ok:false, code:'CARD_WRONG_YEAR' };
    const s = DB.students.find(x => x.id === c.sid) || {};
    // FORME variable — c'est le sujet du §5 bis : le navigateur ne doit
    // dépendre d'AUCUN nom de champ particulier.
    if (FORME === 'imbriquee')  return { ok:true, data:{ card:{ no:c.card_no }, student:{ matricule:s.mat, nom_complet:s.name } } };
    if (FORME === 'inattendue') return { ok:true, data:{ student_mat:s.mat, libelle:s.name } };
    if (FORME === 'muette')     return { ok:true, data:{ card_no:c.card_no } };
    return { ok:true, data:{ mat:s.mat, sid:c.sid, student_name:s.name, card_no:c.card_no } };
  }
  return { ok:false, code:'PGRST202' };
};

// ── Le code réel ──────────────────────────────────────────────────────────
function extraire(nom, finMarqueur) {
  const i = html.indexOf(nom);
  if (i < 0) throw new Error('introuvable : ' + nom);
  const j = html.indexOf(finMarqueur, i);
  if (j < 0) throw new Error('fin introuvable après ' + nom);
  return html.slice(i, j);
}
const bloc      = extraire('window._CARTE_ETATS = {', '// ── CARDS STUDIO — Renderer ──');
const decodeQR  = extraire('function _decodeQR(raw) {', '// ── LE QR PERMANENT AU PORTAIL');
const resolveur = extraire('window._CARTE_REFUS = {', 'function _startDecodeLoop(video)');

// eslint-disable-next-line no-new-func
new Function(bloc + '\n' + decodeQR + '\n' + resolveur + '\nglobalThis._decodeQR = _decodeQR;')();

// ── Le jeu d'essai ────────────────────────────────────────────────────────
DB.classes.push({id:'c1', name:'3ᵉ Primaire A', cycle:'primaire'});
DB.students.push({id:'s1', name:'Enfant Un', mat:'LS-0001', cid:'c1', dob:'2017-04-02', photo:'data:,x'});
DB.students.push({id:'s2', name:'Enfant Deux', mat:'LS-0002', cid:'c1', dob:'2017-09-11', photo:'data:,y'});

const R = []; const ok = (q,v,d) => R.push({q, v:!!v, d});
const appelsDe = (n) => appels.filter(a => a.nom === n).length;

// ═══ 1 · L'APERÇU N'ÉCRIT RIEN ═══════════════════════════════════════════
apercuCarte('s1');
ok("l'aperçu n'écrit aucune carte au registre", DB.student_cards.length === 0, DB.student_cards.length + ' carte(s)');
ok("et il n'appelle pas le serveur", appels.length === 0, appels.length + ' appel(s)');

// ═══ 2 · CARTE INITIALE — ÉMISE PAR LE SERVEUR ═══════════════════════════
ouvrirEmissionCarte('s1');
champs.carteType = 'initiale'; champs.carteNote = 'remise à la maman';
await confirmerEmissionCarte('s1');
const c1 = _carteActive('s1');
ok('l’émission passe par issue_student_card', appelsDe('issue_student_card') === 1, appelsDe('issue_student_card') + ' appel(s)');
ok('la carte initiale est active', c1 && c1.status === 'active', c1 ? c1.card_no : 'aucune');
ok('son numéro vient du SERVEUR, pas d’un length+1 local',
   c1 && c1.card_no === 'LS-2026-2027-0001' && c1.id.startsWith('srv_'), c1 && c1.id);
ok('sa charge utile QR vient du serveur, signée en 64 hex',
   c1 && /^schoolsafe:\/\/card\/LS-2026-2027-0001\/[0-9a-f]{64}$/.test(c1.qr_payload||''), c1 && c1.qr_payload);
ok('le QR permanent garde ses 5 segments — distinct du quotidien',
   c1 && (c1.qr_payload||'').split('/').length === 5, (c1.qr_payload||'').split('/').length + ' segments');
ok('LE NAVIGATEUR N’A SIGNÉ AUCUNE CARTE', hmacCartes === 0, hmacCartes + ' signature(s) locale(s)');
ok('et il n’écrit plus rien en direct dans student_cards',
   sync.filter(x => x.table === 'student_cards').length === 0,
   sync.filter(x => x.table === 'student_cards').length + ' écriture(s)');

// ═══ 3 · UN MOTIF VIDE EST REFUSÉ AVANT L'ALLER-RETOUR ═══════════════════
const avantAppels = appels.length;
champs.carteType = 'duplicata_perte'; champs.carteMotif = '   '; champs.carteNote = '';
await confirmerEmissionCarte('s1');
ok('un duplicata sans motif ne part même pas au serveur', appels.length === avantAppels, appels.length + ' vs ' + avantAppels);
ok('et le champ est désigné', toasts.some(t => t.t === 'field'), '');

// ═══ 4 · DUPLICATA POUR PERTE — L'ORDRE EST TENU PAR LE SERVEUR ══════════
champs.carteMotif = 'perdue au marché, signalée par le papa';
await confirmerEmissionCarte('s1');
const c2 = _carteActive('s1');
const c1apres = _cartesDe('s1').find(c => c.id === c1.id);
ok('le duplicata devient la carte active', c2 && c2.id !== c1.id && c2.status === 'active', c2 && c2.card_no);
ok('l’ancienne carte est reflétée comme perdue', c1apres.status === 'perdue', c1apres.status);
ok('l’invalidation garde son auteur', !!c1apres.invalidated_by_name, c1apres.invalidated_by_name);
ok('l’invalidation garde son motif', (c1apres.invalidated_reason||'').includes('marché'), c1apres.invalidated_reason);
ok('l’ancienne pointe vers la nouvelle', c1apres.replaced_by === c2.id, c1apres.replaced_by);
ok('rien n’est effacé — les deux cartes restent', _cartesDe('s1').length === 2, _cartesDe('s1').length);
ok('une seule carte active par élève et par année',
   _cartesDe('s1','2026-2027').filter(c=>c.status==='active').length === 1, '');
ok('le remplacement est annoncé au serveur, pas décidé ici',
   appels.filter(a=>a.nom==='issue_student_card').slice(-1)[0].p.p_replaces === c1.id, '');

// ═══ 5 · LE PORTAIL — LA DÉCISION VIENT DU SERVEUR ═══════════════════════
const bonQR = _decodeQR(c2.qr_payload);
ok('le portail reconnaît la forme d’un QR permanent', bonQR && bonQR.carteNo === c2.card_no, bonQR && bonQR.carteNo);
ok('et il garde la charge utile ENTIÈRE pour l’envoyer', bonQR && bonQR.cartePayload === c2.qr_payload, bonQR && bonQR.cartePayload);

const nAvantVerif = appelsDe('verify_student_card_qr');
const vNouvelle = await _resoudreCarteQR(c2.qr_payload);
ok('le contrôle passe par verify_student_card_qr',
   appelsDe('verify_student_card_qr') === nAvantVerif + 1, '');
ok('la carte ACTIVE ouvre le portail', vNouvelle.ok && vNouvelle.mat === 'LS-0001', vNouvelle.titre || vNouvelle.mat);

const vPerdue = await _resoudreCarteQR(c1.qr_payload);
ok('la carte PERDUE est refusée', !vPerdue.ok, vPerdue.titre);
ok('et le gardien lit POURQUOI, dans les mots de l’école',
   /perdue/i.test(vPerdue.detail||''), vPerdue.detail);

const vFausse = await _resoudreCarteQR('schoolsafe://card/' + c2.card_no + '/' + 'b'.repeat(64));
ok('une signature fausse est refusée par le serveur', !vFausse.ok, vFausse.titre);
ok('et le motif est nommé', /Signature invalide/.test(vFausse.detail||''), vFausse.detail);

const vInconnue = await _resoudreCarteQR('schoolsafe://card/LS-2026-2027-9999/' + SIG);
ok('un numéro absent du registre est refusé', !vInconnue.ok && /registre/.test(vInconnue.detail||''), vInconnue.detail);

DB.settings.year = '2027-2028';
const vAnnee = await _resoudreCarteQR(c2.qr_payload);
ok('une carte d’une autre année est refusée', !vAnnee.ok && /année en cours/.test(vAnnee.detail||''), vAnnee.detail);
DB.settings.year = '2026-2027';

DB.students[0].archived = true;
const vArch = await _resoudreCarteQR(c2.qr_payload);
ok('un élève archivé est refusé', !vArch.ok && /ARCHIV/.test(vArch.titre||''), vArch.titre);
DB.students[0].archived = false;

// ═══ 5 bis · LE NOM DU CHAMP NE DOIT PAS DÉCIDER DE L'ACCÈS ══════════════
// ChatGPT a donné l'ENTRÉE de verify_student_card_qr, pas la FORME de sa
// réponse. Si le navigateur lit `d.mat` en dur et que le serveur nomme son
// champ autrement, **le portail refuse des cartes parfaitement valables** et
// personne ne comprend pourquoi. On ne devine donc pas un nom : on reconnaît
// une VALEUR.
for (const [forme, libelle] of [['documentee','la forme documentée'],
                                ['imbriquee','une réponse IMBRIQUÉE (student.matricule)'],
                                ['inattendue','des noms de champs INATTENDUS (student_mat)']]) {
  FORME = forme;
  const v = await _resoudreCarteQR(c2.qr_payload);
  ok(`la carte ouvre le portail avec ${libelle}`,
     v.ok && v.mat === 'LS-0001', v.titre || v.mat);
}
// Et le cas honnête : le serveur ne rend PAS l'élève du tout.
FORME = 'muette';
const vMuet = await _resoudreCarteQR(c2.qr_payload);
ok('si le serveur ne rend AUCUN élève, on refuse en le disant — sans deviner',
   !vMuet.ok && /reconnu/i.test(vMuet.detail||''), vMuet.detail);
ok('et le gardien est renvoyé vers un contrôle manuel, pas vers un mur',
   /contrôle manuel/i.test(vMuet.detail||''), vMuet.detail);
FORME = 'documentee';

// ═══ 6 · LE GARDIEN N'A PAS LE REGISTRE — ET ÇA MARCHE QUAND MÊME ════════
// C'était le défaut : il lisait `DB.student_cards`, que la RLS ne lui donne
// pas. Toute carte valable lui répondait « CARTE INCONNUE ».
const registreLocal = DB.student_cards.slice();
DB.student_cards = [];
S.user = { id:'u_gar', name:'Gardien', role:'gardien' };
const vGardien = await _resoudreCarteQR(c2.qr_payload);
ok('le gardien, sans registre local, ouvre quand même une carte valable',
   vGardien.ok && vGardien.mat === 'LS-0001', vGardien.titre || vGardien.mat);
const vGardienPerdue = await _resoudreCarteQR(c1.qr_payload);
ok('et il voit refuser une carte perdue, avec sa raison',
   !vGardienPerdue.ok && /perdue/i.test(vGardienPerdue.detail||''), vGardienPerdue.detail);
DB.student_cards = registreLocal;
S.user = { id:'u_dir', name:'Mme la Directrice', role:'direction' };

// ═══ 7 · HORS LIGNE — ON REFUSE, ET ON LE DIT ════════════════════════════
// Une carte est une pièce d'identité scolaire : l'émettre localement, c'est
// risquer deux cartes actives. Et une perte gardée dans la file laisse la
// carte ouvrir le portail.
DB_ONLINE = false;
const nHL = DB.student_cards.length, appelsHL = appels.length;
champs.carteType = 'initiale'; champs.carteMotif = ''; champs.carteNote = '';
await confirmerEmissionCarte('s2');
ok('hors ligne, aucune carte n’est émise', DB.student_cards.length === nHL, DB.student_cards.length);
ok('hors ligne, rien ne part dans la file', appels.length === appelsHL, '');
ok('et l’écran DIT pourquoi', toasts.some(t => /hors ligne/i.test(t.m)), JSON.stringify(toasts.slice(-1)));

champs.perteMotif = 'oubliée dans le taxi';
await confirmerPerteCarte('s1');
ok('hors ligne, une perte ne se déclare pas en silence',
   _carteActive('s1') !== null && toasts.some(t => /hors ligne/i.test(t.m)), '');
DB_ONLINE = true;

// ═══ 8 · LE SERVEUR REFUSE — RIEN N'EST ÉCRIT LOCALEMENT ═════════════════
SRV = 'refus';
const nRef = DB.student_cards.length;
champs.carteType = 'initiale'; champs.carteMotif = ''; champs.carteNote = '';
await confirmerEmissionCarte('s2');
ok('sur un refus serveur, aucune carte n’entre au registre local',
   DB.student_cards.length === nRef, DB.student_cards.length);
ok('et le refus s’affiche avec son code, pour le dépannage',
   /CARD_ISSUE_FORBIDDEN/.test(modalCorps||''), modalTitre);
SRV = 'ok';

// ═══ 9 · DÉCLARER PERDUE, SANS ÉMETTRE ═══════════════════════════════════
champs.perteMotif = 'oubliée dans le taxi';
await confirmerPerteCarte('s1');
ok('la déclaration passe par declare_student_card_lost', appelsDe('declare_student_card_lost') >= 1, '');
ok('la déclaration de perte invalide immédiatement', _carteActive('s1') === null, '');
ok('la carte déclarée perdue ne passe plus au portail',
   !(await _resoudreCarteQR(c2.qr_payload)).ok, '');

// ═══ 10 · LA RÉIMPRESSION SE COMPTE AU REGISTRE SERVEUR ══════════════════
champs.carteType = 'initiale'; champs.carteMotif = ''; champs.carteNote = '';
await confirmerEmissionCarte('s2');
const c3 = _carteActive('s2');
const avantPrint = c3.print_count;
await imprimerCarte(c3.id);
ok('une réimpression appelle count_student_card_print', appelsDe('count_student_card_print') === 1, '');
ok('et le compteur reflété vient du serveur', c3.print_count === avantPrint + 1, c3.print_count);

// ═══ 11 · LES DROITS ═════════════════════════════════════════════════════
const nAvant = DB.student_cards.length, apAvant = appels.length;
S.user = { id:'u_par', name:'Un parent', role:'parent' };
ok('un parent ne peut pas émettre', !_peutCarte(), '');
champs.carteType = 'initiale'; champs.carteMotif=''; champs.carteNote='';
await confirmerEmissionCarte('s2');
ok('et sa tentative n’atteint même pas le serveur', appels.length === apAvant, '');
ok('elle n’écrit rien non plus', DB.student_cards.length === nAvant, DB.student_cards.length);
await confirmerPerteCarte('s2');
ok('un parent ne peut pas déclarer une perte', appels.length === apAvant, '');
S.user = { id:'u_d2', name:'Direction 2', role:'direction2' };
ok('Direction 2 a les mêmes droits — décision de Loms', _peutCarte(), '');
S.user = { id:'u_ens', name:'Enseignant', role:'enseignant' };
ok('un enseignant ne peut pas émettre', !_peutCarte(), '');
S.user = { id:'u_c', name:'Caisse', role:'direction3' };
ok('la Caisse n’a aucun accès aux cartes — contrat #102', !_peutCarte(), '');
S.user = { id:'u_dir', name:'Mme la Directrice', role:'direction' };

// ═══ 12 · L'AUDIT ET L'INVARIANT FINAL ═══════════════════════════════════
ok('l’audit garde la trace de chaque acte', audits.length >= 3, audits.length + ' lignes');
ok('AUCUNE signature de carte n’a été calculée dans le navigateur, de bout en bout',
   hmacCartes === 0, hmacCartes + ' signature(s)');
ok('AUCUNE écriture directe sur student_cards, de bout en bout',
   sync.filter(x => x.table === 'student_cards').length === 0, '');

// ── Verdict ───────────────────────────────────────────────────────────────
console.log('\n═══ RECETTE — LE REGISTRE DES CARTES, BRANCHÉ AU SERVEUR ═══\n');
for (const r of R) console.log(`  ${r.v?'✓':'✗'} ${r.q}${r.v?'':'   → '+r.d}`);
const ko = R.filter(r=>!r.v);

if (PREUVE) {
  // La vérification est revenue dans le navigateur : le portail doit trancher
  // SANS avoir consulté le serveur. C'est ce point-là qu'on veut voir tomber,
  // nommément — pas un décompte.
  const leControle = R.find(r => /le contrôle passe par verify_student_card_qr/.test(r.q));
  const leGardien  = R.find(r => /le gardien, sans registre local/.test(r.q));
  if (leControle && !leControle.v && leGardien && !leGardien.v) {
    console.log('\n✔ PREUVE TENUE — signature vérifiée dans le navigateur : le serveur');
    console.log('  n’est plus consulté, et le gardien sans registre ne peut plus rien ouvrir.\n');
    process.exit(0);
  }
  console.log('\n✗ PREUVE MANQUÉE — le portail a tranché sans le serveur, sans être vu.\n');
  process.exit(1);
}

console.log(`\n${ko.length?'✗ '+ko.length+' sur '+R.length+' en échec':'✓ les '+R.length+' points passent'}\n`);
process.exit(ko.length?1:0);
