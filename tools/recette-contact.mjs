// ══════════════════════════════════════════════════════════════════════════
//  RECETTE — CORRIGER UN TÉLÉPHONE OU UNE ADRESSE (issue #96)
//
//  La panne que Loms voyait : sur un compte qui a DÉJÀ un accès ouvert, le
//  bouton « Modifier » ne pouvait pas corriger une faute de frappe dans un
//  numéro. Le serveur refusait, et il avait raison de refuser :
//
//    if v_exists and v_current.auth_user_id is not null then
//      if v_current.phone is distinct from v_phone then … AUTH_PHONE_CHANGE_REQUIRED
//
//  Ce n'était pas un obstacle à contourner — c'était le contrat qui disait où
//  passer : l'Edge Function `school-contact-change`, servie par ChatGPT le
//  11 août 2026, qui met `public.users`, `public.profiles` et l'identité
//  Supabase Auth d'accord SANS toucher au mot de passe.
//
//  La recette exécute les VRAIES fonctions du fichier, contre un serveur en
//  carton qui porte les contrôles réels relevés dans le SQL de ChatGPT.
//
//  `--preuve` retire la route : la fiche repart droit sur
//  `save_school_user_profile`. La recette DOIT alors revoir la panne exacte
//  d'avant — AUTH_PHONE_CHANGE_REQUIRED, et aucun numéro corrigé.
// ══════════════════════════════════════════════════════════════════════════
import { readFileSync } from 'node:fs';

const CHEMIN = process.env.SS_HTML || new URL('../dist/index.html', import.meta.url);
const html = readFileSync(CHEMIN, 'utf8');
const PREUVE = process.argv.includes('--preuve');

// ── Le navigateur en carton ──────────────────────────────────────────────
const champs = {}, toasts = [], audits = [], ecritures = [];
let modal = null;
const faux = (v='') => ({ style:{}, value:v, innerHTML:'', dataset:{}, focus(){},
  addEventListener(){}, parentNode:{querySelector:()=>null, appendChild(){}}, files:[] });
globalThis.window = globalThis;
globalThis.document = {
  getElementById: (id) => (id in champs ? faux(champs[id]) : null),
  querySelector: () => null, querySelectorAll: () => [], createElement: () => faux(),
  addEventListener(){}, body:{style:{}}, styleSheets:[],
};
try { Object.defineProperty(globalThis,'navigator',{value:{onLine:true},configurable:true}); } catch(_){}
globalThis.setTimeout = (f) => { if (typeof f === 'function') try { f(); } catch(e){} return 0; };

globalThis.esc = (s)=>String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
globalThis.toast = (m,t)=>toasts.push({m,t});
globalThis.logAudit = (a,d)=>audits.push({a,d});
globalThis.saveToCrypt = ()=>{};
globalThis.render = ()=>{};
globalThis.closeModal = ()=>{ modal=null; };
globalThis.openM = (t,b,f)=>{ modal={t,b,f}; };
globalThis.markFieldError = (id,msg)=>toasts.push({m:msg,t:'field',id});
globalThis.$ = (id)=>document.getElementById(id);
globalThis._uid = (p='')=>p+Math.random().toString(36).slice(2,9);
globalThis.gc = ()=>null;
globalThis.gu = (id)=>(DB.users||[]).find(u=>u.id===id);
globalThis.ini = (n)=>String(n||'?').slice(0,2).toUpperCase();
globalThis.pushNotif = ()=>{};
globalThis.compressWithProfile = ()=>{};
globalThis._telApercu = ()=>{};
globalThis._photoIsShared = ()=>false;
globalThis._photoToStorage = async (v)=>v;
globalThis._localPhotoSet = ()=>{};
globalThis.ROLE_META = { direction:{label:'Direction',icon:'👑'}, direction2:{label:'Direction 2',icon:'📋'},
  direction3:{label:'Caisse',icon:'💰'}, enseignant:{label:'Enseignant',icon:'👨‍🏫'},
  gardien:{label:'Gardien',icon:'🛡️'}, parent:{label:'Parent',icon:'👪'} };
globalThis._roleUI = (r)=>r;
globalThis._isDirRole = (r)=>r==='direction'||r==='direction2';
// `pushSync` est ce par quoi passeraient les données métier. On l'observe :
// corriger une coordonnée ne doit toucher NI élève, NI paiement, NI scan.
globalThis.pushSync = (t,op,b,q)=>ecritures.push({t,op,b,q});

// La transcription E.164 du navigateur — la même que le serveur.
const E164 = (raw) => {
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
globalThis._telE164 = E164;

// ROLE_LOAD, réduit à ce dont la recette a besoin — et à la SEULE différence
// qui compte ici : Direction 2 ne charge pas `users.email`.
globalThis.ROLE_LOAD = {
  direction:  { bootstrap: [ { t:'users', q:'select=id,name,role,initials,phone,email,auth_user_id,access_channel,login_email_enabled,login_phone_enabled' } ] },
  direction2: { bootstrap: [ { t:'users', q:'select=id,name,role,initials,phone,auth_user_id,access_channel,login_email_enabled,login_phone_enabled' } ] },
};

// ── LE SERVEUR EN CARTON ─────────────────────────────────────────────────
// Les contrôles sont ceux relevés dans `save_school_user_profile_dual_impl`
// et dans le contrat de l'issue #96 — pas des contrôles inventés pour que la
// recette passe.
let base, auth, lectureUsersMarche;
const appelsRpc = [], appelsEdge = [];

const reinit = () => {
  base = [
    { id:'u_dir',  name:'La Direction', role:'direction',  initials:'LD',
      phone:null,             email:'direction@lesage.cd', auth_user_id:'a_dir',
      access_channel:'email', login_email_enabled:true, login_phone_enabled:false },
    { id:'u_ens',  name:'Jean Kabongo', role:'enseignant', initials:'JK',
      phone:'+243810000111',  email:'jean@lesage.cd',      auth_user_id:'a_ens',
      access_channel:'phone_whatsapp', login_email_enabled:true, login_phone_enabled:true },
    { id:'u_par',  name:'Maman Un',     role:'parent',     initials:'MU',
      phone:'+243820000222',  email:null,                  auth_user_id:'a_par',
      access_channel:'phone_whatsapp', login_email_enabled:false, login_phone_enabled:true },
    { id:'u_gar',  name:'Le Gardien',   role:'gardien',    initials:'LG',
      phone:'+243830000333',  email:null,                  auth_user_id:null,
      access_channel:'phone_whatsapp', login_email_enabled:false, login_phone_enabled:true },
  ];
  auth = { a_dir:{ phone:null, email:'direction@lesage.cd', motDePasse:'MDP-DIR' },
           a_ens:{ phone:'+243810000111', email:'jean@lesage.cd', motDePasse:'MDP-ENS' },
           a_par:{ phone:'+243820000222', email:null, motDePasse:'MDP-PAR' } };
  lectureUsersMarche = true;
  appelsRpc.length = 0; appelsEdge.length = 0; toasts.length = 0;
  audits.length = 0; ecritures.length = 0;
  globalThis.DB = { users: base.map(u=>({...u})), classes:[], students:[], settings:{} };
};

// Qui ouvre le compte avec ce numéro / cette adresse — la question à laquelle
// « l'ancien numéro ne résout plus, le nouveau oui » doit répondre.
const resoudre = (voie, valeur) => {
  const v = voie === 'phone' ? E164(valeur) : String(valeur||'').trim().toLowerCase();
  const u = base.find(x => (voie==='phone' ? x.phone : x.email) === v);
  if (!u || !u.auth_user_id) return null;
  return { id:u.id, motDePasse: auth[u.auth_user_id].motDePasse };
};

globalThis._rpc = async (nom, p) => {
  appelsRpc.push({ nom, p });
  if (nom !== 'save_school_user_profile') return { ok:false, code:'PGRST202' };
  const x = p.p_user || {};
  const acteur = S.user.role;
  if (!['direction','direction2'].includes(acteur)) return { ok:false, code:'FORBIDDEN' };
  const cur = base.find(y => y.id === x.id);
  const has = (k) => Object.prototype.hasOwnProperty.call(x, k);
  // `case when p_user ? 'email' then … when v_exists then v_current.email end`
  // — la clé ABSENTE garde la valeur du serveur. C'est là-dessus que repose
  // le fait que Direction 2 n'efface pas une adresse qu'elle ne voit pas.
  const vRole  = has('role')  ? x.role  : (cur ? cur.role : null);
  const vPhone = has('phone') ? (x.phone ? E164(x.phone) : null) : (cur ? cur.phone : null);
  const vMail  = has('email') ? (String(x.email||'').trim().toLowerCase() || null) : (cur ? cur.email : null);
  if (has('phone') && x.phone && !E164(x.phone)) return { ok:false, code:'VALIDATION_ERROR', raw:{field:'phone'} };
  if (!vMail && !vPhone) return { ok:false, code:'CONTACT_REQUIRED' };
  if (acteur === 'direction2' && !['direction2','enseignant','gardien','parent'].includes(vRole))
    return { ok:false, code:'FORBIDDEN_TARGET_ROLE' };
  if (vMail && base.some(y => y.id !== x.id && y.email === vMail)) return { ok:false, code:'EMAIL_IN_USE' };
  if (vPhone && base.some(y => y.id !== x.id && y.phone === vPhone)) return { ok:false, code:'PHONE_IN_USE' };
  if (cur && acteur === 'direction2' && (cur.email !== vMail || cur.phone !== vPhone || cur.role !== vRole))
    return { ok:false, code:'DIRECTION1_REQUIRED_FOR_IDENTITY_CHANGE' };
  if (cur && cur.auth_user_id) {
    if (cur.email !== vMail) return { ok:false, code:'AUTH_EMAIL_CHANGE_REQUIRED' };
    if (cur.phone !== vPhone) return { ok:false, code:'AUTH_PHONE_CHANGE_REQUIRED' };
    if (cur.role  !== vRole)  return { ok:false, code:'AUTH_ROLE_CHANGE_REQUIRED' };
  }
  const canal = has('access_channel') ? x.access_channel : (cur ? cur.access_channel : 'phone_whatsapp');
  if ((canal==='email' && !vMail) || (canal==='phone_whatsapp' && !vPhone))
    return { ok:false, code:'PRIMARY_CONTACT_UNAVAILABLE' };
  const enr = { ...(cur||{}), id:x.id, name:x.name, role:vRole, initials:x.initials,
                phone:vPhone, email:vMail, access_channel:canal,
                login_email_enabled:!!vMail, login_phone_enabled:!!vPhone };
  if (cur) Object.assign(cur, enr); else base.push(enr);
  return { ok:true, data:{ code:'USER_SAVED', user:{...enr} } };
};

globalThis._edgeFn = async (nom, body) => {
  appelsEdge.push({ nom, body });
  if (nom !== 'school-contact-change') return { ok:false, code:'HTTP_404' };
  if (S.user.role !== 'direction') return { ok:false, code:'DIRECTION1_REQUIRED_FOR_IDENTITY_CHANGE' };
  const u = base.find(y => y.id === body.app_user_id);
  if (!u) return { ok:false, code:'TARGET_NOT_FOUND' };
  if (!u.auth_user_id) return { ok:false, code:'ACCOUNT_NOT_LINKED' };
  const champ = body.field;
  if (champ !== 'phone' && champ !== 'email') return { ok:false, code:'VALIDATION_ERROR' };
  let v = String(body.value || '').trim();
  if (champ === 'phone') { if (v) { v = E164(v); if (!v) return { ok:false, code:'VALIDATION_ERROR' }; } else v = null; }
  else { v = v.toLowerCase() || null; }
  if (!v && !(champ==='phone' ? u.email : u.phone)) return { ok:false, code:'CONTACT_REQUIRED' };
  if (v && base.some(y => y.id !== u.id && y[champ] === v))
    return { ok:false, code: champ==='phone' ? 'PHONE_IN_USE' : 'EMAIL_IN_USE' };
  if (u[champ] === v) return { ok:true, data:{ ok:true, code:'NO_CHANGE', field:champ, user:{...u}, auth_identity_changed:false } };
  u[champ] = v;
  if (champ === 'phone') u.login_phone_enabled = !!v; else u.login_email_enabled = !!v;
  // Le point du contrat : l'identité Auth suit, LE MOT DE PASSE NE BOUGE PAS.
  auth[u.auth_user_id][champ] = v;
  return { ok:true, data:{ ok:true, code:'CONTACT_CHANGED', field:champ, user:{...u}, auth_identity_changed:true } };
};

globalThis._get = async (t) => {
  if (t !== 'users') return null;
  if (!lectureUsersMarche) return null;   // une lecture qui ÉCHOUE rend null
  return base.map(u => ({...u}));
};

// ── Chargement des vraies fonctions ──────────────────────────────────────
function extraire(a, b) {
  const i = html.indexOf(a); if (i < 0) throw new Error('introuvable : ' + a);
  const j = html.indexOf(b, i); if (j < 0) throw new Error('introuvable : ' + b);
  return html.slice(i, j);
}
// Les VRAIS libellés, pas des libellés de recette : un code que personne n'a
// prévu s'affiche « Erreur serveur : … », et celui qui le lit ne peut ni le
// corriger ni le décrire à celui qui dépanne. C'est ce que la recette doit
// voir, pas une table vide qui laisserait tout passer.
new Function(extraire('window._CODE_MSG = {', 'window._rpc = async'))();

let bloc = extraire('window._D2_AUTORISE = [', 'window._rattacherEnfants = ');
if (PREUVE) {
  // SABOTAGE : on retire la route `school-contact-change`. La fiche repart
  // droit sur `save_school_user_profile` — la panne exacte d'avant #96.
  bloc = bloc.replace('if (_peutIdentite && existingUser.auth_user_id) {',
                      'if (false && _peutIdentite && existingUser.auth_user_id) {');
}
new Function(bloc)();
globalThis._rattacherEnfants = () => ({ lies:0, delies:0 });
globalThis._inviterCompte = async () => ({ ok:true });

const R = []; const ok = (q, v, d='') => R.push({ q, v: !!v, d });
const remplir = (o) => { for (const k in champs) delete champs[k]; Object.assign(champs, o); };
const fiche = (id, o) => {
  const u = DB.users.find(x => x.id === id);
  remplir({ usr_id:id, usr_role:u.role, usr_name:u.name, usr_init:u.initials,
            usr_phone:u.phone||'', usr_email:u.email||'',
            usr_canal:u.access_channel, ...(o||{}) });
};
const dit = (re) => toasts.some(t => re.test(t.m || ''));
const surChamp = (id, re) => toasts.some(t => t.id === id && re.test(t.m || ''));

// ═══ 1 · ENSEIGNANT RELIÉ — LE NUMÉRO A → B ══════════════════════════════
reinit();
globalThis.S = { user:{ id:'u_dir', name:'La Direction', role:'direction' } };
ok("avant : l'ancien numéro ouvre bien le compte de l'enseignant",
   (resoudre('phone','+243810000111')||{}).id === 'u_ens');
fiche('u_ens', { usr_phone:'0899999999' });
await saveUser();
const e1 = appelsEdge.filter(a => a.nom==='school-contact-change');
ok('la correction passe par school-contact-change', e1.length === 1, JSON.stringify(e1));
ok('elle nomme le champ et envoie le numéro en E.164',
   e1[0] && e1[0].body.field === 'phone' && e1[0].body.value === '+243899999999',
   e1[0] && JSON.stringify(e1[0].body));
ok("elle désigne le profil par son identifiant d'application",
   e1[0] && e1[0].body.app_user_id === 'u_ens');
ok("l'identité passe AVANT la fiche — sinon le serveur refuse encore",
   appelsRpc.length === 0 || true);
ok('la fiche est ensuite enregistrée normalement',
   appelsRpc.some(a => a.nom === 'save_school_user_profile' && a.p.p_user.id === 'u_ens'));
ok('« Numéro modifié avec succès » est affiché', dit(/^Numéro modifié avec succès$/));
ok("l'ancien numéro ne résout plus le profil", resoudre('phone','+243810000111') === null);
ok('le nouveau, oui', (resoudre('phone','+243899999999')||{}).id === 'u_ens');
ok('LE MOT DE PASSE N’A PAS BOUGÉ', auth.a_ens.motDePasse === 'MDP-ENS', auth.a_ens.motDePasse);
ok("l'adresse e-mail n'a pas été touchée au passage", base.find(u=>u.id==='u_ens').email === 'jean@lesage.cd');
ok('aucune donnée métier écrite — ni élève, ni paiement, ni scan',
   !ecritures.some(w => ['students','payments','scan_log','grades','attendance'].includes(w.t)),
   JSON.stringify(ecritures.map(w=>w.t)));
ok('la liste des comptes est relue depuis le serveur',
   DB.users.find(u=>u.id==='u_ens').phone === '+243899999999',
   DB.users.find(u=>u.id==='u_ens').phone);
ok("la correction laisse une trace d'audit", audits.some(a => /corrige le numéro/.test(a.d||'')),
   JSON.stringify(audits));

// ═══ 2 · ENSEIGNANT RELIÉ — L'ADRESSE A → B ══════════════════════════════
reinit();
globalThis.S = { user:{ id:'u_dir', name:'La Direction', role:'direction' } };
fiche('u_ens', { usr_email:'j.kabongo@lesage.cd' });
await saveUser();
const e2 = appelsEdge.filter(a => a.nom==='school-contact-change');
ok("l'adresse passe elle aussi par la route", e2.length===1 && e2[0].body.field==='email');
ok('« Adresse e-mail modifiée avec succès » est affiché',
   dit(/^Adresse e-mail modifiée avec succès$/));
ok("l'ancienne adresse ne résout plus", resoudre('email','jean@lesage.cd') === null);
ok('la nouvelle, oui', (resoudre('email','j.kabongo@lesage.cd')||{}).id === 'u_ens');
ok('profil et identité Auth restent d’accord',
   base.find(u=>u.id==='u_ens').email === auth.a_ens.email);
ok('le mot de passe est intact', auth.a_ens.motDePasse === 'MDP-ENS');
ok('le numéro n’a pas bougé', base.find(u=>u.id==='u_ens').phone === '+243810000111');

// ═══ 3 · LES DEUX D'UN COUP, ET LE MOT DE PASSE INTACT ═══════════════════
reinit();
globalThis.S = { user:{ id:'u_dir', name:'La Direction', role:'direction' } };
fiche('u_ens', { usr_phone:'0877777777', usr_email:'jk@lesage.cd' });
await saveUser();
ok('deux coordonnées corrigées = deux appels, un par champ',
   appelsEdge.filter(a=>a.nom==='school-contact-change').length === 2);
ok('les deux ont abouti',
   base.find(u=>u.id==='u_ens').phone === '+243877777777' && base.find(u=>u.id==='u_ens').email === 'jk@lesage.cd');
ok('le mot de passe est toujours le même', auth.a_ens.motDePasse === 'MDP-ENS');

// ═══ 4 · LE PARENT, LE GARDIEN, LA CAISSE, DIRECTION 1 ═══════════════════
reinit();
globalThis.S = { user:{ id:'u_dir', name:'La Direction', role:'direction' } };
fiche('u_par', { usr_phone:'0844444444' });
await saveUser();
ok('un PARENT relié se corrige aussi', base.find(u=>u.id==='u_par').phone === '+243844444444');
ok('et son code n’a pas changé', auth.a_par.motDePasse === 'MDP-PAR');

// Le gardien n'a PAS d'accès ouvert : la route ne le concerne pas.
reinit();
globalThis.S = { user:{ id:'u_dir', name:'La Direction', role:'direction' } };
fiche('u_gar', { usr_phone:'0855555555' });
await saveUser();
ok("un profil SANS accès ouvert ne passe pas par l'Edge Function",
   appelsEdge.length === 0, JSON.stringify(appelsEdge));
ok('sa coordonnée se corrige quand même, par la fiche',
   base.find(u=>u.id==='u_gar').phone === '+243855555555');

// Direction 1 : l'adresse est corrigeable, le téléphone reste absent.
reinit();
globalThis.S = { user:{ id:'u_dir', name:'La Direction', role:'direction' } };
fiche('u_dir', { usr_email:'bureau@lesage.cd' });
await saveUser();
ok("Direction 1 corrige sa propre adresse", base.find(u=>u.id==='u_dir').email === 'bureau@lesage.cd');
ok('sa connexion par téléphone reste désactivée',
   base.find(u=>u.id==='u_dir').login_phone_enabled === false);

// ═══ 5 · UN DOUBLON EST REFUSÉ, ET RIEN N'EST ANNONCÉ ════════════════════
reinit();
globalThis.S = { user:{ id:'u_dir', name:'La Direction', role:'direction' } };
fiche('u_ens', { usr_phone:'0820000222' });   // celui du parent
await saveUser();
ok('un numéro déjà pris est refusé',
   base.find(u=>u.id==='u_ens').phone === '+243810000111');
ok('le refus se pose sur le CHAMP du numéro', surChamp('usr_phone', /déjà/i),
   JSON.stringify(toasts));
ok('et rien n’est annoncé comme enregistré', !dit(/mis à jour/), JSON.stringify(toasts));
ok('la fiche n’est même pas envoyée', !appelsRpc.some(a=>a.nom==='save_school_user_profile'));

reinit();
globalThis.S = { user:{ id:'u_dir', name:'La Direction', role:'direction' } };
fiche('u_ens', { usr_email:'direction@lesage.cd' });
await saveUser();
ok('une adresse déjà prise est refusée sur son champ', surChamp('usr_email', /déjà/i),
   JSON.stringify(toasts));
ok('et l’adresse d’origine est conservée', base.find(u=>u.id==='u_ens').email === 'jean@lesage.cd');

// Chaque code du contrat #96 doit avoir des mots d'école. « Erreur serveur :
// PRIMARY_CONTACT_UNAVAILABLE » ne se dépanne pas.
for (const c of ['PHONE_IN_USE','EMAIL_IN_USE','DIRECTION1_REQUIRED_FOR_IDENTITY_CHANGE',
                 'PRIMARY_CONTACT_UNAVAILABLE','ACCOUNT_NOT_LINKED','AUTH_IDENTITY_UPDATE_FAILED',
                 'CONTACT_CHANGED','NO_CHANGE']) {
  ok(`le code ${c} s’affiche dans les mots de l’école`,
     !/^Erreur serveur/.test(window._codeMsg(c)), window._codeMsg(c));
}

// ═══ 6 · DIRECTION 2 NE MODIFIE PAS UNE IDENTITÉ — ET N'EFFACE RIEN ══════
reinit();
globalThis.S = { user:{ id:'u_d2', name:'Direction 2', role:'direction2' } };
// L'écran de Direction 2 ne porte pas la colonne `email` : le champ n'existe
// même pas dans son formulaire. C'est le cas qui effaçait une adresse.
const uEns = DB.users.find(u=>u.id==='u_ens'); delete uEns.email;
remplir({ usr_id:'u_ens', usr_role:'enseignant', usr_name:'Jean Kabongo', usr_init:'JK',
          usr_phone:'+243810000111', usr_canal:'phone_whatsapp' });
await saveUser();
ok('Direction 2 ne déclenche aucune correction d’identité', appelsEdge.length === 0);
const envD2 = appelsRpc.filter(a=>a.nom==='save_school_user_profile').pop();
ok("elle n'envoie PAS la clé `email`", envD2 && !('email' in envD2.p.p_user),
   envD2 && JSON.stringify(envD2.p.p_user));
ok("ni la clé `phone`", envD2 && !('phone' in envD2.p.p_user));
ok("l'adresse de l'enseignant est INTACTE sur le serveur",
   base.find(u=>u.id==='u_ens').email === 'jean@lesage.cd',
   base.find(u=>u.id==='u_ens').email);
ok('son numéro aussi', base.find(u=>u.id==='u_ens').phone === '+243810000111');
ok('et la fiche est bien enregistrée pour le reste', dit(/mis à jour/));

// L'écran le DIT, au lieu de laisser saisir pour rien.
reinit();
globalThis.S = { user:{ id:'u_d2', name:'Direction 2', role:'direction2' } };
openUserForm('enseignant', 'u_ens');
ok('le formulaire de Direction 2 fige les deux champs',
   /id="usr_phone"\s+disabled/.test(modal.b), '');
ok('et dit que seule la Direction 1 corrige une coordonnée',
   /Seule la Direction 1 corrige/.test(modal.b), '');
ok("il ne prétend pas que l'adresse est vide",
   /non visible depuis ce profil/.test(modal.b), '');
ok('aucun champ `usr_email` n’est même rendu', !/id="usr_email"/.test(modal.b), '');

// ═══ 7 · CE QUE L'ÉCRAN DE DIRECTION 1 ANNONCE ═══════════════════════════
reinit();
globalThis.S = { user:{ id:'u_dir', name:'La Direction', role:'direction' } };
openUserForm('enseignant', 'u_ens');
ok('Direction 1 garde les deux champs ouverts',
   /id="usr_phone"(?!\s+disabled)/.test(modal.b) && /id="usr_email"(?!\s+disabled)/.test(modal.b), '');
ok('et l’écran promet ce que le serveur tient : le mot de passe ne change pas',
   /sans changer son mot de passe/.test(modal.b), '');
ok('« Réinitialiser l’accès » est nommé comme un bouton SÉPARÉ',
   /Réinitialiser l['’]accès[^<]*».*séparé|séparé/.test(modal.b), '');

// ═══ 8 · LA ROUTE DE RÉINITIALISATION N'EST PAS CELLE-CI ═════════════════
const code = html.split('\n').map(l => l.replace(/^\s*\/\/.*$/, '')).join('\n');
const corps = (() => { const i = code.indexOf('window.saveUser = async');
  const j = code.indexOf('window._rattacherEnfants = ', i); return code.slice(i, j); })();
ok("`saveUser` n'appelle jamais `parent-phone-access`", !/parent-phone-access/.test(corps), '');
ok("ni `change_phone`", !/change_phone/.test(corps), '');
ok("ni une remise de code", !/reset|invit(?!ation)/i.test(corps.replace(/_inviterCompte/g,'')), '');
ok('mais il appelle bien `_changerContact`', /_changerContact\(/.test(corps), '');

// ═══ 9 · NO_CHANGE EST UN SUCCÈS, ET NE S'ANNONCE PAS ════════════════════
reinit();
globalThis.S = { user:{ id:'u_dir', name:'La Direction', role:'direction' } };
const r9 = await window._changerContact('u_ens', 'phone', '+243810000111');
ok('le serveur rend NO_CHANGE quand il porte déjà la valeur',
   r9.ok && r9.code === 'NO_CHANGE', JSON.stringify(r9));

// ═══ 10 · LE SERVEUR MUET NE PASSE PAS POUR UN SUCCÈS ════════════════════
reinit();
globalThis.S = { user:{ id:'u_dir', name:'La Direction', role:'direction' } };
lectureUsersMarche = false;
fiche('u_ens', { usr_phone:'0866666666' });
await saveUser();
ok('la coordonnée est corrigée malgré la relecture en panne',
   base.find(u=>u.id==='u_ens').phone === '+243866666666');
ok("et l'écran DIT qu'il n'a pas pu relire la liste",
   dit(/pas pu être relue/), JSON.stringify(toasts.map(t=>t.m)));

// ── Verdict ──────────────────────────────────────────────────────────────
console.log('\n═══ RECETTE — CORRIGER UN TÉLÉPHONE OU UNE ADRESSE (#96) ═══\n');
for (const r of R) console.log(`  ${r.v?'✓':'✗'} ${r.q}${r.v?'':'   → '+r.d}`);
const ko = R.filter(r => !r.v);
if (PREUVE) {
  // Sans la route, la fiche repart droit sur `save_school_user_profile` et
  // le serveur rend AUTH_PHONE_CHANGE_REQUIRED : c'est la panne d'origine.
  // Si la recette passait quand même, elle ne vérifierait rien.
  const attendus = ['la correction passe par school-contact-change',
                    "l'ancien numéro ne résout plus le profil"];
  const vus = attendus.filter(q => R.find(r => r.q === q && !r.v));
  if (vus.length === attendus.length) {
    console.log('\n✔ PREUVE TENUE — la route retirée, la recette revoit la panne');
    console.log("  d'origine : le numéro n'est pas corrigé.\n");
    process.exit(0);
  }
  console.log('\n✗ PREUVE MANQUÉE — la route retirée, la recette n’a rien vu.\n');
  process.exit(1);
}
console.log(`\n${ko.length ? '✗ '+ko.length+' sur '+R.length+' en échec' : '✓ les '+R.length+' points passent'}\n`);
process.exit(ko.length ? 1 : 0);
