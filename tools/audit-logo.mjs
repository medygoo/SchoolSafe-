// ══════════════════════════════════════════════════════════════════════════
//  audit-logo.mjs — l'emblème de l'école sur les documents officiels
//
//  Un document qui engage l'école porte son emblème. Sans lui, un bulletin,
//  une fiche de paie ou une liste ENAFEP n'est qu'une feuille imprimée : elle
//  ne prouve rien et une administration peut la refuser.
//
//  Onze documents sur trente-sept en sortaient dépourvus — les deux fiches de
//  paie, les listes ENAFEP et EXÉTAT, la fiche de santé, le kit d'urgence, le
//  rapport SECOPE, le palmarès annuel, le rapport mensuel, le reçu de
//  paiement. Aucun n'était signalé : rien ne le vérifiait.
//
//  L'outil repère chaque appel à `dlPDF`, remonte à la fonction qui le
//  contient, et y cherche `_logoImg` ou `SCHOOL_LOGO`.
//
//  Usage : node tools/audit-logo.mjs
// ══════════════════════════════════════════════════════════════════════════
import fs from 'fs';

const src = fs.readFileSync(new URL('../dist/index.html', import.meta.url), 'utf8');
const lignes = src.split('\n');

// `dlPDF` est l'assistant d'impression lui-même, pas un document.
//
// Les fonctions d'impression de CARTES n'ont pas à poser d'emblème : elles
// écrivent la carte déjà construite par `ssBuildBadge` / `ssBuildCarte`, qui
// la porte. Leur en ajouter un second le ferait paraître deux fois.
const ASSISTANTS = new Set(['dlPDF',
  'ssPrintCard', 'exportSSAllCardsZip', 'printClassCards',
  'generateDuplicata', 'imprimerCarte']);

// Un document sort de trois manières : `dlPDF`, une fenêtre d'impression
// (`w.document.write` — le nom de la variable varie), ou un Blob PDF
// téléchargé. N'en guetter qu'une en laissait passer trois.
const sorties = [];
lignes.forEach((l, i) => {
  const parPDF   = /dlPDF\(\s*[A-Za-z_`]/.test(l);
  const parFen   = /\b\w+\.document\.write\(/.test(l);
  // Tout téléchargement est une sortie : le nom du fichier est parfois une
  // variable, et exiger une extension littérale manquait des documents
  // entiers. En revanche un Blob issu d'un PDF DÉJÀ stocké est un renvoi de
  // fichier, pas un document composé : il ne peut porter aucun emblème.
  // Un téléchargement n'est un DOCUMENT que si le fichier est une page — HTML
  // ou PDF composé. Un export CSV, une sauvegarde JSON, un PNG de carte sont
  // des fichiers de données ou des images : ils n'ont pas d'en-tête à orner.
  // Et un PDF déjà stocké qu'on renvoie tel quel n'est pas composé non plus.
  const amont    = lignes.slice(Math.max(0, i - 14), i + 1).join('\n');
  const parBlob  = /a\.download\s*=/.test(l)
                && /type:\s*['"`](?:text\/html|application\/pdf)/.test(amont)
                && !/d\.content|\.content\.split/.test(amont);
  if (!parPDF && !parFen && !parBlob) return;
  const nom = /dlPDF\([^,]*,\s*[`'"]([^`'"$]*)/.exec(l)
           || /a\.download\s*=\s*[`'"]([^`'"$]*)/.exec(l);
  sorties.push({ ligne: i + 1, doc: (nom && nom[1]) || l.trim().slice(0, 46) });
});

const debutFonction = (i) => {
  for (let j = i; j >= 0 && j > i - 700; j--)
    if (/^(window\.[A-Za-z_$][\w$]*\s*=|function\s+[A-Za-z_$])/.test(lignes[j])) return j;
  return Math.max(0, i - 200);
};

// `window.machin = …` comme `function machin(…)` : deux formes de déclaration.
// N'en lire qu'une donnait « function » comme nom, et l'assistant d'impression
// n'était jamais reconnu comme tel.
const nomFonction = (ligne) => {
  const m = /^(?:window\.)?([A-Za-z_$][\w$]*)\s*=/.exec(ligne)
         || /^function\s+([A-Za-z_$][\w$]*)/.exec(ligne);
  return m ? m[1] : '?';
};

let sans = 0;
console.log('═══ EMBLÈME DE L\'ÉCOLE SUR LES DOCUMENTS IMPRIMÉS ═══\n');
for (const s of sorties) {
  const d = debutFonction(s.ligne - 1);
  const fn = nomFonction(lignes[d]);
  if (ASSISTANTS.has(fn)) continue;
  const aLogo = /_logoImg|SCHOOL_LOGO|logo_url/.test(lignes.slice(d, s.ligne).join('\n'));
  if (!aLogo) { sans++; console.log(`   ✗ ${fn.padEnd(30)} ${s.doc}   (ligne ${s.ligne})`); }
}

const total = sorties.filter(s => !ASSISTANTS.has(nomFonction(lignes[debutFonction(s.ligne - 1)]))).length;

console.log(sans
  ? `\n✗ ${sans} document(s) sur ${total} sans emblème — ajouter \`\${_logoImg(60)}\` à l'en-tête`
  : `\n✓ Les ${total} documents officiels portent l'emblème de l'école`);

// ══════════════════════════════════════════════════════════════════════════
//  LE CONTRÔLE INVERSE : l'emblème NE DOIT PAS être dans l'interface
//
//  SchoolSafe est le logiciel, Le Sage est l'école. Poser l'emblème de
//  l'école dans la barre latérale ou l'écran de connexion fait passer le
//  logiciel pour l'école. C'est arrivé en donnant une valeur par défaut à
//  `SCHOOL_LOGO` : l'interface, qui le lisait sans garde, s'est mise à
//  l'afficher partout dès le premier lancement.
//
//  L'emblème n'est légitime dans l'interface QUE si la Direction l'a
//  elle-même téléversé — donc lu depuis `DB.settings.school.logo`, jamais
//  depuis le repli intégré au fichier.
const debutsDoc = new Set(sorties.map(s => debutFonction(s.ligne - 1)));
const INTERFACE_OK = new Set([
  'ssBuildBadge', 'ssBuildCarte',   // la carte d'élève EST un document
  'applyCrop',                      // téléversement du logo dans Paramètres
  '_logoImg',                       // l'assistant lui-même
]);
let fuites = 0;
console.log('');
lignes.forEach((l, i) => {
  if (!/window\.SCHOOL_LOGO/.test(l)) return;
  if (/^\s*(\/\/|\*|<!--)/.test(l)) return;          // commentaire
  if (/window\.SCHOOL_LOGO\s*=/.test(l)) return;      // affectation
  const d = debutFonction(i);
  if (debutsDoc.has(d)) return;                      // dans un document
  const fn = nomFonction(lignes[d]);
  if (INTERFACE_OK.has(fn)) return;
  fuites++;
  console.log(`   ✗ ${fn.padEnd(28)} ligne ${i + 1} — l'emblème de l'école dans l'interface`);
});
console.log(fuites
  ? `\n✗ ${fuites} fuite(s) : lire DB.settings.school.logo, jamais le repli intégré`
  : `✓ L'interface reste SchoolSafe — l'emblème de l'école n'y paraît pas`);

process.exit(sans + fuites ? 1 : 0);
