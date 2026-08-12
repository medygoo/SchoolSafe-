// ══════════════════════════════════════════════════════════════════════════
//  audits.mjs — lance TOUS les audits, même quand l'un d'eux échoue.
//
//  Pourquoi ce fichier existe : `npm run audit` enchaînait les outils avec
//  `&&`. Le troisième — `verif-coherence` — est en panne depuis une reprise
//  du harnais. Résultat : les audits de l'emblème, de la charte, des
//  signatures et des contrastes NE TOURNAIENT PLUS DU TOUT, sans que rien ne
//  le dise. Le filet était troué à l'endroit exact où on croyait l'avoir
//  tendu.
//
//  C'est la même faute que celles que ces outils cherchent : un échec
//  silencieux. Ici il ne l'est plus — chaque outil tourne, et le tableau
//  final dit lequel passe et lequel ne passe pas.
//
//    node tools/audits.mjs
// ══════════════════════════════════════════════════════════════════════════
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ICI = dirname(fileURLToPath(import.meta.url));

const OUTILS = [
  ['portee',      'audit-portee.mjs',          'les pages blanches'],
  ['invariant',   'audit-invariant.mjs',       'toute table lue est déclarée'],
  ['gardes',      'audit-gardes.mjs',          'les mutations sans contrôle de rôle'],
  ['coherence',   'verif-coherence.mjs',       'la chaîne de calcul, exécutée'],
  ['logo',        'audit-logo.mjs',            'l’emblème sur les documents'],
  ['charte',      'audit-charte.mjs',          'gris · blanc · or sur les documents'],
  ['signature',   'audit-signature.mjs',       'quel document se signe'],
  ['contraste',   'audit-contraste-site.mjs',  'les contrastes du site, mesurés'],
  ['connexion',   'audit-contraste-connexion.mjs', "l'écran de connexion, sur photographie"],
  ['telephone',   'audit-telephone.mjs',       'le numéro écrit comme le serveur l’écrit'],
  ['cartes',      'recette-cartes.mjs',        'le registre des cartes, exécuté'],
  ['sortie',      'recette-sortie.mjs',        'la sortie en deux étapes, exécutée'],
  ['notifs',      'recette-notifications.mjs', 'le centre de notifications, exécuté'],
  ['encaissement','recette-auteur-encaissement.mjs','qui a encaissé, sur les reçus'],
  ['autorisees',  'recette-personnes-autorisees.mjs','les personnes autorisées au portail'],
  ['contact',     'recette-contact.mjs',       'corriger un téléphone ou une adresse'],
  ['scanphys',    'recette-scanner-physique.mjs','scanner physique ≠ accès QR Caisse'],
  ['fermeture',   'recette-scanner-fermeture.mjs','les points de fermeture du Scanner'],
  ['demarrage',   'audit-demarrage.mjs',       'ce qui retarde l’ouverture'],
  ['entete',      'audit-entete.mjs',          'la chaîne de responsabilité des documents'],
  ['messages',    'recette-messages-v2.mjs',    'le routage Parent → Direction → enseignant'],
  ['recuv2',      'recette-recu-v2.mjs',        'le reçu de paiement V2'],
  ['whatsapp',    'recette-acces-whatsapp.mjs', 'l’invitation par code WhatsApp'],
  ['connexionux', 'recette-ecran-connexion.mjs','l’ouverture et la frappe, sur l’écran de connexion'],
  ['presencerh',  'recette-presence-personnel.mjs','le registre de présence du personnel, et sa retenue'],
  // ── QUATRE OUTILS QUI EXISTAIENT SANS JAMAIS TOURNER ────────────────────
  // `CLAUDE.md` les présentait dans son tableau des outils comme faisant
  // partie du filet. Ils n'étaient dans aucune liste : `npm run audit` ne les
  // a jamais lancés une seule fois. C'est la leçon du 4 août, commise ici même
  // — « une règle qu'on lit et qu'on n'exécute pas ne protège de rien » — et
  // c'est aussi celle de l'enchaînement `&&` : un filet troué ne se voit pas,
  // il se mesure.
  ['mort',        'audit-mort.mjs',            'les fonctions exposées sans appelant'],
  ['ecritures',   'audit-writes.mjs',          'les écritures dont l’échec est invisible'],
  ['schema',      'audit-schema.mjs',          'code ↔ SQL, et ce qu’il ne peut pas vérifier'],
  ['porteeparent','audit-portee-parent.mjs',   'ce dont le parent a réellement besoin'],
  ['compte',      'recette-cycle-compte.mjs',  'le cycle de vie d’un compte'],
];

const detail = process.argv.includes('--detail');
const resultats = [];

for (const [nom, fichier, quoi] of OUTILS) {
  const r = spawnSync(process.execPath, [join(ICI, fichier)], { encoding: 'utf8' });
  const ok = r.status === 0;
  resultats.push({ nom, quoi, ok, sortie: (r.stdout || '') + (r.stderr || '') });
  if (detail || !ok) {
    console.log(`\n${'═'.repeat(74)}\n  ${nom.toUpperCase()} — ${quoi}\n${'═'.repeat(74)}`);
    console.log((r.stdout || '').trimEnd());
    if (!ok && r.stderr) console.log(r.stderr.trimEnd());
  }
}

console.log(`\n${'═'.repeat(74)}\n  RÉSUMÉ\n${'═'.repeat(74)}`);
for (const x of resultats) {
  // La dernière ligne utile de chaque outil résume son verdict.
  const der = x.sortie.split('\n').filter(l => l.trim()).pop() || '';
  console.log(`  ${x.ok ? '✓' : '✗'} ${x.nom.padEnd(11)} ${x.quoi.padEnd(38)} ${der.trim().slice(0, 60)}`);
}
const ratés = resultats.filter(x => !x.ok);
console.log(ratés.length
  ? `\n✗ ${ratés.length} audit(s) en échec : ${ratés.map(x => x.nom).join(', ')}\n`
  : `\n✓ les ${resultats.length} audits passent\n`);
process.exit(ratés.length ? 1 : 0);
