// ══════════════════════════════════════════════════════════════════════════
//  RECETTE — LA SORTIE DE L'ÉLÈVE EN DEUX ÉTAPES (issue #64)
//
//  Charge les VRAIES fonctions de dist/index.html dans Node avec un serveur
//  en carton qui répond comme les RPC de ChatGPT, et confronte le parcours
//  profil par profil.
//
//  Ce qu'elle cherche, et qui a coûté la reprise : l'ancien écran écrivait
//  dans `scan_log` sans appeler une seule des quatre RPC servies — donc sans
//  le filtre de validité des accréditations, qui vit dans la RPC. Une
//  accréditation EXPIRÉE passait pour valable au portail.
//
//  Éprouvée dans l'autre sens : `--preuve` fait mentir le serveur (il refuse)
//  et vérifie que l'écran ne prétend PAS que la sortie a réussi.
// ══════════════════════════════════════════════════════════════════════════
import { readFileSync } from 'node:fs';
import { webcrypto } from 'node:crypto';
const _crypto = globalThis.crypto || webcrypto;

const CHEMIN = process.env.SS_HTML || new URL('../dist/index.html', import.meta.url);
const html = readFileSync(CHEMIN, 'utf8');
const PREUVE = process.argv.includes('--preuve');

// ── Navigateur en carton ─────────────────────────────────────────────────
const champs = {}, toasts = [], audits = [], zones = {};
let modal = null;
const faux = () => ({ style:{}, value:'', innerHTML:'', dataset:{}, focus(){}, addEventListener(){},
  parentNode:{querySelector:()=>null, appendChild(){}}, scrollIntoView(){}, closest:()=>null });
globalThis.window = globalThis;
globalThis.document = {
  getElementById: (id) => {
    if (id in champs) { const e = faux(); e.value = champs[id]; return e; }
    if (id in zones) return zones[id];
    return null;
  },
  querySelector:()=>null, querySelectorAll:()=>[], createElement:()=>faux(),
  addEventListener(){}, body:{style:{}}, styleSheets:[],
};
try{Object.defineProperty(globalThis,'navigator',{value:{onLine:true},configurable:true});}catch(_){}
globalThis.localStorage = { getItem:()=>null, setItem(){}, removeItem(){} };
globalThis.setTimeout = (f)=>{ if(typeof f==='function') try{f();}catch(e){} return 0; };
globalThis.clearTimeout = ()=>{};

// ── Dépendances de l'application ─────────────────────────────────────────
globalThis.S = { user:null, lockdown:false, page:'scanner_exit' };
globalThis.DB = { students:[], classes:[], users:[], aps:[], scan_log:[], notifs:[],
  student_exit_events:[], settings:{ year:'2026-2027', gate_label:'Portail principal' } };
globalThis.esc = (s)=>String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
globalThis.ini = (n)=>String(n||'?').slice(0,2).toUpperCase();
globalThis.toast = (m,t)=>toasts.push({m,t});
globalThis.logAudit = (a,d)=>audits.push({a,d});
globalThis.pushSync = ()=>true;
globalThis.saveToCrypt = ()=>{};
globalThis.render = ()=>{};
globalThis.closeModal = ()=>{ modal=null; };
globalThis.openM = (t,b,f)=>{ modal={t,b,f}; };
globalThis.markFieldError = (id,msg)=>toasts.push({m:'CHAMP '+id,t:'field',msg});
globalThis.today = ()=>'2026-08-10';
globalThis.nowTime = ()=>'14:05';
globalThis._serverNow = ()=>new Date('2026-08-10T14:05:00Z');
globalThis._uid = (p='')=>p+Math.random().toString(36).slice(2,9);
globalThis._acteur = ()=>(S.user?S.user.name:'—');
globalThis._requireRole = (...ok)=> (!S.user||!ok.includes(S.user.role)) ? 'REFUS' : null;
globalThis.$ = (id)=>document.getElementById(id);
globalThis.compressImage = ()=>{};
globalThis.COMPRESS = { photo_preuve:{} };
globalThis.pushNotif = async ()=>{};
globalThis.showC = (t,m,cb)=>cb();
globalThis.gc = (id)=>DB.classes.find(c=>c.id===id);
globalThis.gu = (id)=>DB.users.find(u=>u.id===id);

// ── Le serveur en carton — il répond comme les RPC de ChatGPT ────────────
const appels = [];
globalThis._rpc = async (nom, p) => {
  appels.push({ nom, p });
  if (PREUVE) return { ok:false, code:'INVALID_ESCORT' };
  const s = DB.students.find(x=>x.id===p.p_sid);
  if (nom === 'prepare_student_exit') {
    if (!s) return { ok:false, code:'STUDENT_NOT_FOUND' };
    if (s._sansEntree) return { ok:false, code:'MISSING_ENTRY' };
    if (!s.pid) return { ok:false, code:'PRIMARY_PARENT_REQUIRED' };
    return { ok:true, data:{ code:'EXIT_PREPARED', exit_event_id:'ev_'+p.p_sid,
      status:'prepared', prepared_at:'2026-08-10T13:50:00Z', expires_at:'2026-08-10T14:20:00Z',
      notification:{ app:'sent', email:'queued', whatsapp:'queued' } } };
  }
  if (nom === 'get_student_pickup_context') {
    if (!s) return { ok:false, code:'STUDENT_NOT_FOUND' };
    return { ok:true, data:{ ok:true,
      student:{ id:s.id, name:s.name, photo:s.photo, class_id:s.cid },
      primary_parent:{ id:'p1', kind:'primary', name:'Maman Un', relation:'Parent principal',
        photo_portrait:'data:,a', photo_full_body:'data:,b', id_doc_type:'Carte d’électeur',
        id_doc_last4:'4821', ready_for_pickup:!s._parentIncomplet },
      // Le serveur a DÉJÀ écarté l'accréditation expirée : elle n'est pas là.
      authorized_people:[{ id:'aps1', kind:'accredited', name:'Tante Deux', relation:'Tante',
        photo_portrait:'data:,c', photo_full_body:'data:,d', id_doc_type:'Passeport',
        id_doc_last4:'9013', valid_until:'2027-06-30' }],
      authorized_count:1 } };
  }
  if (nom === 'scan_student_exit_at_gate') {
    if (!p.p_escort_id) return { ok:false, code:'ESCORT_REQUIRED' };
    if (!p.p_gate_label) return { ok:false, code:'GATE_REQUIRED' };
    if (S.user.role === 'enseignant' && !p.p_teacher_gate_reason) return { ok:false, code:'TEACHER_GATE_REASON_REQUIRED' };
    return { ok:true, data:{ code:'EXIT_GATE_SCANNED', exit_event_id:'ev_'+p.p_sid, status:'gate_scanned',
      gate_scanned_at:'2026-08-10T14:05:00Z', escort_name:'Tante Deux',
      photo_portrait:'data:,c', photo_full_body:'data:,d', id_doc_type:'Passeport', id_doc_last4:'9013' } };
  }
  if (nom === 'validate_student_exit') {
    if (p.p_decision === 'refused' && !p.p_note) return { ok:false, code:'REFUSAL_REASON_REQUIRED' };
    return { ok:true, data:{ code:p.p_decision==='authorized'?'EXIT_CONFIRMED':'EXIT_REFUSED',
      exit_event_id:p.p_exit_event_id, status:p.p_decision, prepared_by:'Mme Luyeye',
      scanned_by:'Gardien', validated_by:'Gardien', escort_name:'Tante Deux',
      notification:{ app:'sent', email:'queued', whatsapp:'queued' } } };
  }
  if (nom === 'cancel_student_exit_preparation') {
    if (!p.p_reason) return { ok:false, code:'REASON_REQUIRED' };
    return { ok:true, data:{ code:'EXIT_PREPARATION_CANCELLED' } };
  }
  return { ok:false, code:'PGRST202' };
};

// ── Le code réel ─────────────────────────────────────────────────────────
function extraire(debut, fin) {
  const i = html.indexOf(debut); if (i < 0) throw new Error('introuvable : ' + debut);
  const j = html.indexOf(fin, i); if (j < 0) throw new Error('fin introuvable : ' + fin);
  return html.slice(i, j);
}
const bloc = extraire('window._SORTIE_REFUS = {', 'R.scanner_exit');
globalThis.R = {};
new Function('R', bloc)(globalThis.R);

// ── Jeu d'essai ──────────────────────────────────────────────────────────
DB.classes.push({id:'c1', name:'3ᵉ Primaire A', titulaire_id:'ens1'});
DB.classes.push({id:'c2', name:'2ᵉ Primaire B', titulaire_id:'ens2'});
DB.students.push({id:'s1', name:'Enfant Un', mat:'LS-0001', cid:'c1', pid:'p1', photo:'data:,x'});
DB.students.push({id:'s2', name:'Enfant Deux', mat:'LS-0002', cid:'c2', pid:'p1', photo:'data:,y'});
DB.students.push({id:'s3', name:'Enfant Trois', mat:'LS-0003', cid:'c1', pid:null});
DB.students.push({id:'s4', name:'Enfant Quatre', mat:'LS-0004', cid:'c1', pid:'p1', _sansEntree:true});

const Rz=[]; const ok=(q,v,d)=>Rz.push({q,v:!!v,d});
const zone = () => { zones.exitResult = faux(); zones.sortieDetail = faux(); return zones.exitResult; };

// ═══ 1 · L'ENSEIGNANT PRÉPARE ════════════════════════════════════════════
S.user = { id:'ens1', name:'Mme Luyeye', role:'enseignant' };
await preparerSortie('s1');
ok('l’enseignant prépare la sortie par la RPC servie',
   appels.some(a=>a.nom==='prepare_student_exit'), appels.map(a=>a.nom).join(','));
ok('la préparation est mémorisée avec son échéance',
   (DB.student_exit_events||[]).some(e=>e.sid==='s1'&&e.status==='prepared'&&e.expires_at), '');
ok('et le portail est nommé — sinon le serveur refuse',
   appels[0].p.p_gate_label === 'Portail principal', appels[0].p.p_gate_label);

// Un élève sans parent principal
await preparerSortie('s3');
ok('sans parent principal, le refus est EXPLIQUÉ, pas avalé',
   modal && /parent principal/i.test(modal.b), modal?'modale':'aucune');
// Un élève qui n'est pas entré
await preparerSortie('s4');
ok('un élève non entré ce jour est refusé, avec sa raison',
   modal && /n’est pas entré/i.test(modal.b), '');

// ═══ 2 · L'ÉCRAN DE PRÉPARATION, PAR PROFIL ══════════════════════════════
S.user = { id:'ens1', name:'Mme Luyeye', role:'enseignant' };
const ecranEns = R.preparer_sortie();
ok('l’enseignant ne voit QUE ses classes',
   ecranEns.includes('Enfant Un') && !ecranEns.includes('Enfant Deux'), '');
ok('il lit l’état « en attente de récupération »', /en attente/i.test(ecranEns), '');
S.user = { id:'d1', name:'Direction', role:'direction' };
ok('la Direction voit toute l’école', R.preparer_sortie().includes('Enfant Deux'), '');
S.user = { id:'g1', name:'Gardien', role:'gardien' };
ok('le gardien n’a pas l’écran de préparation', R.preparer_sortie() === 'REFUS', '');
S.user = { id:'p1', name:'Parent', role:'parent' };
ok('le parent non plus', R.preparer_sortie() === 'REFUS', '');
S.user = { id:'d3', name:'Caisse', role:'direction3' };
ok('la Caisse non plus — contrat de ChatGPT', R.preparer_sortie() === 'REFUS', '');

// ═══ 3 · LE PORTAIL ══════════════════════════════════════════════════════
S.user = { id:'g1', name:'Gardien', role:'gardien' };
zone();
await ouvrirSortiePortail('s1');
ok('le portail passe par get_student_pickup_context',
   appels.some(a=>a.nom==='get_student_pickup_context'), '');
const vue = zones.exitResult.innerHTML;
ok('il montre le parent principal ET la personne accréditée',
   vue.includes('Maman Un') && vue.includes('Tante Deux'), '');
ok('il annonce que choisir n’autorise pas encore', /n’autorise pas encore/.test(vue), '');
ok('le compte à rebours de la préparation est affiché', /min restantes/.test(vue), '');
ok('« personne inconnue » reste possible', /Personne inconnue/.test(vue), '');

// La comparaison
choisirPersonneSortie(1);
const det = zones.sortieDetail.innerHTML;
ok('la comparaison montre le PORTRAIT et l’EN PIED', /PORTRAIT/.test(det)&&/EN PIED/.test(det), '');
ok('elle montre la pièce d’identité', /Passeport/.test(det), '');
ok('elle montre la validité de l’accréditation', /2027-06-30/.test(det), '');

// Étape 2 : la présentation n'autorise rien
await enregistrerPresentationPortail();
ok('la présentation appelle scan_student_exit_at_gate',
   appels.some(a=>a.nom==='scan_student_exit_at_gate'), '');
ok('mais elle n’autorise RIEN — deux boutons attendent',
   /Autoriser/.test(zones.sortieDetail.innerHTML) && /Refuser/.test(zones.sortieDetail.innerHTML), '');
ok('et l’écran le dit à haute voix',
   /pas encore sorti/.test(zones.sortieDetail.innerHTML), '');
ok('aucune validation n’a encore été appelée',
   !appels.some(a=>a.nom==='validate_student_exit'), '');

// Étape 3 : la décision
await confirmerDecisionSortie('authorized');
ok('la décision appelle validate_student_exit',
   appels.some(a=>a.nom==='validate_student_exit'), '');
const fin = zones.exitResult.innerHTML;
ok('la sortie confirmée nomme les TROIS acteurs',
   /Mme Luyeye/.test(fin) && /Gardien/.test(fin), '');
ok('l’écran ne prétend PAS que l’e-mail est parti',
   /en file d’envoi/.test(fin) && !/e-mail : envoyé/.test(fin), fin.slice(0,0));

// ═══ 4 · UN REFUS SE MOTIVE ══════════════════════════════════════════════
const avant = appels.filter(a=>a.nom==='validate_student_exit').length;
champs.sortieRefusMotif = '   ';
await confirmerDecisionSortie('refused');
ok('un refus sans motif n’atteint pas le serveur',
   appels.filter(a=>a.nom==='validate_student_exit').length === avant, '');
champs.sortieRefusMotif = 'la personne ne correspond pas aux photos';
await confirmerDecisionSortie('refused');
ok('avec son motif, le refus part',
   appels.filter(a=>a.nom==='validate_student_exit').length === avant+1, '');

// ═══ 5 · L'ENSEIGNANT AU PORTAIL DOIT SE JUSTIFIER ═══════════════════════
S.user = { id:'ens1', name:'Mme Luyeye', role:'enseignant' };
zone(); await ouvrirSortiePortail('s1'); choisirPersonneSortie(1);
ok('un enseignant au portail se voit demander pourquoi',
   /Pourquoi tenez-vous le portail/.test(zones.sortieDetail.innerHTML), '');
delete champs.sortieMotifEns;
const av2 = appels.filter(a=>a.nom==='scan_student_exit_at_gate').length;
await enregistrerPresentationPortail();
ok('sans motif, rien ne part au serveur',
   appels.filter(a=>a.nom==='scan_student_exit_at_gate').length === av2, '');
champs.sortieMotifEns = 'gardien absent';
await enregistrerPresentationPortail();
ok('avec le motif, la présentation part',
   appels.filter(a=>a.nom==='scan_student_exit_at_gate').length === av2+1, '');

// ═══ 6 · LES DROITS AU PORTAIL ═══════════════════════════════════════════
for (const [role, permis] of [['gardien',true],['enseignant',true],['direction',true],
                              ['direction2',true],['direction3',false],['parent',false]]) {
  S.user = { id:'x', name:role, role };
  zone();
  await ouvrirSortiePortail('s1');
  const passe = /Qui se présente/.test(zones.exitResult.innerHTML);
  ok(`${role} ${permis?'confirme':'ne confirme PAS'} une sortie`, passe === permis, '');
}

// ═══ 7 · LE CONFINEMENT GARDE SON EXCEPTION ══════════════════════════════
S.user = { id:'g1', name:'Gardien', role:'gardien' };
S.lockdown = true; zone();
await ouvrirSortiePortail('s1');
ok('le confinement bloque la sortie', /LOCKDOWN/.test(zones.exitResult.innerHTML), '');
ok('mais l’exception médicale reste ouverte',
   /urgence médicale/i.test(zones.exitResult.innerHTML), '');
S.lockdown = false;

// ── Verdict ──────────────────────────────────────────────────────────────
console.log('\n═══ RECETTE — LA SORTIE EN DEUX ÉTAPES ═══\n');
for (const r of Rz) console.log(`  ${r.v?'✓':'✗'} ${r.q}${r.v?'':'   → '+r.d}`);
const ko = Rz.filter(r=>!r.v);
if (PREUVE) {
  // Serveur qui refuse tout : l'écran ne doit JAMAIS annoncer une sortie.
  const ment = Rz.find(r => /confirmée nomme les TROIS/.test(r.q) && r.v);
  if (!ment) { console.log('\n✔ PREUVE TENUE — serveur qui refuse, aucune sortie annoncée.\n'); process.exit(0); }
  console.log('\n✗ PREUVE MANQUÉE — l’écran a annoncé une sortie que le serveur a refusée.\n');
  process.exit(1);
}
console.log(`\n${ko.length?'✗ '+ko.length+' sur '+Rz.length+' en échec':'✓ les '+Rz.length+' points passent'}\n`);
process.exit(ko.length?1:0);
