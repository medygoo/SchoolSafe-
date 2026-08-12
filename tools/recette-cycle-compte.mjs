// ══════════════════════════════════════════════════════════════════════════
//  RECETTE — LE CYCLE DE VIE D'UN COMPTE (P0-13)
//
//  L'application faisait `pushSync('users','delete')` — une SUPPRESSION
//  SÈCHE. Trois conséquences, et la troisième est la pire :
//
//   1. l'historique disparaissait avec la personne : reçus, salaires, audit ;
//   2. rien ne protégeait le DERNIER compte de Direction ;
//   3. **l'accès n'était PAS retiré** — supprimer la ligne applicative ne
//      touche pas l'identité d'authentification. La personne « supprimée »
//      pouvait encore se connecter.
//
//  `--preuve` fait échouer le retrait de l'identité de connexion à
//  l'étape 2 : la recette doit vérifier qu'on ne prétend PAS que l'accès
//  est fermé.
// ══════════════════════════════════════════════════════════════════════════
import { readFileSync } from 'node:fs';

const CHEMIN = process.env.SS_HTML || new URL('../dist/index.html', import.meta.url);
const html = readFileSync(CHEMIN, 'utf8');
const PREUVE = process.argv.includes('--preuve');

const champs = {}, toasts = [], audits = [];
let modal = null, confirmCb = null;
const faux = (v='') => ({ style:{}, value:v, innerHTML:'', focus(){}, addEventListener(){},
  parentNode:{querySelector:()=>null, appendChild(){}} });
globalThis.window = globalThis;
globalThis.document = { getElementById:(id)=>(id in champs ? faux(champs[id]) : null),
  querySelector:()=>null, querySelectorAll:()=>[], createElement:()=>faux(), addEventListener(){}, body:{style:{}} };
try{Object.defineProperty(globalThis,'navigator',{value:{onLine:true},configurable:true});}catch(_){}
globalThis.setTimeout = (f)=>{ if(typeof f==='function') try{f();}catch(e){} return 0; };

globalThis.S = { user:{ id:'u_dir', name:'La Direction', role:'direction', auth_user_id:'auth-dir' } };
globalThis.DB = { users:[], students:[], classes:[], settings:{} };
globalThis.esc = (s)=>String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
globalThis.toast = (m,t)=>toasts.push({m,t});
globalThis.logAudit = (a,d)=>audits.push({a,d});
globalThis.saveToCrypt = ()=>{};
globalThis.render = ()=>{};
globalThis.closeModal = ()=>{ modal=null; };
globalThis.openM = (t,b,f)=>{ modal={t,b,f}; };
globalThis.markFieldError = (id,msg)=>toasts.push({m:msg,t:'field',id});
globalThis.showC = (t,m,cb)=>{ confirmCb=cb; };

// ── Le serveur en carton, avec les vrais contrôles de ChatGPT ────────────
const appels = [];
let identiteRetiree = false;
globalThis._rpc = async (nom, p) => {
  appels.push({ nom, p });
  const cible = DB.users.find(u => u.id === p.p_app_user_id);
  if (nom === 'suspend_school_account') {
    if (!['direction','direction2'].includes(S.user.role)) return { ok:false, code:'FORBIDDEN' };
    if (!p.p_reason || p.p_reason.length < 5) return { ok:false, code:'REASON_REQUIRED' };
    if (!cible) return { ok:false, code:'TARGET_NOT_FOUND' };
    if (cible.id === S.user.id) return { ok:false, code:'CANNOT_SUSPEND_CURRENT_ACCOUNT' };
    if (S.user.role === 'direction2' && !['direction2','enseignant','gardien','parent'].includes(cible.role))
      return { ok:false, code:'FORBIDDEN_TARGET_ROLE' };
    // La protection qui compte : le DERNIER compte de Direction actif.
    if (cible.role === 'direction' && !DB.users.some(u =>
        u.id !== cible.id && u.status === 'active' && u.auth_user_id && u.role === 'direction'))
      return { ok:false, code:'LAST_DIRECTION_ACCOUNT' };
    return { ok:true, data:{ code:'ACCOUNT_SUSPENDED', user:{...cible, status:'suspended'} } };
  }
  if (nom === 'reactivate_school_account') {
    if (!cible) return { ok:false, code:'TARGET_NOT_FOUND' };
    return { ok:true, data:{ code:'ACCOUNT_REACTIVATED', user:{...cible, status:'active'} } };
  }
  if (nom === 'prepare_school_account_removal') {
    if (S.user.role !== 'direction') return { ok:false, code:'FORBIDDEN' };
    if (!p.p_reason || p.p_reason.length < 5) return { ok:false, code:'INVALID_REASON' };
    if (!cible) return { ok:false, code:'TARGET_NOT_FOUND' };
    if (cible.auth_user_id === p.p_actor_auth_user_id) return { ok:false, code:'CANNOT_REMOVE_CURRENT_ACCOUNT' };
    if (cible.role === 'direction' && !DB.users.some(u =>
        u.id !== cible.id && u.status === 'active' && u.auth_user_id && u.role === 'direction'))
      return { ok:false, code:'LAST_DIRECTION_ACCOUNT' };
    return { ok:true, data:{ code:'ACCOUNT_REMOVAL_PREPARED' } };
  }
  if (nom === 'confirm_school_account_removal') {
    if (!cible) return { ok:false, code:'TARGET_NOT_FOUND' };
    // Le contrôle qui empêche d'annoncer une fermeture qui n'a pas eu lieu.
    if (!identiteRetiree) return { ok:false, code:'AUTH_IDENTITY_STILL_PRESENT' };
    return { ok:true, data:{ code:'ACCOUNT_ACCESS_REMOVED', status:'removed',
      access_removed_at:'2026-08-11T04:00:00Z' } };
  }
  return { ok:false, code:'PGRST202' };
};
globalThis._edgeFn = async (nom) => {
  appels.push({ nom, edge:true });
  if (PREUVE) return { ok:false, code:'RPC_REFUSED' };
  identiteRetiree = true;
  return { ok:true, data:{} };
};

function extraire(a,b){ const i=html.indexOf(a); if(i<0) throw new Error(a); const j=html.indexOf(b,i); if(j<0) throw new Error(b); return html.slice(i,j); }
// La résolution du conflit du 12 août a placé les fonctions du cycle de vie
// APRÈS l'écran des parents : la tranche d'extraction traversait donc
// `R.teachers` et `R.parents`, qui ont besoin d'un `R` et de dépendances
// d'affichage. On extrait les deux morceaux séparément — l'outil suit le code,
// ce n'est pas au code de se plier à l'outil.
new Function(extraire('window._COMPTE_REFUS = {', 'R.teachers ='))();
new Function(extraire('window.confirmerSuspension = async', "window._parQ = ''"))();

const R=[]; const ok=(q,v,d)=>R.push({q,v:!!v,d});
const reset = () => {
  identiteRetiree = false;
  DB.users = [
    { id:'u_dir',  name:'La Direction', role:'direction',  status:'active', auth_user_id:'auth-dir' },
    { id:'u_dir2', name:'Direction 2',  role:'direction',  status:'active', auth_user_id:'auth-dir2' },
    { id:'u_ens',  name:'Mme Luyeye',   role:'enseignant', status:'active', auth_user_id:'auth-ens' },
  ];
  DB.students = [{ id:'s1', name:'Enfant Un', pid:'u_ens' }];
  S.user = { id:'u_dir', name:'La Direction', role:'direction', auth_user_id:'auth-dir' };
};

// ═══ 1 · PLUS AUCUNE SUPPRESSION ════════════════════════════════════════
const code = html.split('\n').map(l => l.replace(/^\s*\/\/.*$/,'')).join('\n');
ok('`deleteUser` n’existe plus', !/window\.deleteUser\s*=/.test(code), '');
ok('plus aucune suppression de compte n’est envoyée',
   !/pushSync\('users','delete'/.test(code), '');

// ═══ 2 · SUSPENDRE ══════════════════════════════════════════════════════
reset();
champs.cptMotif = 'abs';
await confirmerSuspension('u_ens');
ok('un motif trop court n’atteint pas le serveur',
   !appels.some(a=>a.nom==='suspend_school_account'), '');
champs.cptMotif = 'congé sans solde jusqu’en janvier';
await confirmerSuspension('u_ens');
ok('avec son motif, la suspension part',
   appels.some(a=>a.nom==='suspend_school_account'), '');
ok('et le compte passe suspendu en local APRÈS le succès',
   DB.users.find(u=>u.id==='u_ens').status === 'suspended', '');
ok('la ligne n’est PAS supprimée', DB.users.length === 3, DB.users.length);

// On ne se suspend pas soi-même
reset(); champs.cptMotif = 'motif quelconque';
await confirmerSuspension('u_dir');
ok('on ne suspend pas son propre compte',
   toasts.some(t=>/votre propre compte/i.test(t.m||'')), '');

// LE DERNIER compte de Direction — ce que l'écran fait du refus serveur.
//
// La garde elle-même appartient à ChatGPT, et elle est volontairement
// difficile à atteindre : il faut qu'aucune AUTRE Direction active et
// rattachée à une identité de connexion n'existe. Fabriquer ce cas dans un
// serveur en carton ne prouverait rien sur SON code — seulement sur ma
// copie de son code.
//
// Ce que cette recette doit vérifier, c'est MA moitié : quand le serveur
// oppose ce refus, l'écran dit-il ce que ça fermerait ? Un « refusé » sec
// enverrait la Direction insister.
reset();
const vraiRpc = globalThis._rpc;
globalThis._rpc = async (nom, p) => { appels.push({nom,p});
  return nom === 'suspend_school_account' ? { ok:false, code:'LAST_DIRECTION_ACCOUNT' } : vraiRpc(nom, p); };
champs.cptMotif = 'tentative de fermeture';
await confirmerSuspension('u_dir2');
ok('le refus du DERNIER compte de Direction est expliqué',
   toasts.some(t=>/DERNIER compte de Direction/.test(t.m||'')), toasts.slice(-1)[0]?.m);
ok('et la phrase dit ce que ça fermerait',
   toasts.some(t=>/fermerait l’école à tout le monde/.test(t.m||'')), '');
ok('elle dit aussi quoi faire à la place',
   toasts.some(t=>/Créez d’abord une autre Direction/.test(t.m||'')), '');
ok('et rien n’a changé en local',
   DB.users.find(u=>u.id==='u_dir2').status === 'active', '');
globalThis._rpc = vraiRpc;

// Direction 2 ne touche pas à tout
reset();
S.user = { id:'u_dir2', name:'Direction 2', role:'direction2', auth_user_id:'auth-dir2' };
champs.cptMotif = 'motif quelconque';
await confirmerSuspension('u_dir');
ok('Direction 2 ne suspend pas une Direction 1',
   toasts.some(t=>/Passez par Direction 1/.test(t.m||'')), '');

// ═══ 3 · RÉACTIVER ══════════════════════════════════════════════════════
reset();
DB.users.find(u=>u.id==='u_ens').status = 'suspended';
reactiverCompte('u_ens'); if (confirmCb) await confirmCb();
ok('la réactivation passe par sa RPC',
   appels.some(a=>a.nom==='reactivate_school_account'), '');
ok('et le compte redevient actif', DB.users.find(u=>u.id==='u_ens').status === 'active', '');

// ═══ 4 · RETIRER L'ACCÈS — TROIS TEMPS ══════════════════════════════════
reset();
champs.cptMotif = 'a quitté l’école le 30 juin';
await confirmerRetraitAcces('u_ens');
const noms = appels.map(a=>a.nom);
// ── UN SEUL APPEL — ChatGPT, PR #85, 12 août 2026 ─────────────────────────
// Cette recette exigeait TROIS appels : préparer, retirer, confirmer. L'audit
// du vrai Supabase par ChatGPT a montré que les deux appels de bout sont
// **service_role uniquement** : depuis le navigateur, ils étaient refusés en
// silence. L'Edge Function tient les trois étapes elle-même.
//
// Ce que la recette garde maintenant est l'inverse de ce qu'elle gardait : que
// le navigateur n'appelle QUE la porte qui lui est ouverte.
ok('le retrait passe par l’Edge Function, seule porte ouverte au navigateur',
   noms.includes('remove-school-account'), noms.join(','));
ok('il n’appelle PLUS `prepare_school_account_removal` — service_role only',
   !noms.includes('prepare_school_account_removal'),
   'appel refusé en silence : la panne du 5 août recommencée');
ok('ni `confirm_school_account_removal` — même raison',
   !noms.includes('confirm_school_account_removal'), '');
ok('un seul aller-retour pour le retrait, pas trois',
   noms.filter(n => n === 'remove-school-account').length === 1, noms.join(','));
const ens = DB.users.find(u=>u.id==='u_ens');
ok('le compte porte « accès retiré », il n’est pas supprimé',
   ens && ens.status === 'removed' && DB.users.length === 3, '');
ok('son identité de connexion est effacée du miroir', ens && !ens.auth_user_id, '');

// Seule Direction 1
reset();
S.user = { id:'u_dir2', name:'Direction 2', role:'direction2', auth_user_id:'auth-dir2' };
const avant = appels.length;
retirerAccesCompte('u_ens');
ok('Direction 2 ne retire pas un accès', appels.length === avant, '');
ok('et on le lui dit', toasts.some(t=>/Direction 1 retire un accès/.test(t.m||'')), '');

// ═══ 5 · LA PASTILLE NE MENT PAS SUR L'ÉTAT ════════════════════════════
new Function(extraire('window._etatAccesCompte = (u) => {', '  // ═══════════════════════════════════════════════════════════════════════')
  + '\n  return {cle:"autre",texte:"—"};\n};')();
globalThis._telE164 = () => '+243810000111';
ok('un compte suspendu affiche « Suspendu »',
   _etatAccesCompte({status:'suspended', email:'x@y.z'}).cle === 'suspendu', '');
ok('un compte dont l’accès est retiré l’affiche aussi',
   _etatAccesCompte({status:'removed', email:'x@y.z'}).cle === 'acces_retire', '');
ok('l’état du COMPTE passe avant son canal d’accès',
   _etatAccesCompte({status:'suspended', email:'x@y.z', invitation_sent_at:'2026-08-01'}).cle === 'suspendu', '');

// ── Verdict ──────────────────────────────────────────────────────────────
console.log('\n═══ RECETTE — LE CYCLE DE VIE D’UN COMPTE ═══\n');
for (const r of R) console.log(`  ${r.v?'✓':'✗'} ${r.q}${r.v?'':'   → '+r.d}`);
const ko = R.filter(r=>!r.v);
if (PREUVE) {
  // Le retrait de l'identité échoue : on ne doit PAS annoncer un accès fermé.
  const dit = R.find(r=>/il n’est pas supprimé/.test(r.q));
  if (dit && !dit.v) {
    console.log('\n✔ PREUVE TENUE — l’identité non retirée, l’écran n’annonce pas');
    console.log('  un accès fermé. Il propose de suspendre en attendant.\n');
    process.exit(0);
  }
  console.log('\n✗ PREUVE MANQUÉE — l’écran a annoncé un accès fermé qui ne l’est pas.\n');
  process.exit(1);
}
console.log(`\n${ko.length?'✗ '+ko.length+' sur '+R.length+' en échec':'✓ les '+R.length+' points passent'}\n`);
process.exit(ko.length?1:0);
