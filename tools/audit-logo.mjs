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
//  contient, et y cherche l'assistant d'emblème — `_logoDoc`, `_logoImg` —
//  ou une lecture directe de `SCHOOL_LOGO`.
//
//  Le 4 août 2026, les DIX derniers documents ont reçu l'emblème via un
//  assistant unique, `_logoDoc(px)`. Sans repli : si la Direction n'a pas
//  téléversé l'emblème, rien ne paraît. Lui donner une valeur par défaut le
//  ferait porter par une école qui ne l'a pas choisi.
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
  // `_enteteOfficiel()` PORTE l'emblème — il appelle `_logoDoc(52)` lui-même.
  // Un assistant partagé échappe aux reprises : il a fallu l'apprendre à cet
  // outil, sinon il déclare « sans emblème » trois documents qui en ont un.
  const aLogo = /_logoDoc|_logoImg|SCHOOL_LOGO|logo_url|_enteteOfficiel\(/.test(lignes.slice(d, s.ligne).join('\n'));
  if (!aLogo) { sans++; console.log(`   ✗ ${fn.padEnd(30)} ${s.doc}   (ligne ${s.ligne})`); }
}

const total = sorties.filter(s => !ASSISTANTS.has(nomFonction(lignes[debutFonction(s.ligne - 1)]))).length;

console.log(sans
  ? `\n✗ ${sans} document(s) sur ${total} sans emblème — ajouter \`\${_enteteOfficiel()}\` ou \`\${_logoDoc(56)}\` à l'en-tête`
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
// La bonne question n'est PAS « chaque lecture porte-t-elle sa garde ? ».
// Une première version de ce contrôle listait neuf « fuites » — des lectures
// de `window.SCHOOL_LOGO` hors des documents — et aucune n'était un défaut :
// la ligne juste au-dessus affectait la valeur depuis les réglages, ou la
// lecture servait à construire une carte, qui EST un document. Poser neuf
// gardes n'aurait rien protégé.
//
// La bonne question est : **la valeur peut-elle seulement être autre chose
// que ce que la Direction a téléversé ?** Si toute affectation vient des
// réglages, d'un téléversement, ou de `null`, alors le global ne peut PAS
// contenir un emblème intégré — et le lire, où que ce soit, est sans risque.
//
// C'est ce seul point qu'on vérifie. Il tient en trois lignes de code au
// lieu de neuf reproches, et il attrape la vraie faute : le jour où
// quelqu'un écrira `window.SCHOOL_LOGO = 'data:image/…'`, l'emblème de
// l'école reparaîtra dans la barre latérale dès le premier lancement — et
// l'application se remettra à porter l'école.
let repliHorsDoc = 0, nomLogiciel = 0;
const debutsDocuments = new Set(sorties.map(x => debutFonction(x.ligne - 1)));

// ══════════════════════════════════════════════════════════════════════════
//  LE NOM DU LOGICIEL N'ENTRE PAS DANS UN DOCUMENT DE L'ÉCOLE
//
//  Symétrique du contrôle de l'emblème, et de la même famille : l'interface
//  porte SchoolSafe, le papier porte Le Sage.
//
//  Un bulletin qui affiche « 🛡️ SchoolSafe » en en-tête, une liste ENAFEP qui
//  se dit « générée par SchoolSafe v3.0 », un certificat qui porte le nom de
//  l'éditeur : une administration lit cela au premier coup d'œil et comprend
//  que c'est le LOGICIEL qui délivre. Ce n'est pas lui qui engage.
//
//  Vingt documents étaient dans ce cas le 4 août 2026, dont les bulletins, les
//  deux listes d'examen d'État, les fiches de paie et l'archive de clôture.
//  Personne ne l'avait vu : rien ne le vérifiait.
//
//  Reste légitime — et donc admis ici :
//   · `sc.name || 'SchoolSafe'` : un REPLI quand l'école n'a pas de nom
//     enregistré. C'est une valeur par défaut, pas une signature ;
//   · les NOMS DE FICHIER : ils ne s'impriment pas sur le document.
{
  let mentions = 0;
  console.log('');
  for (const s2 of sorties) {
    const d = debutFonction(s2.ligne - 1);
    const fn = nomFonction(lignes[d]);
    if (ASSISTANTS.has(fn)) continue;
    for (let k = d; k <= s2.ligne - 1; k++) {
      const l = lignes[k];
      if (!/SchoolSafe/.test(l)) continue;
      if (/^\s*(\/\/|\*)/.test(l)) continue;
      for (const m of l.matchAll(/SchoolSafe/g)) {
        const ctx = l.slice(Math.max(0, m.index - 30), m.index + 30);
        if (/\|\|\s*['"]SchoolSafe/.test(ctx)) continue;        // repli du nom
        if (/download\s*=|fname|filename|\.json`|\.png'/.test(ctx)) continue; // nom de fichier
        mentions++;
        console.log(`   \u2717 ${fn.padEnd(28)} ligne ${k + 1} — le nom du LOGICIEL dans un document de l'école`);
        break;
      }
    }
  }
  console.log(mentions
    ? `\u2717 ${mentions} mention(s) : une administration croira que c'est le logiciel qui délivre`
    : `\u2713 Aucun document ne porte le nom du logiciel — le papier porte l'école`);
  nomLogiciel = mentions;
}

// ── LE REPLI DES DOCUMENTS, ET SA FRONTIÈRE ──────────────────────────────
// Depuis le 4 août 2026, l'emblème du Complexe Scolaire Le Sage est intégré
// au fichier sous `window.SCHOOL_LOGO_DOC` : un document en porte un
// TOUJOURS, c'est une obligation, pas une préférence.
//
// Toute la sécurité tient à une seule frontière : cette constante appartient
// aux DOCUMENTS. Si l'interface la lit, l'application se remet à porter
// l'école dès le premier lancement — l'erreur déjà commise, et corrigée, avec
// le repli de `SCHOOL_LOGO`.
//
// C'est ce qu'on vérifie ici, et rien d'autre. Éprouvé dans les deux sens.
{
  // `_dessinerCarteAcces` (11 août 2026) rejoint les deux constructeurs de
  // cartes d'élève, et pour la même raison : ce n'est pas un ÉCRAN, c'est une
  // PIÈCE qu'on remet à quelqu'un. L'emblème y est à sa place ; ce que la
  // frontière interdit, c'est qu'il reparaisse dans la barre latérale ou
  // l'écran de connexion.
  const OK_DOC = new Set(['_logoDoc', 'ssBuildBadge', 'ssBuildCarte', '_dessinerCarteAcces']);
  let hors = 0;
  lignes.forEach((l, i) => {
    if (!/SCHOOL_LOGO_DOC/.test(l)) return;
    if (/^\s*(\/\/|\*|<!--)/.test(l)) return;
    if (/window\.SCHOOL_LOGO_DOC\s*=/.test(l)) return;     // la déclaration
    const d = debutFonction(i);
    const fn = nomFonction(lignes[d]);
    if (OK_DOC.has(fn)) return;
    if (debutsDocuments.has(d)) return;                   // dans un document
    hors++;
    console.log(`   \u2717 ${fn.padEnd(28)} ligne ${i + 1} — le repli des DOCUMENTS lu hors d'un document`);
  });
  console.log(hors
    ? `\u2717 ${hors} lecture(s) de SCHOOL_LOGO_DOC hors document : l'emblème va reparaître dans l'interface`
    : `\u2713 Le repli des documents ne sort pas des documents`);
  repliHorsDoc = hors;
}

const SOURCES_LEGITIMES = [
  /window\.SCHOOL_LOGO\s*=\s*null\s*;/,                        // aucun repli
  /window\.SCHOOL_LOGO\s*=\s*DB\.settings[?.]*\.school[?.]*\.logo/, // les réglages
  /window\.SCHOOL_LOGO\s*=\s*data\s*;/,                        // le téléversement
];
let repli = 0;
console.log('');
lignes.forEach((l, i) => {
  if (!/window\.SCHOOL_LOGO\s*=/.test(l)) return;
  if (/^\s*(\/\/|\*|<!--)/.test(l)) return;
  if (SOURCES_LEGITIMES.some(re => re.test(l))) return;
  repli++;
  console.log(`   \u2717 ligne ${i + 1} — l'emblème reçoit une valeur qui ne vient pas de la Direction`);
  console.log(`     ${l.trim().slice(0, 120)}`);
});
console.log(repli
  ? `\n\u2717 ${repli} affectation(s) hors réglages : l'emblème de l'école reparaîtra dans l'interface`
  : `\u2713 L'emblème ne peut venir que de la Direction — aucun repli intégré, donc aucune fuite possible`);


process.exit(sans + repli + repliHorsDoc + nomLogiciel ? 1 : 0);
