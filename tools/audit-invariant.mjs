// ══════════════════════════════════════════════════════════════════════════
//  audit-invariant.mjs — l'invariant qui rend les gardes `|| []` inutiles
//
//  Remplace audit-nullgard.mjs, qui signalait 498 accès « non gardés » à
//  DB.<table> dont aucun n'était un défaut. La bonne question n'est pas
//  « chaque accès porte-t-il son `|| []` ? » mais :
//
//      DB.<table> peut-il seulement être autre chose qu'un tableau ?
//
//  Il ne le peut pas, à trois conditions que ce fichier vérifie :
//
//    1. Toute table lue est déclarée dans `window.DB = { … }`, donc
//       initialisée à [] au chargement du script.
//    2. `loadFromCrypt` FUSIONNE les clés du cache dans DB au lieu de le
//       remplacer — une table ajoutée depuis l'écriture du cache garde son [].
//    3. `safe()` de `loadFromSupabase` renvoie toujours un tableau : la
//       réponse si elle en est un, sinon la valeur précédente, sinon [].
//
//  Un `DB.machin` lu sans être déclaré casse l'invariant et fait planter
//  l'écran. C'est ainsi qu'a été trouvé `DB.exit_scans` : lu sur la fiche
//  élève, écrit nulle part, table inexistante — la fiche d'un enfant déjà
//  sorti affichait encore son heure d'arrivée.
//
//  Usage : node tools/audit-invariant.mjs
// ══════════════════════════════════════════════════════════════════════════
import fs from 'fs';

// Ne retirer QUE les lignes entièrement commentées : les commentaires citent
// des noms de tables en prose. Un `/* … */` glouton, lui, avale les littéraux
// d'expression régulière et les divisions — la mesure tombait de 49 tables
// écrites à 26 sans qu'une ligne de code ait changé.
const src = fs.readFileSync(new URL('../dist/index.html', import.meta.url), 'utf8')
  .replace(/^[ \t]*\/\/.*$/gm, ' ');

const init = /window\.DB\s*=\s*\{([\s\S]*?)\n\};/.exec(src);
if (!init) { console.error('window.DB introuvable — la forme du fichier a changé'); process.exit(2); }

// Les clés de premier niveau seulement. On coupe à `settings:`, qui ouvre un
// sous-objet (school, horaires, toggles…) dont les clés ne sont pas des
// tables. Plusieurs tables tiennent sur une même ligne : compter par ligne
// n'en voyait que 15 sur 49.
const declarees = new Set();
const avantSettings = init[1].split(/\n\s*settings\s*:/)[0];
for (const m of avantSettings.matchAll(/([a-z_0-9]+)\s*:/gi)) declarees.add(m[1]);

const lues = new Set();
for (const m of src.matchAll(/\bDB\.([a-z_][a-z_0-9]*)\b/g)) lues.add(m[1]);

const ecrites = new Set();
for (const m of src.matchAll(/pushSync\(\s*'([a-z_0-9]+)'/g)) ecrites.add(m[1]);

const interne = new Set(['settings', '_idx']);
const garde = t => !interne.has(t) && !t.startsWith('_');

const luesNonDeclarees = [...lues].filter(t => garde(t) && !declarees.has(t));

// Une table écrite sans miroir local est légitime si rien ne la relit :
// `push_subscriptions` s'enregistre au serveur et ne se consulte jamais ici.
const ecritesSansMiroir = [...ecrites].filter(t => garde(t) && !declarees.has(t) && !lues.has(t));
const ecritesNonDeclarees = [...ecrites].filter(t => garde(t) && !declarees.has(t) && lues.has(t));

// Conditions 2 et 3 : les deux chemins de chargement préservent-ils les clés ?
const fusionCache = /Object\.keys\(d\)\.forEach\(k =>[^\n]*Array\.isArray\(d\[k\]\)\)\s*DB\[k\]/.test(src);
const safeToujoursTableau = /const safe = \(r, cur\) => \{[\s\S]{0,200}?Array\.isArray\(cur\) \? cur : \[\]/.test(src);

console.log('═══ INVARIANT : DB.<table> est toujours un tableau ═══\n');
console.log(`  ${declarees.size} tables déclarées · ${lues.size} lues · ${ecrites.size} écrites\n`);

let ko = 0;
const ligne = (ok, txt, detail) => {
  console.log(`  ${ok ? '✓' : '✗'} ${txt}${detail ? ' — ' + detail : ''}`);
  if (!ok) ko++;
};

ligne(luesNonDeclarees.length === 0,
  'toute table lue est déclarée',
  luesNonDeclarees.length ? luesNonDeclarees.join(', ') + ' : undefined au démarrage' : '');
ligne(ecritesNonDeclarees.length === 0,
  'toute table écrite ET relue a son miroir local',
  ecritesNonDeclarees.join(', '));
ligne(fusionCache, 'loadFromCrypt fusionne les clés au lieu de remplacer DB');
ligne(safeToujoursTableau, 'safe() de loadFromSupabase renvoie toujours un tableau');

if (ecritesSansMiroir.length) {
  console.log(`\n  · écrites sans miroir local, jamais relues (normal) : ${ecritesSansMiroir.join(', ')}`);
}

console.log(ko
  ? `\n✗ ${ko} condition(s) rompue(s) — les gardes \`|| []\` ne suffiront pas à rattraper`
  : '\n✓ Invariant tenu : aucun accès à DB.<table> ne peut être indéfini');
process.exit(ko ? 1 : 0);
