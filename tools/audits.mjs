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
