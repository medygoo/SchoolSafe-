// ══════════════════════════════════════════════════════════════════════════
//  audit-signature.mjs — QUEL DOCUMENT SE SIGNE, ET QUEL DOCUMENT NE SE
//  SIGNE PAS ?
//
//  La règle, donnée par Loms le 4 août 2026 : « le reçu doit avoir la
//  signature ; le cahier de préparation, pas de signature, juste le logo ».
//
//  Elle se formule ainsi :
//
//    ┌──────────────────────────────────────────────────────────────────┐
//    │  Un document se signe pour DEUX raisons, et deux seulement :     │
//    │                                                                  │
//    │    · DÉLIVRANCE — il engage l'école envers un tiers : une        │
//    │      famille, un employé, une administration.                    │
//    │    · CERTIFICATION — il reste dans l'école, mais quelqu'un       │
//    │      répond de son exactitude.                                   │
//    │                                                                  │
//    │  Tout le reste est un document de TRAVAIL : emblème, pas de      │
//    │  signature.                                                      │
//    └──────────────────────────────────────────────────────────────────┘
//
//  La seconde raison n'était pas dans la première version de cette règle,
//  et l'outil a buté sur un cas : le KIT D'URGENCE MÉDICALE. Il ne quitte
//  pas l'école — il est affiché à l'infirmerie — mais il porte des groupes
//  sanguins et des allergies, et il est signé par la Direction et
//  l'infirmier(ère). Ce n'est pas une délivrance, c'est quelqu'un qui répond
//  d'une donnée dont dépend une vie.
//
//  On n'a pas forcé le cas dans la règle : c'est la règle qui était trop
//  étroite.
//
//  Ce n'est pas une question de forme. Une signature qui n'a pas de raison
//  d'être dévalue toutes les autres : si l'enseignant signe son cahier de
//  préparation, la signature du caissier au bas d'un reçu ne veut plus rien
//  dire de particulier. On ne signe que ce qui engage.
//
//  Le cahier de préparation portait un pied de page officiel à trois
//  signatures — bénéficiaire, acteur, autorité — sur un document que
//  l'enseignant écrit pour lui-même. Il ne l'a plus.
//
//  Cet outil est éprouvé dans les deux sens : il doit refuser une signature
//  de trop AUTANT qu'une signature manquante.
//
//    node tools/audit-signature.mjs
//    node tools/audit-signature.mjs --preuve
// ══════════════════════════════════════════════════════════════════════════
import fs from 'fs';

const src = fs.readFileSync(new URL('../dist/index.html', import.meta.url), 'utf8');
const lignes = src.split('\n');

// ── LA RÈGLE, document par document ───────────────────────────────────────
//
// « signe » : DÉLIVRANCE ou CERTIFICATION. Soit l'école remet un acte à
//             quelqu'un — famille, employé, administration — et il faut
//             savoir qui l'a établi et qui le vise ; soit le document reste
//             dans l'école mais quelqu'un répond de son exactitude.
// « travail » : l'école produit un document pour elle-même. Emblème, pas de
//             signature.
// « donnee » : ce n'est pas un document mais une extraction — CSV, JSON, image.
//             Ni emblème ni signature.

const REGLE = {
  // ─── ACTES DÉLIVRÉS À UN TIERS ────────────────────────────────────────
  downloadRecuPaiement:        ['signe', 'reçu remis à la famille qui paie'],
  downloadRecuFrais:           ['signe', 'reçu de frais scolaires'],
  downloadRecuRattrapage:      ['signe', 'reçu de rattrapage'],
  downloadRecuCantine:         ['signe', 'reçu de cantine'],
  downloadRecuActivites:       ['signe', 'reçu d’activités'],
  printVersementRecu:          ['signe', 'reçu de versement'],
  viewReceipt:                 ['signe', 'reçu consulté puis imprimé'],
  downloadAttestationPaiement: ['signe', 'attestation — engage l’école'],
  downloadCertificatScolarite: ['signe', 'certificat — engage l’école'],
  downloadCertificatPassage:   ['signe', 'certificat de passage'],
  downloadCertificatBonneConduite: ['signe', 'certificat de bonne conduite'],
  downloadConvocationPDF:      ['signe', 'convocation adressée à la famille'],
  downloadCommuniquePDF:       ['signe', 'communiqué de la Direction'],
  printFicheInscription:       ['signe', 'inscription — acte d’admission'],
  printSanctionLetter:         ['signe', 'lettre de sanction remise au parent'],
  downloadBulletin:            ['signe', 'bulletin remis à la famille'],
  exportAllBulletinsPDF:       ['signe', 'bulletins remis aux familles'],
  printPVDeliberation:         ['signe', 'procès-verbal de délibération'],
  printTenafepList:            ['signe', 'liste ENAFEP — transmise au ministère'],
  printExetatList:             ['signe', 'liste EXETAT — transmise au ministère'],
  printRapportSecope:          ['signe', 'rapport SECOPE — transmis au ministère'],
  // Le registre de présence du personnel se signe, et pour deux raisons qui
  // suffiraient chacune : le SECOPE peut le demander — c'est l'organe qui
  // contrôle la présence et la paie des enseignants en RDC — et il FONDE une
  // retenue sur un salaire. Un document qui peut coûter de l'argent à
  // quelqu'un doit porter le nom de celui qui en répond.
  printRegistrePresence:       ['signe', 'registre de présence — fonde une retenue sur salaire, opposable au SECOPE'],
  printPersonnelFichePaie:     ['signe', 'fiche de paie remise à l’employé'],
  printFichePaie:              ['signe', 'fiche de paie remise à l’employé'],
  printFicheSante:             ['signe', 'fiche santé — remise à un soignant'],
  printKitUrgencePDF:          ['signe', 'kit d’urgence — CERTIFICATION : on répond des groupes sanguins'],
  printDevoir:                 ['signe', 'devoir — le parent contresigne'],
  printReport:                 ['signe', 'rapport remis à la famille'],
  exportJournalPDF:            ['signe', 'journal comptable — arrêté SYSCOHADA'],
  exportBalancePDF:            ['signe', 'balance — arrêtée SYSCOHADA'],
  exportGrandLivrePDF:         ['signe', 'grand livre — arrêté SYSCOHADA'],
  exportComptabilitePDF:       ['signe', 'comptabilité — arrêtée SYSCOHADA'],
  exportBilanPDF:              ['signe', 'bilan — arrêté SYSCOHADA'],
  exportEtatFinancierPDF:      ['signe', 'état financier — Loms : tout document financier se signe'],

  // ─── DOCUMENTS DE TRAVAIL — emblème seul ──────────────────────────────
  downloadPrepPDF:             ['travail', 'CAHIER DE PRÉPARATION — l’enseignant l’écrit pour lui'],
  genererRapportMensuel:       ['travail', 'rapport interne de la Direction'],
  genererPalmaresAnnuel:       ['travail', 'palmarès — affichage interne'],
  printMonthlyAttendance:      ['travail', 'relevé de présences interne'],
  exportArchivePDF:            ['travail', 'archive de fin d’année'],

  // ─── EXTRACTIONS — ni emblème ni signature ────────────────────────────
  exportCSV:                   ['donnee', 'extraction CSV'],
  exportBackupJSON:            ['donnee', 'sauvegarde JSON'],
  exportScanLogCSV:            ['donnee', 'journal des passages, CSV'],
  exportSSCardPNG:             ['donnee', 'image d’une carte'],
  ssPrintCard:                 ['donnee', 'la carte porte déjà l’emblème'],
  exportSSAllCardsZip:         ['donnee', 'la carte porte déjà l’emblème'],
  printClassCards:             ['donnee', 'la carte porte déjà l’emblème'],
  // P0-8 — `imprimerCarte` remplace `generateDuplicata`, retirée le 10 août
  // 2026. Même classement, et pour la même raison : la carte EST la pièce,
  // elle porte l'emblème de l'école sur sa face. Un bloc de signatures
  // au-dessous d'un badge PVC de 86 mm n'aurait aucun sens, et ce qui
  // engage l'école ici n'est pas un paraphe : c'est le REGISTRE, qui garde
  // le numéro, l'auteur, la date et le motif de chaque émission.
  imprimerCarte:               ['donnee', 'la carte porte déjà l’emblème'],
  // La carte de première connexion (Loms, 11 août 2026). Elle n'engage
  // l'école envers personne et ne certifie aucune donnée dont quelqu'un
  // répond : elle transporte des identifiants. Une signature n'y voudrait
  // rien dire — et une signature sans raison d'être dévalue toutes les
  // autres.
  _partagerCarte:              ['donnee', 'carte d’identifiants — n’engage ni ne certifie'],
};

// ── Repérer les documents et ce qu'ils portent ────────────────────────────
const estDecl = l => /^(window\.[A-Za-z_$][\w$]*\s*=|function\s+[A-Za-z_$])/.test(l);
const nomDe = l => {
  const m = /^(?:window\.)?([A-Za-z_$][\w$]*)\s*=/.exec(l) || /^function\s+([A-Za-z_$][\w$]*)/.exec(l);
  return m ? m[1] : '?';
};
const plages = new Map();
lignes.forEach((l, i) => {
  if (!/dlPDF\(|\b\w+\.document\.write\(|a\.download\s*=/.test(l)) return;
  for (let j = i; j >= 0 && j > i - 900; j--) {
    if (!estDecl(lignes[j])) continue;
    if (nomDe(lignes[j]) === 'dlPDF') return;
    plages.set(j, Math.max(plages.get(j) || 0, i));
    return;
  }
});

// Une signature, c'est l'un des trois assistants partagés, ou une ligne à
// signer écrite sur place.
const A_SIGNATURE = /_officialFooter\(|_pdfSignatureBlock\(|sig-grid|sig-box|sig-line|Signature (de|du|des|parent|Direction|Infirmier)|Visa de |Lu et approuvé|cachet et signature|Cachet &amp; Signature|Cachet et signature/i;
// `_enteteOfficiel()` appelle `_logoDoc(52)` : un document qui l'emploie porte
// l'emblème, même s'il ne nomme pas l'assistant directement.
const A_EMBLEME   = /_logoDoc|_logoImg|SCHOOL_LOGO|_enteteOfficiel\(/;

// Loms, 4 août 2026 : « la signature doit être, mais bien définir quel profil
// et le nom de la personne qui a créé ce reçu ».
//
// Une case de signature vide ne désigne personne. Un document qui engage
// l'école doit porter le NOM et le PROFIL de celui qui l'a établi.
//
// Deux situations à ne pas confondre :
//   · AUTEUR ENREGISTRÉ — le document reçoit un troisième argument
//     `{nom, role, le}` : la personne qui a fait l'acte, telle qu'elle a été
//     enregistrée au moment où l'acte a eu lieu. Une réimpression six mois
//     plus tard donne toujours le même nom.
//   · À DÉFAUT — le pied porte « Délivré par » et la personne connectée. Ce
//     n'est pas un mensonge, mais ce n'est pas l'auteur de l'acte.
//
// Ce n'est PAS compté comme un défaut du frontend quand la donnée n'existe
// pas : DB.payments n'enregistre pas qui a encaissé. On ne pose pas une garde
// là où la valeur ne peut pas exister — on demande le champ.
// L'auteur peut arriver de deux façons, et l'outil doit reconnaître les deux.
//
// Il ne reconnaissait qu'un objet ÉCRIT EN CLAIR dans l'appel. Le jour où un
// reçu a reçu son auteur par une fonction — `_auteurDesLignes(lignes)`, qui
// rend `{nom, role, le}` ou `null` selon ce que la base porte — l'outil a
// continué à annoncer « délivré par ». Il mesurait la FORME de l'appel, pas
// ce qui s'imprime. Un audit qui ne voit qu'une écriture sur deux ne dit pas
// « je ne sais pas » : il dit « non », et c'est faux.
const AUTEUR_ENREGISTRE = /_officialFooter\([^;]*?(\{\s*nom\s*:|_auteurDesLignes\()/;
const NOMME_QUELQU_UN   = /_officialFooter\(|_pdfSignatureBlock\(|S\.user\?\.name|S\.user\.name|by_name|\br\.by\b|\bv\.by\b/;
const FINANCIER = new Set(['downloadRecuPaiement','downloadRecuFrais','downloadRecuRattrapage',
  'downloadRecuCantine','downloadRecuActivites','printVersementRecu','viewReceipt',
  'downloadAttestationPaiement','exportJournalPDF','exportBalancePDF','exportGrandLivrePDF',
  'exportComptabilitePDF','exportBilanPDF','exportEtatFinancierPDF']);

const preuve = process.argv.includes('--preuve');
let manquantes = 0, superflues = 0, inconnus = [], lignesSortie = [], financiers = [];

for (const [d, i] of [...plages].sort((a, b) => a[0] - b[0])) {
  const nom = nomDe(lignes[d]);
  const corps = lignes.slice(d, i + 1).join('\n');
  const regle = REGLE[nom];
  if (!regle) { inconnus.push(nom); continue; }
  const [attendu, pourquoi] = regle;
  const signe = A_SIGNATURE.test(corps);
  const emblm = A_EMBLEME.test(corps);

  const auteurEnr = AUTEUR_ENREGISTRE.test(corps);
  const nomme     = NOMME_QUELQU_UN.test(corps);
  if (FINANCIER.has(nom)) financiers.push({ nom, auteurEnr, nomme });

  let verdict = '·', note = '';
  // Un document financier qui ne nomme personne du tout : c'est un défaut.
  if (FINANCIER.has(nom) && !nomme) { verdict = '✘'; manquantes++; note = 'NE NOMME PERSONNE'; }
  if (attendu === 'signe' && !signe)      { verdict = '✘'; manquantes++; note = 'SIGNATURE MANQUANTE'; }
  else if (attendu === 'travail' && signe){ verdict = '✘'; superflues++; note = 'SIGNATURE DE TROP'; }
  else if (attendu === 'donnee' && signe) { verdict = '✘'; superflues++; note = 'SIGNATURE DE TROP'; }
  else if (attendu !== 'donnee' && !emblm){ verdict = '✘'; manquantes++; note = 'EMBLÈME MANQUANT'; }

  lignesSortie.push(`  ${verdict} ${nom.padEnd(30)} ${attendu.padEnd(8)} ${emblm ? 'emblème' : '       '} ${signe ? 'signature' : '         '}  ${note || pourquoi}`);
}

if (preuve) {
  // L'outil doit refuser dans LES DEUX SENS. On le lui demande sur pièce :
  // on lui présente un cahier de préparation qui se signe, et un reçu qui ne
  // se signe pas. S'il accepte l'un des deux, il ne vérifie rien.
  const faux = (corps, attendu) => {
    const signe = A_SIGNATURE.test(corps);
    if (attendu === 'signe')   return !signe;                 // doit être refusé
    if (attendu === 'travail') return signe;                  // doit être refusé
    return false;
  };
  const cahierSigne = faux('${_officialFooter(t.name,"Enseignant(e)")}', 'travail');
  const recuNu      = faux('<div>Reçu n° 42</div>', 'signe');
  console.log('\n  PREUVE — l\'outil refuse-t-il dans les deux sens ?\n');
  console.log(`    un cahier de préparation QUI SE SIGNE  →  ${cahierSigne ? 'REFUSÉ' : 'accepté'}`);
  console.log(`    un reçu SANS aucune signature          →  ${recuNu ? 'REFUSÉ' : 'accepté'}`);
  const ok = cahierSigne && recuNu;
  console.log(`    ${ok ? '✔ il refuse la signature de trop ET la signature manquante.'
                        : '✘ il ne sait refuser que dans un sens : il ne vérifie rien.'}\n`);
  process.exit(ok ? 0 : 1);
}

console.log('\n═══ QUEL DOCUMENT SE SIGNE ? ═══');
console.log('    un document se signe quand il ENGAGE l\'école envers un TIERS ;');
console.log('    un document de TRAVAIL porte l\'emblème et ne se signe pas.\n');
console.log(lignesSortie.join('\n'));

// ── Les documents financiers : qui les a établis ? ────────────────────────
console.log('\n  DOCUMENTS FINANCIERS ET REÇUS — l\'auteur est-il nommé ?');
for (const f of financiers)
  console.log(`    ${f.auteurEnr ? '✓ auteur enregistré ' : f.nomme ? '· délivré par        ' : '✘ personne          '} ${f.nom}`);
// Un état comptable est ÉTABLI au moment où on le tire : celui qui le génère
// en est bien l'auteur. Un reçu, lui, atteste un encaissement ANTÉRIEUR — son
// auteur est le caissier qui a reçu l'argent, et cette donnée manque.
const ETAT_COMPTABLE = new Set(['exportEtatFinancierPDF','exportJournalPDF','exportBalancePDF',
  'exportGrandLivrePDF','exportComptabilitePDF','exportBilanPDF']);
const recusSansAuteur = financiers.filter(f => !f.auteurEnr && f.nomme && !ETAT_COMPTABLE.has(f.nom));
if (recusSansAuteur.length) {
  console.log(`\n  ⓘ ${recusSansAuteur.length} reçu(s) portent « Délivré par » et non « Établi par ».`);
  console.log('    Un reçu atteste un encaissement ANTÉRIEUR : son auteur est le caissier');
  console.log('    qui a reçu l\'argent. Or DB.payments n\'enregistre pas qui a encaissé —');
  console.log('    aucune écriture ne renseigne ce champ, donc aucune lecture ne le peut.');
  console.log('    Ce n\'est pas un défaut du frontend : c\'est un champ à DEMANDER.');
  console.log('    (Les états comptables, eux, sont établis au moment du tirage :');
  console.log('     celui qui les génère en est bien l\'auteur, et il est nommé.)');
}

// Un outil doit déclarer ce qu'il ne sait pas vérifier.
console.log('\n  Ce que cet outil ne vérifie pas :');
console.log('    – que la signature soit AU BON ENDROIT sur la page (droite = autorité) ;');
console.log('    – qu\'un document classé « travail » ne parte pas malgré tout à un tiers ;');
console.log('    – la règle elle-même : elle appartient à Loms, pas au code.');

if (inconnus.length) {
  console.log(`\n  ✘ ${inconnus.length} document(s) SANS RÈGLE — ajoutez-les à REGLE :`);
  inconnus.forEach(n => console.log(`      ${n}`));
}

const total = manquantes + superflues + inconnus.length;
console.log(total === 0
  ? `\n✓ ${lignesSortie.length} documents : chacun porte ce qu'il doit porter, et rien de plus\n`
  : `\n✗ ${manquantes} manque(s) · ${superflues} signature(s) de trop · ${inconnus.length} sans règle\n`);
process.exit(total === 0 ? 0 : 1);
