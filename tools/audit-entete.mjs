// ══════════════════════════════════════════════════════════════════════════
//  AUDIT — L'EN-TÊTE OFFICIEL DES DOCUMENTS
//
//  Un document scolaire congolais se lit de haut en bas comme une CHAÎNE DE
//  RESPONSABILITÉ : une administration qui le reçoit la remonte pour savoir à
//  qui s'adresser.
//
//              RÉPUBLIQUE DÉMOCRATIQUE DU CONGO
//     MINISTÈRE DE L'ÉDUCATION NATIONALE ET NOUVELLE CITOYENNETÉ
//        Province éducationnelle de …  ·  Sous-division de …
//
//  ── CE QUE LA MESURE A DONNÉ, LE 11 AOÛT 2026 ────────────────────────────
//  Sur les 47 producteurs de documents de l'application : **zéro** portait
//  « RÉPUBLIQUE », « Province éducationnelle », « Sous-division » ou le code
//  SERNIE. Trois seulement nommaient un ministère — **et c'était le mauvais**,
//  écrit en dur : « Ministère de l'EPSP » et « Ministère de l'ESU ».
//
//  L'EPSP a été remplacé par le Ministère de l'Éducation Nationale et Nouvelle
//  Citoyenneté. Une liste ENAFEP transmise au ministère en nommant un
//  ministère disparu se fait refuser au guichet, et personne dans l'école ne
//  peut savoir pourquoi.
//
//  Deux règles en sortent, et cet outil les tient :
//
//   1. **Le nom d'un ministère est un RÉGLAGE, jamais une constante.** Il a
//      déjà changé, il changera encore. En dur, il oblige à republier
//      l'application entière pour un changement qui ne la concerne pas.
//   2. **L'en-tête s'écrit une fois et s'appelle.** `_officialFooter` avait
//      échappé à toutes les reprises de charte précisément parce qu'il était
//      partagé et que personne ne le cherchait — un assistant partagé se
//      reprend par son NOM, pas par balayage.
//
//  Éprouvé dans les deux sens : `--preuve` remet un ministère en dur dans un
//  document et vérifie que l'outil le revoit.
// ══════════════════════════════════════════════════════════════════════════
import { readFileSync } from 'node:fs';

let html = readFileSync(process.env.SS_HTML || new URL('../dist/index.html', import.meta.url), 'utf8');
const PREUVE = process.argv.includes('--preuve');

if (PREUVE) {
  const avant = html;
  html = html.replace('      ${_enteteOfficiel()}\n      <h1>🎓 LISTE OFFICIELLE ENAFEP',
    '      <div style="font-size:11px">REPUBLIQUE DEMOCRATIQUE DU CONGO · Ministère de l\'EPSP</div>\n      <h1>🎓 LISTE OFFICIELLE ENAFEP');
  // Et le dessin : un document qui reprend sa feuille à lui.
  html = html.replace('  const CSS = window._CSS_DOC;',
    '  const CSS = `*{box-sizing:border-box}body{font-family:Arial}`;');
  if (html === avant) { console.log('\n✗ PREUVE IMPOSSIBLE — le point à réinjecter est introuvable.\n'); process.exit(1); }
}

// Un contrôle « absence de X » qui balaie le fichier entier échouerait sur le
// commentaire qui explique le retrait de X. Ce piège s'est refermé trois fois
// dans ce dépôt. Un outil teste une condition, jamais une chaîne.
const code = html
  .split('\n').map(l => l.replace(/^\s*\/\/.*$/, '')).join('\n')
  .replace(/<!--[\s\S]*?-->/g, '')
  // ⚠️ Le `/*` doit être en DÉBUT DE LIGNE. Sans cette ancre, `accept="image/*"`
  // — un attribut HTML parfaitement normal — ouvre un faux commentaire CSS que
  // le premier `*/` venu referme : mesuré, **351 Ko avalés d'un coup**, dont la
  // seule ligne qui emploie `jsQR`. L'outil déclarait alors « bibliothèque
  // téléchargée sans être appelée » sur une bibliothèque parfaitement utilisée.
  // Un nettoyeur qui ne comprend pas le contexte n'omet pas : il INVENTE.
  .replace(/^[ \t]*\/\*[\s\S]*?\*\//gm, '');
const lignes = code.split('\n');

const R = []; const ok = (q, v, d = '') => R.push({ q, v: !!v, d });

// ── 1 · AUCUN MINISTÈRE ÉCRIT EN DUR ──────────────────────────────────────
// La bonne question n'est pas « le nom est-il correct ? » — il ne le restera
// pas — mais « peut-il seulement être corrigé sans republier l'application ? »
const MINISTERE_DUR = /Minist[èe]re\s+de\s+l['’]\s*(EPSP|ESU|EPST)\b/gi;
const dursMin = [];
lignes.forEach((l, i) => { if (MINISTERE_DUR.test(l)) dursMin.push(i + 1); MINISTERE_DUR.lastIndex = 0; });
ok('aucun ministère n’est écrit en dur — il se règle, il ne se recompile pas',
   dursMin.length === 0, 'ligne(s) ' + dursMin.join(', '));

// ── 2 · LE MINISTÈRE EST BIEN UN RÉGLAGE, SAISISSABLE ET LU ───────────────
ok('le ministère a un champ de saisie', /id="cfg_school_ministere"/.test(code));
ok('et il est ENREGISTRÉ — un champ qu’on remplit sans le sauver ne sert à rien',
   /school\.ministere\s*=/.test(code));
ok('et il est LU par l’en-tête — sinon c’est un champ mort',
   /sc\.ministere/.test(code));

// La même question pour les trois autres maillons de la chaîne.
for (const [nom, champ, lu] of [
  ['la province éducationnelle', 'cfg_school_province', 'sc.province'],
  ['la sous-division',           'cfg_school_sub',      'sc.sub'],
  ['le code école (SERNIE)',     'cfg_school_code',     'sc.code_ecole'],
]) {
  ok(`${nom} se saisit, s’enregistre et se lit`,
     code.includes(`id="${champ}"`) && new RegExp(champ.replace('cfg_school_', 'school\\.').replace(/^school\\\.code$/, 'school\\.code_ecole')).test(code.replace('cfg_school_code', 'school.code_ecole')) && code.includes(lu),
     `${champ} / ${lu}`);
}

// ── 3 · `sc.sub` N'EST PLUS UN CHAMP MORT ─────────────────────────────────
// Il était LU quinze fois et écrit nulle part : la ligne ne s'affichait donc
// jamais, et personne ne s'en apercevait puisqu'elle était conditionnelle.
const lecturesSub = (code.match(/sc\.sub\b/g) || []).length;
ok('`sc.sub` est lu ET écrit — avant, il était lu 15 fois et écrit nulle part',
   lecturesSub > 0 && /school\.sub\s*=/.test(code),
   lecturesSub + ' lecture(s), écriture ' + (/school\.sub\s*=/.test(code) ? 'présente' : 'ABSENTE'));

// ── 4 · L'EN-TÊTE PARTAGÉ EXISTE ET NE MENT PAS ───────────────────────────
const bloc = code.slice(code.indexOf('window._enteteOfficiel'), code.indexOf('window._roleOfficiel'));
ok('l’en-tête officiel est écrit UNE fois et s’appelle',
   /window\._enteteOfficiel\s*=/.test(code));
ok('il porte l’emblème de l’école', /_logoDoc\(/.test(bloc));
ok('une ligne dont la valeur manque ne s’imprime PAS',
   /const ligne\s*=\s*\(t[^)]*\)\s*=>\s*t\s*\?/.test(bloc),
   'un renseignement inventé sur un document officiel est pire que son absence');
ok('et si toute la tutelle manque, aucun bloc vide ne se pose',
   /const vide\s*=/.test(bloc) && /\$\{vide \? '' :/.test(bloc));
ok('le pays vient des réglages, pas d’une constante',
   /sc\.country/.test(bloc),
   'SchoolSafe est livré à une école congolaise, il n’est pas un logiciel congolais');

// ── 5 · LES DOCUMENTS ADRESSÉS À L'EXTÉRIEUR LE PORTENT ───────────────────
// On ne l'exige que des documents qui SORTENT vers une administration. Un
// bulletin ou un reçu portent déjà leur propre en-tête d'école ; les y forcer
// serait la faute symétrique — imposer partout ce qui vaut quelque part.
const VERS_MINISTERE = ['printTenafepList', 'printExetatList', 'printRapportSecope'];
for (const fn of VERS_MINISTERE) {
  const i = code.indexOf('function ' + fn) >= 0 ? code.indexOf('function ' + fn) : code.indexOf(fn + ' =');
  const bout = i >= 0 ? code.slice(i, i + 9000) : '';
  ok(`${fn} porte la chaîne de responsabilité`,
     /_enteteOfficiel\(/.test(bout), i < 0 ? 'fonction introuvable' : 'en-tête absent');
}

// ── 6 · UN SEUL DESSIN POUR LA FINANCE ET LA RH ───────────────────────────
// Loms, 11 août 2026 : « que tous les documents qui proviennent de cette partie
// prennent le même design ». La référence est le reçu de ChatGPT.
//
// Il y avait DIX feuilles de style écrites à la main, une par document : deux
// papiers sortis de la même caisse le même jour ne se ressemblaient pas. C'est
// la leçon des neuf copies du classement, appliquée au dessin — quand dix
// endroits répondent à la même question, ils appellent le même code.
const FINANCE_RH = ['exportEtatFinancierPDF','exportJournalPDF','exportBalancePDF',
  'exportGrandLivrePDF','exportComptabilitePDF','exportBilanPDF',
  'printFichePaie','printPersonnelFichePaie','printVersementRecu','viewReceipt'];

ok('la feuille commune des documents existe', /window\._CSS_DOC\s*=/.test(code));
ok('elle parle la langue du reçu — bandeau, badge, cartouche, cachet',
   /\.amount-box/.test(code) && /\.stamp/.test(code) && /\.badge/.test(code) && /#556777/.test(code));
ok('l’en-tête de tableau se répète en haut de chaque page',
   /thead\{display:table-header-group\}/.test(code),
   'sinon une colonne de comptes devient illisible dès la deuxième page');
ok('la barre d’action ne s’imprime jamais',
   /\.pbtn,\.dl-btn,\.print-bar,\.dl-bar\{display:none\}/.test(code),
   'elle n’appartient pas au document');
ok('la comptabilité DÉRIVE de la feuille commune au lieu d’en écrire une autre',
   /_COMPTA_CSS\s*=\s*window\._CSS_DOC\s*\+/.test(code));

// La tranche s'arrête à la DÉCLARATION SUIVANTE au premier niveau, pas au
// prochain document de la liste : entre deux documents de Finance il y a
// parfois des milliers de lignes, et la feuille d'un voisin serait comptée
// comme celle qu'on examine. Une tranche trop large ne trouve pas moins —
// elle attribue à tort.
const _finDe = (i) => {
  const m = /\n(?:window\.[A-Za-z_0-9.]+\s*=|function\s+[A-Za-z_0-9]+|R\.[a-z_0-9]+\s*=|const\s+[A-Z_]+\s*=)/.exec(code.slice(i + 40));
  return m ? i + 40 + m.index : Math.min(i + 20000, code.length);
};
const solitaires = [];
FINANCE_RH.map(n => [n, code.indexOf('window.' + n + ' =')])
  .filter(([, i]) => i >= 0)
  .forEach(([n, i]) => {
  const bout = code.slice(i, _finDe(i));
  const partagee = /_CSS_DOC|_COMPTA_CSS/.test(bout);
  // Une feuille écrite à la main se reconnaît à ses règles, pas à sa longueur.
  const propre = /const CSS\s*=\s*`|<style>\s*\*\{/.test(bout);
  if (!partagee || propre) solitaires.push(n + (propre ? ' (feuille propre)' : ' (aucune feuille)'));
});
ok('les 10 documents de Finance et RH partagent le MÊME dessin',
   solitaires.length === 0, solitaires.join(', '));

// ── Verdict ───────────────────────────────────────────────────────────────
console.log('\n═══ AUDIT — L’EN-TÊTE OFFICIEL ET LE DESSIN DES DOCUMENTS ═══\n');
for (const r of R) console.log(`  ${r.v ? '✓' : '✗'} ${r.q}${r.v ? '' : '   → ' + r.d}`);

console.log('\n  CE QUE CET OUTIL NE VÉRIFIE PAS, et il faut le savoir :');
console.log('    · que les valeurs saisies par la Direction soient les BONNES —');
console.log('      un code école faux passe ici sans un mot ;');
console.log('    · les 44 autres documents, qui portent l’en-tête de l’école mais');
console.log('      pas la chaîne ministérielle. C’est un choix, pas un oubli :');
console.log('      un reçu de cantine ne s’adresse à aucune administration.');
console.log('    · les deux mentions du « Ministère de l’ESU » qui restent dans du');
console.log('      TEXTE D’ÉCRAN (résultats EXETAT). Signalé à Loms, pas corrigé :');
console.log('      je ne connais pas le nom actuel de ce ministère-là.');

const ko = R.filter(r => !r.v);
if (PREUVE) {
  const dur = R.find(r => /aucun ministère n’est écrit en dur/.test(r.q));
  const doc = R.find(r => /printTenafepList porte la chaîne/.test(r.q));
  const des = R.find(r => /partagent le MÊME dessin/.test(r.q));
  if (dur && !dur.v && doc && !doc.v && des && !des.v) {
    console.log('\n✔ PREUVE TENUE — un ministère remis en dur est revu, le document');
    console.log('  qui perd son en-tête aussi, et celui qui reprend sa propre feuille.\n');
    process.exit(0);
  }
  console.log('\n✗ PREUVE MANQUÉE — le ministère en dur est repassé sans être vu.\n');
  process.exit(1);
}
console.log(`\n${ko.length ? '✗ ' + ko.length + ' sur ' + R.length + ' en échec'
                           : '✓ les ' + R.length + ' points passent'}\n`);
process.exit(ko.length ? 1 : 0);
