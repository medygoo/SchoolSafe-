// ════════════════════════════════════════════════════════════════════════════
//  audit-contraste-site — la charte du site de l'école, mesurée
//
//  « Mesurer les contrastes, ne pas les estimer. » Un rapport se calcule en
//  quatre lignes ; l'œil se trompe, surtout sur les demi-transparences et sur
//  l'or, qui paraît lisible sur blanc et ne l'est pas (2,9:1).
//
//  L'outil lit les variables de dist/assets/site.css — il ne les recopie pas,
//  sinon il validerait sa propre copie au lieu du fichier livré — puis
//  confronte chaque couple texte/fond réellement employé au seuil WCAG AA.
//
//    node tools/audit-contraste-site.mjs
//    node tools/audit-contraste-site.mjs --preuve   ← qu'il sait dire NON
//
//  Seuils AA : 4,5:1 pour le texte courant · 3:1 pour les GRANDS caractères
//  (≥ 24 px, ou ≥ 19 px en gras) · 3:1 pour une bordure ou un repère.
// ════════════════════════════════════════════════════════════════════════════
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const RACINE = join(dirname(fileURLToPath(import.meta.url)), '..');
const CSS = join(RACINE, 'dist/assets/site.css');

// ── la mesure ───────────────────────────────────────────────────────────────
const canal = v => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4; };
function luminance(hex) {
  const h = hex.replace('#', '');
  const p = h.length === 3 ? [...h].map(c => c + c) : h.match(/../g);
  const [r, g, b] = p.map(x => parseInt(x, 16));
  return 0.2126 * canal(r) + 0.7152 * canal(g) + 0.0722 * canal(b);
}
const rapport = (a, b) => {
  const [x, y] = [luminance(a), luminance(b)].sort((m, n) => n - m);
  return (x + 0.05) / (y + 0.05);
};

// ── les variables, lues dans le fichier livré ───────────────────────────────
function palette() {
  const css = readFileSync(CSS, 'utf8');
  const bloc = css.slice(css.indexOf(':root{'), css.indexOf('}', css.indexOf(':root{')));
  const p = {};
  for (const m of bloc.matchAll(/(--[\w-]+)\s*:\s*(#[0-9a-fA-F]{3,6})/g)) p[m[1]] = m[2];
  return p;
}

// ── les couples réellement employés dans le site ────────────────────────────
//  texte · fond · seuil · où. Un couple qu'on retire du CSS se retire d'ici.
const COUPLES = [
  // fonds clairs
  ['--ink',        '--white',   4.5, 'corps de page'],
  ['--ink',        '--surface', 4.5, 'texte sur bandeau clair (stats, équipe, galerie)'],
  ['--muted',      '--white',   4.5, 'paragraphes secondaires'],
  ['--muted',      '--surface', 4.5, 'légendes sur bandeau clair'],
  ['--gold-deep',  '--white',   4.5, '.kicker, .menu a.active, .cinfo .l, .day-step .tm'],
  ['--gold-deep',  '--surface', 4.5, '.stat .num, .ex-cell .num'],
  ['--ground',     '--white',   4.5, '.btn-ghost'],

  // LE MUR — la couleur relevée sur la photographie de la Direction.
  // Elle ne porte que du blanc : --surface y tombe à 4,09 et l'or clair à 2,47.
  // C'est pourquoi, sur ce fond, l'or ne s'écrit pas — il se remplit.
  ['--white',      '--ground-deep', 4.5, '.prog — bandeau des programmes, tout son texte'],

  // le gris de travail, plus soutenu : celui qui porte le petit texte
  ['--white',      '--ground',  4.5, '.btn-solid, .mission-band p'],
  ['--surface',    '--ground',  4.5, '.mission-band'],
  ['--gold-pale',  '--ground',  4.5, '.mission-band .kicker'],

  // l'encre, en aplat
  ['--surface',    '--ink',     4.5, '.hero, .testi, .mobile-menu'],
  ['--surface-2',  '--ink',     4.5, '.topband, footer a, .hero p.lede, .crumb'],
  ['--ground-soft','--ink',     4.5, '.hero .badges, .foot-bottom, .t-card .who span'],
  ['--gold-light', '--ink',     4.5, '.hero .kicker, footer h4, .foot-tag, .chip:hover'],
  ['--gold',       '--ink',     3.0, 'filets et repères sur fond sombre'],

  // l'or en aplat porte du texte d'encre
  ['--ink',        '--gold',    4.5, '.ribbon, .btn-brass, .lead-card .role, .t-card .av'],
];

// ── ce que l'outil ne sait PAS vérifier — il le déclare ─────────────────────
const ANGLES_MORTS = [
  'les textes posés sur une photographie (hero, page-hero) : le contraste y dépend du voile, pas seulement des variables',
  'les demi-transparences rgba() employées en bordure ou en fond de carte',
  "la palette « côté enfant » : distinguer les âges est une fonction, elle ne suit pas la charte",
];

// ── sortie ──────────────────────────────────────────────────────────────────
const p = palette();
const preuve = process.argv.includes('--preuve');

if (preuve) {
  // Un outil doit être éprouvé dans les deux sens : il doit savoir dire NON.
  // Le cas connu : l'or sur blanc, que l'œil croit lisible.
  const r = rapport(p['--gold'], p['--white']);
  const nonPasse = r < 4.5;
  console.log(`\n  PREUVE — l'outil sait-il refuser ?\n`);
  console.log(`    --gold sur --white : ${r.toFixed(2)}:1  →  ${nonPasse ? 'REFUSÉ' : 'accepté'}`);
  console.log(`    ${nonPasse ? '✔ l\'outil refuse ce qu\'il doit refuser.' : '✘ l\'outil accepte tout : il ne vérifie rien.'}\n`);
  process.exit(nonPasse ? 0 : 1);
}

let echecs = 0, lignes = [];
for (const [f, b, seuil, ou] of COUPLES) {
  if (!p[f] || !p[b]) { console.error(`  variable absente du CSS : ${p[f] ? b : f}`); echecs++; continue; }
  const r = rapport(p[f], p[b]);
  const ok = r >= seuil;
  if (!ok) echecs++;
  lignes.push(`  ${ok ? '·' : '✘'} ${(f + ' sur ' + b).padEnd(30)} ${r.toFixed(2).padStart(6)}:1  (≥ ${seuil})  ${ou}`);
}

console.log(`\n  CONTRASTES DU SITE — ${CSS.replace(RACINE + '/', '')}\n`);
console.log(`  gris bleuté ${p['--ground']} · blanc ${p['--white']} · or ${p['--gold']}\n`);
console.log(lignes.join('\n'));
console.log(`\n  Ce que cet outil ne vérifie pas :`);
ANGLES_MORTS.forEach(a => console.log(`    – ${a}`));
console.log(echecs === 0
  ? `\n  ${COUPLES.length} couples mesurés, aucun sous le seuil.\n`
  : `\n  ${echecs} couple(s) sous le seuil — à corriger avant livraison.\n`);
process.exit(echecs === 0 ? 0 : 1);
