#!/usr/bin/env node
// ═══════════════════════════════════════════════════════════════════════════
//  LES CONTRASTES DE L'ÉCRAN DE CONNEXION — MESURÉS
// ═══════════════════════════════════════════════════════════════════════════
//
//  Pourquoi un outil à part de `audit-contraste-site` : cet écran ne pose pas
//  son texte sur une couleur. Il le pose sur une PHOTOGRAPHIE, sous un voile,
//  sous une carte. Mesurer contre le dégradé déclaré dans `.login-screen`
//  donnait de 4,95 à 12,7:1 — tous au-dessus du seuil — pendant que « Adresse
//  e-mail » était illisible sur un visage en plein soleil.
//
//  On compose donc les trois couches, et on prend le PIRE CAS possible : une
//  photographie entièrement blanche. Si le contraste tient là, il tient sur
//  n'importe quelle image que la Direction déposera.
//
//  Ce que cet outil NE SAIT PAS vérifier, et qu'il faut savoir :
//    · le flou d'arrière-plan (backdrop-filter) — il ne change pas la
//      luminance moyenne, mais il lisse les zones claires : le vrai contraste
//      est donc au mieux égal à celui mesuré ici, jamais pire ;
//    · l'ombre portée des textes (text-shadow), qui aide l'œil sans que le
//      rapport WCAG en tienne compte — encore une marge en notre faveur ;
//    · une couleur d'accent fournie à l'exécution : il n'y en a plus, l'écran
//      ne va chercher aucune marque ailleurs.
//
//  Éprouvé dans les deux sens : `--preuve` rejoue le voile d'avant la
//  correction (5 % en haut de l'écran) et l'outil doit REFUSER.
// ═══════════════════════════════════════════════════════════════════════════

import { readFileSync } from 'fs';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const HTML = readFileSync(join(ROOT, 'dist/index.html'), 'utf8');
const PREUVE = process.argv.includes('--preuve');

// ── couleur ────────────────────────────────────────────────────────────────
const lin = c => { c /= 255; return c <= .04045 ? c / 12.92 : Math.pow((c + .055) / 1.055, 2.4); };
const L = ([r, g, b]) => .2126 * lin(r) + .7152 * lin(g) + .0722 * lin(b);
const ratio = (a, b) => { const [x, y] = [L(a), L(b)].sort((p, q) => q - p); return (x + .05) / (y + .05); };
const hex = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
const sur = (couche, a, fond) => fond.map((c, i) => a * couche[i] + (1 - a) * c);
const BLANC = [255, 255, 255];

// ── lecture des vraies valeurs du fichier livré ────────────────────────────
// Un outil qui porte ses propres constantes ne vérifie rien : il approuverait
// encore après qu'on ait éclairci la carte.
const manques = [];
const regle = (sel) => {
  const i = HTML.indexOf('\n' + sel + '{');
  if (i < 0) { manques.push(sel); return ''; }
  return HTML.slice(i + sel.length + 2, HTML.indexOf('}', i));
};
const rgba = (txt, quoi) => {
  const m = /rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+))?\s*\)/.exec(txt || '');
  if (!m) { manques.push(quoi); return [[0, 0, 0], 1]; }
  return [[+m[1], +m[2], +m[3]], m[4] === undefined ? 1 : +m[4]];
};
const taillePx = (txt, quoi) => {
  const m = /font-size:([\d.]+)px/.exec(txt || '');
  if (!m) { manques.push(quoi + ' — taille'); return 12; }
  return +m[1];
};
const alpha = (txt, quoi) => rgba(/color:(rgba?\([^)]*\))/.exec(txt || '')?.[1], quoi)[1];

const carteRegle  = regle('.login-container');
const voileRegle  = PREUVE
  ? 'linear-gradient(to bottom,rgba(10,17,48,.05) 0%,rgba(3,5,15,.65) 100%)'   // avant la correction
  : regle('.login-bg::after');
const champRegle  = regle('.login-input');
const placeholder = regle('.login-input::placeholder');
const sousTitre   = regle('.login-subtitle');
const lien        = regle('.login-link');
const separateur  = regle('.login-sep');
const pied        = regle('.login-foot-item');
const bouton      = regle('.btn-login');
const titre       = regle('.login-title');
const hint        = /id="LP_HINT"[^>]*style="([^"]*)"/.exec(HTML)?.[1] || (manques.push('#LP_HINT'), '');
// L'aperçu sous le champ : il montre le numéro ou l'adresse tels que le
// serveur les connaît. C'est du texte, il se mesure.
const apercuTel   = /id="LN_VU"[^>]*style="([^"]*)"/.exec(HTML)?.[1] || (manques.push('#LN_VU'), '');

// Une règle CSS porte plusieurs couleurs : le fond, la bordure, l'ombre. Les
// prendre toutes en bloc, c'est mesurer contre une bordure blanche à 10 % et
// déclarer l'écran illisible. On isole la déclaration `background`.
const declaration = (regleCss, prop, quoi) => {
  const m = new RegExp('(?:^|;)\\s*' + prop + ':((?:[^;(]|\\([^)]*\\))*)').exec(regleCss || '');
  if (!m) { manques.push(quoi + ' — ' + prop); return ''; }
  return m[1];
};

// la carte : ses arrêts de dégradé — on garde le MOINS couvrant, le pire cas
const arretsCarte = [...declaration(carteRegle, 'background', '.login-container')
  .matchAll(/rgba?\([^)]*\)/g)].map(m => rgba(m[0], '.login-container'));
const CARTE = arretsCarte.length
  ? arretsCarte.reduce((a, b) => (a[1] <= b[1] ? a : b))
  : (manques.push('.login-container — dégradé de fond'), [[0, 0, 0], 1]);

// le voile : le premier arrêt (haut de l'écran, le moins couvrant) et le dernier
const voileFond = PREUVE ? voileRegle : declaration(voileRegle, 'background', '.login-bg::after');
const arretsVoile = [...voileFond.matchAll(/rgba?\([^)]*\)/g)].map(m => rgba(m[0], '.login-bg::after'));
const VOILE = arretsVoile.length
  ? { "haut de l'écran": arretsVoile[0], "bas de l'écran": arretsVoile[arretsVoile.length - 1] }
  : (manques.push('.login-bg::after — dégradé du voile'), {});

const [cChamp, aChamp] = rgba(declaration(champRegle, 'background', '.login-input'), '.login-input — fond');
const OR = hex((/--gold:(#[0-9a-f]{6})/i.exec(HTML) || [, '#e0a83b'])[1]);
const ENCRE = hex((/color:(#[0-9a-f]{6})/i.exec(bouton) || [, '#1a1206'])[1]);


const TEXTES = [
  ['titre',                      BLANC, 1,                                   taillePx(titre, '.login-title'),      'carte'],
  ['sous-titre',                 BLANC, alpha(sousTitre, '.login-subtitle'), taillePx(sousTitre, '.login-subtitle'), 'carte'],
  ['nom du champ (placeholder)', BLANC, alpha(placeholder, '::placeholder'), taillePx(champRegle, '.login-input'), 'champ'],
  ['valeur saisie',              BLANC, 1,                                   taillePx(champRegle, '.login-input'), 'champ'],
  ['indice mot de passe',        BLANC, alpha(hint, '#LP_HINT'),             taillePx(hint, '#LP_HINT'),           'carte'],
  ['aperçu de l’identifiant',    BLANC, alpha(apercuTel, '#LN_VU'),          taillePx(apercuTel, '#LN_VU'),         'carte'],
  ['lien secondaire',            BLANC, alpha(lien, '.login-link'),          taillePx(lien, '.login-link'),        'carte'],
  ['séparateur des liens',       BLANC, alpha(separateur, '.login-sep'),     taillePx(separateur, '.login-sep'),   'carte'],
  ['pied de page',               BLANC, alpha(pied, '.login-foot-item'),     taillePx(pied, '.login-foot-item'),   'carte'],
  ["bouton — encre sur l'or",    ENCRE, 1,                                   taillePx(bouton, '.btn-login'),       'or'],
];

// ── mesure ─────────────────────────────────────────────────────────────────
console.log("═══ LES CONTRASTES DE L'ÉCRAN DE CONNEXION ═══\n");
if (manques.length) {
  console.log("⚠️  Introuvables dans le fichier livré — l'outil ne peut pas les");
  console.log('    vérifier, et il ne fait pas semblant :');
  manques.forEach(m => console.log('      · ' + m));
  console.log('');
}

const PHOTOS = { 'photographie BLANCHE (pire cas)': BLANC, 'photographie sombre': hex('#1a1f14') };
let echecs = 0, mesures = 0;
for (const [nomPhoto, photo] of Object.entries(PHOTOS)) {
  for (const [ouVoile, [cv, av]] of Object.entries(VOILE)) {
    console.log(`── ${nomPhoto} · voile du ${ouVoile}`);
    const fondCarte = sur(CARTE[0], CARTE[1], sur(cv, av, photo));
    const fondChamp = sur(cChamp, aChamp, fondCarte);
    for (const [quoi, couleur, a, taille, ou] of TEXTES) {
      const fond = ou === 'champ' ? fondChamp : ou === 'or' ? OR : fondCarte;
      const r = ratio(sur(couleur, a, fond), fond);
      const seuil = taille >= 24 ? 3 : 4.5;   // le gras n'est pas réclamé : seuil strict
      const ok = r >= seuil; if (!ok) echecs++; mesures++;
      console.log(`   ${quoi.padEnd(28)} ${String(taille).padStart(5)}px  ${r.toFixed(2).padStart(6)}:1  ${ok ? '✓' : '✗ sous ' + seuil}`);
    }
    console.log('');
  }
}

if (PREUVE) {
  console.log(echecs
    ? `✓ PREUVE — avec le voile d'avant la correction, l'outil REFUSE : ${echecs} couple(s) sous le seuil.`
    : "✗ PREUVE MANQUÉE — l'outil accepte le voile d'avant la correction : il ne vérifie rien.");
  process.exit(echecs ? 0 : 1);
}

console.log(echecs
  ? `✗ ${echecs} couple(s) sur ${mesures} sous le seuil`
  : `✓ ${mesures} mesures : tout se lit, même si la photographie de fond est blanche.`);
process.exit(echecs ? 1 : 0);
