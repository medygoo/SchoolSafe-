// ══════════════════════════════════════════════════════════════════════════
//  RECETTE — QUI A ENCAISSÉ (P0-1)
//
//  ChatGPT avait livré le champ : un déclencheur sur `payments` inscrit
//  `recorded_by`, `recorded_by_name`, `recorded_by_role` et les FIGE à la
//  mise à jour. Le navigateur lisait encore `by`, l'ancien champ que plus
//  rien ne renseigne — donc le résolveur rendait null et les dix-sept
//  documents qui l'appellent retombaient sur « Délivré par ».
//
//  Ce que cette recette garde, et qui est tout l'enjeu :
//  **un reçu réimprimé trois mois plus tard par la Direction doit porter le
//  nom de la CAISSIÈRE qui a encaissé devant la famille.**
//
//  `--preuve` remet le résolveur sur la personne connectée et vérifie que la
//  recette refuse.
// ══════════════════════════════════════════════════════════════════════════
import { readFileSync } from 'node:fs';

const CHEMIN = process.env.SS_HTML || new URL('../dist/index.html', import.meta.url);
let html = readFileSync(CHEMIN, 'utf8');
const PREUVE = process.argv.includes('--preuve');

// La panne d'avant : nommer la personne CONNECTÉE au lieu de l'auteur
// enregistré. C'est exactement ce qu'un reçu réimprimé ne doit pas faire.
if (PREUVE) {
  html = html.replace(
    "  if (x.recorded_by_name) {",
    "  if (false) {");
}

globalThis.window = globalThis;
globalThis.document = { getElementById:()=>null, querySelectorAll:()=>[], createElement:()=>({style:{}}) };
globalThis.S = { user:{ id:'u_dir', name:'Mme la Directrice', role:'direction' } };
globalThis.DB = { users:[
  { id:'u_cai', name:'Mireille Kabuya', role:'direction3' },
  { id:'u_dir', name:'Mme la Directrice', role:'direction' },
  { id:'u_cai2', name:'Josée Mbala', role:'direction3' },
], settings:{ school:{ name:'Complexe Scolaire Le Sage' } } };
globalThis.esc = (s)=>String(s==null?'':s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
globalThis.today = ()=>'2026-11-14';
globalThis._roleOfficiel = (r)=>({direction:'Direction Générale', direction3:'Caisse',
  direction2:'Direction Pédagogique', enseignant:'Enseignant'}[r] || r || '');

function extraire(a,b){ const i=html.indexOf(a); if(i<0) throw new Error(a); const j=html.indexOf(b,i); if(j<0) throw new Error(b); return html.slice(i,j); }
const resolveur = extraire('window._auteurLigne = (x) => {', '// Qui agit, et à quel titre');
const pied = extraire('function _officialFooter(name, role, auteur, beneficiaire){', '\n// Habillage permanent sombre');
new Function(resolveur + '\n' + pied + '\nglobalThis._officialFooter = _officialFooter;')();
globalThis._acteur = (u) => { const p=u||S.user||{}; const r=_roleOfficiel(p.role);
  return p.name ? (r?`${p.name} (${r})`:p.name) : '—'; };

const R=[]; const ok=(q,v,d)=>R.push({q,v:!!v,d});

// ── Le jeu d'essai : ce que le serveur a réellement écrit ────────────────
const encaisseParMireille = { t:'T1', paid:true, date:'2026-08-12',
  recorded_by:'u_cai', recorded_by_name:'Mireille Kabuya', recorded_by_role:'direction3',
  recorded_at:'2026-08-12T09:14:00Z' };
const encaisseParJosee = { t:'T2', paid:true, date:'2026-11-03',
  recorded_by:'u_cai2', recorded_by_name:'Josée Mbala', recorded_by_role:'direction3',
  recorded_at:'2026-11-03T11:02:00Z' };
const ancienneLigne = { t:'T3', paid:true, date:'2026-06-01', by:'u_cai' };  // avant le déclencheur
const nonPayee = { t:'T3', paid:false, date:null };

// ═══ 1 · LE CHAMP DU SERVEUR EST LU ══════════════════════════════════════
const a1 = _auteurLigne(encaisseParMireille);
ok('l’auteur vient du champ que le serveur a figé', a1 && a1.nom === 'Mireille Kabuya', a1 && a1.nom);
ok('son profil est traduit dans la langue de l’école', a1 && a1.role === 'Caisse', a1 && a1.role);

// ═══ 2 · LA RÉIMPRESSION NE CHANGE PAS L'AUTEUR ══════════════════════════
// C'est LE point de ce lot. La Direction rouvre le reçu trois mois plus tard.
S.user = { id:'u_dir', name:'Mme la Directrice', role:'direction' };
const auteur = _auteurDesLignes([encaisseParMireille]);
ok('le reçu nomme la caissière, pas la personne connectée',
   auteur && auteur.nom === 'Mireille Kabuya', auteur && auteur.nom);
ok('et la date est celle de l’ACTE, pas de l’impression',
   auteur && auteur.le === '2026-08-12', auteur && auteur.le);

const piedHtml = _officialFooter('Mme la Directrice', 'Direction Générale', auteur);
ok('le pied écrit « Établi par », pas « Délivré par »',
   /Établi par/.test(piedHtml) && !/Délivré par/.test(piedHtml), '');
ok('il imprime le nom de la caissière', /Mireille Kabuya/.test(piedHtml), '');
ok('et il ne fait pas signer la Direction deux fois',
   (piedHtml.match(/Mme la Directrice/g)||[]).length === 1, (piedHtml.match(/Mme la Directrice/g)||[]).length);

// Le même reçu réimprimé par la caissière elle-même
S.user = { id:'u_cai', name:'Mireille Kabuya', role:'direction3' };
const auteur2 = _auteurDesLignes([encaisseParMireille]);
ok('réimprimé par la caissière, le nom est IDENTIQUE',
   auteur2 && auteur2.nom === auteur.nom && auteur2.le === auteur.le, '');
S.user = { id:'u_dir', name:'Mme la Directrice', role:'direction' };

// ═══ 3 · DEUX CAISSIERS : ON NE NOMME PERSONNE ══════════════════════════
const deux = _auteurDesLignes([encaisseParMireille, encaisseParJosee]);
ok('deux caissiers différents → aucun nom au pied', deux === null, JSON.stringify(deux));
const piedDeux = _officialFooter('Mme la Directrice', 'Direction Générale', deux);
ok('et le pied retombe honnêtement sur « Délivré par »',
   /Délivré par/.test(piedDeux), '');
ok('sans inventer un auteur', !/Mireille/.test(piedDeux) && !/Josée/.test(piedDeux), '');

// ═══ 4 · LES LIGNES D'AVANT LE DÉCLENCHEUR ══════════════════════════════
const vieux = _auteurLigne(ancienneLigne);
ok('une ligne antérieure au déclencheur garde son auteur par `by`',
   vieux && vieux.nom === 'Mireille Kabuya', vieux && vieux.nom);
ok('on ne réécrit donc pas l’historique d’une école en service',
   _auteurDesLignes([ancienneLigne]) !== null, '');

// ═══ 5 · CE QU'ON NE SAIT PAS, ON NE L'INVENTE PAS ══════════════════════
ok('une ligne sans aucun auteur ne rend rien',
   _auteurLigne({ t:'T1', paid:true, date:'2026-01-01' }) === null, '');
ok('un seul trou dans le lot fait taire tout le pied',
   _auteurDesLignes([encaisseParMireille, { t:'T2', paid:true, date:'2026-01-01' }]) === null, '');
ok('une ligne NON payée ne compte pas',
   (_auteurDesLignes([encaisseParMireille, nonPayee])||{}).nom === 'Mireille Kabuya', '');
ok('aucune ligne payée du tout → aucun nom',
   _auteurDesLignes([nonPayee]) === null, '');

// ═══ 6 · LE CHAMP QUE J'AVAIS INVENTÉ ═══════════════════════════════════
// J'avais d'abord lu `paid_at`. Il n'existe pas dans public.payments — il
// aurait été lu à vide sans qu'aucune erreur ne le dise.
// Le contrôle regarde le CODE, jamais les commentaires : la note qui explique
// la correction ferait échouer le contrôle qui la vérifie. Troisième fois que
// ce piège se referme sur moi — un outil teste une condition, pas une chaîne.
const codeResolveur = resolveur.split('\n').map(l => l.replace(/^\s*\/\/.*$/, '')).join('\n');
ok('le code ne lit plus `paid_at`, qui n’existe pas',
   !/paid_at/.test(codeResolveur), '');
ok('il lit `recorded_at`, la vraie colonne',
   /recorded_at/.test(codeResolveur), '');

// ── Verdict ──────────────────────────────────────────────────────────────
console.log('\n═══ RECETTE — QUI A ENCAISSÉ ═══\n');
for (const r of R) console.log(`  ${r.v?'✓':'✗'} ${r.q}${r.v?'':'   → '+r.d}`);
const ko = R.filter(r=>!r.v);
if (PREUVE) {
  if (ko.length) {
    console.log(`\n✔ PREUVE TENUE — sans le champ du serveur, ${ko.length} point(s) tombent.`);
    console.log('  Dont : « ' + ko[0].q + ' »\n');
    process.exit(0);
  }
  console.log('\n✗ PREUVE MANQUÉE — la recette accepte un reçu qui nomme le mauvais auteur.\n');
  process.exit(1);
}
console.log(`\n${ko.length?'✗ '+ko.length+' sur '+R.length+' en échec':'✓ les '+R.length+' points passent'}\n`);
process.exit(ko.length?1:0);
