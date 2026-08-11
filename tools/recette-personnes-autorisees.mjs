// ══════════════════════════════════════════════════════════════════════════
//  RECETTE — LES PERSONNES AUTORISÉES (issue #64)
//
//  C'est la moitié manquante de la sortie en deux étapes : le portail
//  affichait « Aucune photo en pied » et « Aucune pièce d'identité » pour
//  tout le monde, parce qu'AUCUN ÉCRAN NE PERMETTAIT DE LES SAISIR.
//
//  Quatre RPC servies par ChatGPT n'étaient appelées par personne ; l'écran
//  écrivait directement dans `aps` — donc sans le plafond de trois tenu par
//  un verrou, sans la normalisation du numéro, sans l'audit, et sans jamais
//  renseigner ce que le portail lit.
//
//  `--preuve` accepte une image collée comme photo : le serveur la refuse
//  (`lower(photo) like 'data:%'`), et la recette doit s'en apercevoir.
// ══════════════════════════════════════════════════════════════════════════
import { readFileSync } from 'node:fs';

const CHEMIN = process.env.SS_HTML || new URL('../dist/index.html', import.meta.url);
const html = readFileSync(CHEMIN, 'utf8');
const PREUVE = process.argv.includes('--preuve');

const champs = {}, toasts = [], audits = [];
let modal = null, confirmCb = null;
const faux = (v='') => ({ style:{}, value:v, innerHTML:'', dataset:{}, focus(){},
  addEventListener(){}, parentNode:{querySelector:()=>null, appendChild(){}}, files:[] });
globalThis.window = globalThis;
globalThis.document = {
  getElementById: (id) => (id in champs ? faux(champs[id]) : null),
  querySelector:()=>null, querySelectorAll:()=>[], createElement:()=>faux(),
  addEventListener(){}, body:{style:{}}, styleSheets:[],
};
try{Object.defineProperty(globalThis,'navigator',{value:{onLine:true},configurable:true});}catch(_){}
globalThis.setTimeout = (f)=>{ if(typeof f==='function') try{f();}catch(e){} return 0; };

globalThis.S = { user:{ id:'u_dir', name:'La Direction', role:'direction' } };
globalThis.DB = { aps:[], students:[{id:'s1',name:'Enfant Un',pid:'p1'}],
  users:[{id:'p1',name:'Maman Un',role:'parent'}], settings:{} };
globalThis.esc = (s)=>String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
globalThis.toast = (m,t)=>toasts.push({m,t});
globalThis.logAudit = (a,d)=>audits.push({a,d});
globalThis.saveToCrypt = ()=>{};
globalThis.render = ()=>{};
globalThis.closeModal = ()=>{ modal=null; };
globalThis.openM = (t,b,f)=>{ modal={t,b,f}; };
globalThis.markFieldError = (id,msg)=>toasts.push({m:msg,t:'field',id});
globalThis.showC = (t,m,cb)=>{ confirmCb=cb; };
globalThis.$ = (id)=>document.getElementById(id);
globalThis.today = ()=>'2026-08-11';
globalThis._uid = (p='')=>p+Math.random().toString(36).slice(2,9);
globalThis.gc = ()=>null; globalThis.gu = (id)=>DB.users.find(u=>u.id===id);
globalThis.ini = (n)=>String(n||'?').slice(0,2);
// La transcription E.164 du navigateur, la vraie.
globalThis._telE164 = (raw) => {
  const brut = String(raw==null?'':raw).trim(); if(!brut) return null;
  let c = brut.replace(/[\s().-]/g,'');
  if (c.slice(0,2)==='00') c = '+'+c.slice(2);
  if (c[0]==='+'){ const d=c.slice(1); return /^[1-9][0-9]{7,14}$/.test(d) ? '+'+d : null; }
  if (!/^[0-9]+$/.test(c)) return null;
  let r;
  if (/^0[0-9]{9}$/.test(c)) r='+243'+c.slice(1);
  else if (/^243[0-9]{9}$/.test(c)) r='+'+c;
  else if (/^[89][0-9]{8}$/.test(c)) r='+243'+c;
  else return null;
  return /^\+[1-9][0-9]{7,14}$/.test(r) ? r : null;
};
// Le stockage : rend une adresse, ou l'image collée si le transfert échoue.
let transfertMarche = true;
globalThis._photoToStorage = async (v) => transfertMarche
  ? 'https://fichiers.cslesage.com/autorisees/' + Math.random().toString(36).slice(2,8) + '.jpg'
  : v;
// `--preuve` fait sauter le garde-fou : l'image collée part quand même vers le
// serveur, qui la refuse. C'est la panne que ce lot corrige.
if (PREUVE) {
  const vrai = globalThis._photoToStorage;
  globalThis.__forcerImageCollee = true;
}

// ── Le serveur en carton, avec les VRAIS contrôles de ChatGPT ────────────
const appels = [];
globalThis._rpc = async (nom, p) => {
  appels.push({ nom, p });
  if (nom === 'save_authorized_pickup_person') {
    const x = p.p_person;
    for (const [champ, val] of [['name',x.name],['relation',x.relation],['phone',x.phone],
                                ['id_doc_type',x.id_doc_type]]) {
      if (!val) return { ok:false, code:'VALIDATION_ERROR', raw:{field:champ} };
    }
    // LE contrôle qui compte : une image collée est refusée.
    for (const champ of ['photo_portrait','photo_full_body']) {
      const v = x[champ] || '';
      if (!v || v.toLowerCase().startsWith('data:') || v.length > 2048)
        return { ok:false, code:'VALIDATION_ERROR', raw:{field:champ} };
    }
    if (!x.id_doc_last4 || x.id_doc_last4.length < 2)
      return { ok:false, code:'VALIDATION_ERROR', raw:{field:'id_doc_last4'} };
    if (x.valid_until && x.valid_from && x.valid_until < x.valid_from)
      return { ok:false, code:'INVALID_VALIDITY_PERIOD' };
    const auj = '2026-08-11';
    const actives = DB.aps.filter(a => a.sid===x.sid && a.id!==x.id && a.active
      && a.approval_status==='approved' && (!a.valid_until || a.valid_until>=auj));
    if (actives.length >= 3) return { ok:false, code:'MAX_THREE_AUTHORIZED' };
    const enr = { ...x, id: x.id || 'aps_'+Math.random().toString(36).slice(2,8),
      photo: x.photo_portrait, active:true, approval_status:'approved',
      valid_from: x.valid_from || auj };
    return { ok:true, data:{ code: x.id?'AUTHORIZED_PERSON_UPDATED':'AUTHORIZED_PERSON_CREATED', person: enr } };
  }
  if (nom === 'set_authorized_pickup_person_status') {
    const a = DB.aps.find(y => y.id === p.p_person_id);
    if (!a) return { ok:false, code:'AUTHORIZED_PERSON_NOT_FOUND' };
    if (p.p_action === 'suspend') {
      if (!p.p_reason || p.p_reason.length < 3) return { ok:false, code:'REASON_REQUIRED' };
      return { ok:true, data:{ code:'AUTHORIZED_PERSON_SUSPENDED',
        person:{...a, active:false, approval_status:'suspended', status_note:p.p_reason} } };
    }
    if (p.p_action === 'reactivate') {
      if (!a.photo || !a.photo_full_body || !a.id_doc_type || !a.id_doc_last4)
        return { ok:false, code:'IDENTITY_INCOMPLETE' };
      return { ok:true, data:{ code:'AUTHORIZED_PERSON_REACTIVATED',
        person:{...a, active:true, approval_status:'approved', status_note:null} } };
    }
    return { ok:false, code:'UNSUPPORTED_ACTION' };
  }
  if (nom === 'save_primary_parent_pickup_identity') {
    for (const [champ, v] of [['photo_portrait',p.p_photo_portrait],['photo_full_body',p.p_photo_full_body]]) {
      if (!v || v.toLowerCase().startsWith('data:') || v.length>2048)
        return { ok:false, code:'VALIDATION_ERROR', raw:{field:champ} };
    }
    if (!p.p_id_doc_type) return { ok:false, code:'VALIDATION_ERROR', raw:{field:'id_doc_type'} };
    const u = DB.users.find(x=>x.id===p.p_parent_id && x.role==='parent');
    if (!u) return { ok:false, code:'PARENT_NOT_FOUND' };
    return { ok:true, data:{ code:'PRIMARY_PARENT_IDENTITY_SAVED', parent:u } };
  }
  if (nom === 'set_student_primary_parent') return { ok:true, data:{ code:'PRIMARY_PARENT_SET' } };
  return { ok:false, code:'PGRST202' };
};

function extraire(a,b){ const i=html.indexOf(a); if(i<0) throw new Error(a); const j=html.indexOf(b,i); if(j<0) throw new Error(b); return html.slice(i,j); }
let bloc = extraire('window._APS_REFUS = {', 'window.planifierConvocation');
if (PREUVE) {
  // On retire le contrôle « l'adresse ne doit pas rester une image collée ».
  bloc = bloc.replace("if (!url || url.indexOf('data:') === 0) return { ok:false, motif:'transfert' };",
                      "if (!url) return { ok:false, motif:'transfert' };");
}
new Function(bloc)();

const R=[]; const ok=(q,v,d)=>R.push({q,v:!!v,d});
const remplir = (o) => { for (const k in champs) delete champs[k];
  Object.assign(champs, { tut_sid:'s1', tut_id:'', tut_name:'Tante Deux', tut_relation:'Tante',
    tut_phone:'0810000111', tut_doc_type:'Passeport', tut_doc_last4:'9013',
    tut_valid_from:'', tut_valid_until:'',
    tut_photo_data:'data:image/jpeg;base64,AAAA', tut_photo_full_data:'data:image/jpeg;base64,BBBB' }, o||{}); };

// ═══ 1 · LES DEUX PHOTOS MONTENT AVANT L'APPEL ═══════════════════════════
remplir();
await saveTutelle();
const env = appels.filter(a=>a.nom==='save_authorized_pickup_person').pop();
ok('l’enregistrement passe par save_authorized_pickup_person', !!env, '');
ok('le portrait est une ADRESSE, pas une image collée',
   env && !String(env.p.p_person.photo_portrait).startsWith('data:'), env && String(env.p.p_person.photo_portrait).slice(0,24));
ok('la photo EN PIED aussi — c’est elle qui manquait au portail',
   env && env.p.p_person.photo_full_body && !String(env.p.p_person.photo_full_body).startsWith('data:'), '');
ok('le numéro part en E.164', env && env.p.p_person.phone === '+243810000111', env && env.p.p_person.phone);
ok('la pièce et ses derniers chiffres partent',
   env && env.p.p_person.id_doc_type==='Passeport' && env.p.p_person.id_doc_last4==='9013', '');
ok('et la personne est écrite en local APRÈS le succès', DB.aps.length===1, DB.aps.length);

// ═══ 2 · CE QUI MANQUE EST DIT, ET RIEN NE PART ═════════════════════════
for (const [absent, attendu] of [['tut_name','nom'], ['tut_doc_type','pièce'], ['tut_doc_last4','deux']]) {
  remplir({ [absent]: '' });
  const avant = appels.length;
  await saveTutelle();
  ok(`sans ${attendu}, aucun appel n’est fait`, appels.length === avant, '');
}
remplir({ tut_phone:'1O0' });   // la lettre O
const avantTel = appels.length;
await saveTutelle();
ok('un numéro illisible est refusé AVANT le serveur', appels.length===avantTel, '');
ok('et le champ est désigné', toasts.some(t=>t.id==='tut_phone'), '');

// ═══ 3 · UNE PHOTO QUI NE MONTE PAS N'EST PAS ENVOYÉE ═══════════════════
transfertMarche = false;
remplir();
const avantP = appels.length;
await saveTutelle();
ok('si le transfert échoue, on n’envoie pas une image collée',
   appels.length === avantP, appels.length - avantP);
ok('et on dit que c’est le transfert, pas la saisie',
   toasts.some(t=>/transfér/.test(t.m||'')), '');
transfertMarche = true;

// ═══ 4 · LE PLAFOND DE TROIS EST CELUI DU SERVEUR ═══════════════════════
DB.aps = ['a','b','c'].map((n,i)=>({ id:'aps_'+n, sid:'s1', name:'P'+i, active:true,
  approval_status:'approved', photo:'https://x/p.jpg', photo_full_body:'https://x/f.jpg',
  id_doc_type:'Passeport', id_doc_last4:'1234' }));
remplir();
await saveTutelle();
ok('une quatrième personne active est refusée par le serveur',
   toasts.some(t=>/trois personnes autorisées actives/.test(t.m||'')), '');
// Une suspendue ne prend pas la place
DB.aps[2].active = false; DB.aps[2].approval_status = 'suspended';
remplir();
await saveTutelle();
ok('mais une personne SUSPENDUE ne prend pas la place d’une autre',
   DB.aps.length === 4, DB.aps.length);

// ═══ 5 · ON SUSPEND, ON NE SUPPRIME PLUS ════════════════════════════════
ok('`deleteTutelle` n’existe plus dans le fichier',
   !/window\.deleteTutelle\s*=/.test(html), '');
ok('plus aucune suppression dans `aps`',
   !/pushSync\('aps','delete'/.test(html.split('\n').map(l=>l.replace(/^\s*\/\/.*$/,'')).join('\n')), '');
ok('ni aucune écriture directe dans `aps`',
   !/pushSync\('aps'/.test(html.split('\n').map(l=>l.replace(/^\s*\/\/.*$/,'')).join('\n')), '');

DB.aps = [{ id:'aps_x', sid:'s1', name:'Tante Deux', active:true, approval_status:'approved',
  photo:'https://x/p.jpg', photo_full_body:'https://x/f.jpg', id_doc_type:'Passeport', id_doc_last4:'9013' }];
champs.apsMotif = '  ';
await confirmerStatutTutelle('aps_x','suspend');
ok('une suspension sans motif n’atteint pas le serveur',
   !appels.some(a=>a.nom==='set_authorized_pickup_person_status'), '');
champs.apsMotif = 'la famille a retiré son autorisation';
await confirmerStatutTutelle('aps_x','suspend');
ok('avec son motif, la suspension part',
   appels.some(a=>a.nom==='set_authorized_pickup_person_status'), '');
ok('et le motif reste visible au registre',
   DB.aps[0].status_note === 'la famille a retiré son autorisation', DB.aps[0].status_note);
ok('la personne n’est PAS effacée', DB.aps.length === 1, DB.aps.length);

// Réactivation impossible si l'identité est incomplète
DB.aps[0] = { ...DB.aps[0], active:false, photo_full_body:null };
await confirmerStatutTutelle('aps_x','reactivate');
ok('on ne réactive pas quelqu’un dont l’identité est incomplète',
   toasts.some(t=>/manque une photo ou la pièce/.test(t.m||'')), '');

// ═══ 6 · L'IDENTITÉ DU PARENT PRINCIPAL ═════════════════════════════════
for (const k in champs) delete champs[k];
Object.assign(champs, { pp_portrait:'data:image/jpeg;base64,AAAA', pp_pied:'data:image/jpeg;base64,BBBB',
  pp_doc_type:'Carte d’électeur', pp_doc_last4:'4821' });
await enregistrerIdentiteParent('p1');
const ident = appels.filter(a=>a.nom==='save_primary_parent_pickup_identity').pop();
ok('l’identité du parent passe par sa RPC', !!ident, '');
ok('ses deux photos sont des adresses',
   ident && !String(ident.p.p_photo_portrait).startsWith('data:')
        && !String(ident.p.p_photo_full_body).startsWith('data:'), '');
ok('le parent est mis à jour en local après succès',
   DB.users[0].identity_document_last4 === '4821', '');

// ═══ 7 · LES DROITS ══════════════════════════════════════════════════════
for (const role of ['parent','enseignant','gardien','direction3']) {
  S.user = { id:'x', name:role, role };
  const avant = appels.length;
  remplir();
  await saveTutelle();
  ok(`${role} n’enregistre pas une personne autorisée`, appels.length===avant, '');
}
S.user = { id:'u_d2', name:'Direction 2', role:'direction2' };
remplir();
const avantD2 = appels.length;
await saveTutelle();
ok('Direction 2 le peut — comme le serveur l’autorise', appels.length>avantD2, '');
S.user = { id:'u_dir', name:'La Direction', role:'direction' };

// ── Verdict ──────────────────────────────────────────────────────────────
console.log('\n═══ RECETTE — LES PERSONNES AUTORISÉES ═══\n');
for (const r of R) console.log(`  ${r.v?'✓':'✗'} ${r.q}${r.v?'':'   → '+r.d}`);
const ko = R.filter(r=>!r.v);
if (PREUVE) {
  // Sabotage : on retire le garde-fou qui empêche d'envoyer une image collée.
  // La recette DOIT s'en apercevoir. Si elle passe quand même, elle ne
  // vérifie rien — c'est ce sens-là qu'il faut éprouver.
  const dit = R.find(r=>/si le transfert échoue/.test(r.q));
  if (dit && !dit.v) {
    console.log('\n✔ PREUVE TENUE — sans le garde-fou, la recette voit passer');
    console.log('  l’image collée que le serveur refuserait.\n');
    process.exit(0);
  }
  console.log('\n✗ PREUVE MANQUÉE — le garde-fou retiré, la recette n’a rien vu.\n');
  process.exit(1);
}
console.log(`\n${ko.length?'✗ '+ko.length+' sur '+R.length+' en échec':'✓ les '+R.length+' points passent'}\n`);
process.exit(ko.length?1:0);
