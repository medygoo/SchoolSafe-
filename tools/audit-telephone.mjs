#!/usr/bin/env node
// ═══════════════════════════════════════════════════════════════════════════
//  Le numéro du navigateur et le numéro du serveur doivent être LE MÊME
// ═══════════════════════════════════════════════════════════════════════════
//
//  Depuis P0-20, `users.phone` identifie un compte. Le serveur pose sa forme
//  canonique dans `private.normalize_phone_e164` ; le navigateur la transcrit
//  dans `window._telE164` pour montrer, AVANT d'envoyer, ce qui sera
//  enregistré.
//
//  Deux transcriptions qui divergent ne produisent aucune erreur : elles
//  produisent un compte introuvable, ou deux comptes pour la même personne.
//  Cet outil les confronte de deux façons :
//
//    1. STRUCTURE — chaque règle littérale du SQL se retrouve-t-elle dans le JS ?
//       Si ChatGPT change une règle, le contrôle tombe.
//    2. COMPORTEMENT — 40 numéros dont la réponse est écrite à la main.
//
//  Éprouvé dans les deux sens : `--preuve` sabote une règle du JS et le
//  contrôle DOIT refuser.

import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ICI = dirname(fileURLToPath(import.meta.url));
const RACINE = join(ICI, '..');
const PREUVE = process.argv.includes('--preuve');

// ── Le SQL de référence ─────────────────────────────────────────────────────
const DIR = join(RACINE, 'supabase', 'migrations');
const fichier = readdirSync(DIR)
  .filter(f => f.endsWith('.sql'))
  .sort()
  .reverse()
  .find(f => readFileSync(join(DIR, f), 'utf8').includes('function private.normalize_phone_e164'));

if (!fichier) {
  console.error('✗ `private.normalize_phone_e164` est introuvable dans supabase/migrations.');
  console.error('  Sans la référence du serveur, ce contrôle ne vérifie rien — il ne passera pas.');
  process.exit(2);
}
const sql = readFileSync(join(DIR, fichier), 'utf8');
const corpsSql = sql.slice(sql.indexOf('function private.normalize_phone_e164'));

// ── Le JS du navigateur ─────────────────────────────────────────────────────
const page = readFileSync(join(RACINE, 'dist', 'index.html'), 'utf8');
const debut = page.indexOf('window._telE164 = ');
if (debut < 0) {
  console.error('✗ `window._telE164` est absent de dist/index.html.');
  process.exit(2);
}
let corpsJs = page.slice(debut, page.indexOf('\n};', debut) + 3);

// Le sabotage : on retire la règle des numéros locaux `08…`, celle qui compte
// le plus en RDC. Le contrôle doit refuser — sinon il ne vérifie rien.
if (PREUVE) corpsJs = corpsJs.replace("/^0[0-9]{9}$/", "/^0[0-9]{99}$/");

const _telE164 = new Function('raw', corpsJs.replace('window._telE164 = ', 'const f = ') + '\nreturn f(raw);');

// ── 1. Structure : les règles du SQL sont-elles toutes dans le JS ? ──────────
const REGLES = [
  ['découpe des séparateurs', '[[:space:]().\\-]',    /\[\\s\(\)\.-\]/],
  ['préfixe international 00', "left(v_compact, 2) = '00'", /slice\(0,\s*2\)\s*===?\s*'00'/],
  ['numéro déjà en +…',       "'^[1-9][0-9]{7,14}$'",  /\^\[1-9\]\[0-9\]\{7,14\}\$/],
  ['local RDC 0XXXXXXXXX',    "'^0[0-9]{9}$'",         /\^0\[0-9\]\{9\}\$/],
  ['indicatif 243 sans +',    "'^243[0-9]{9}$'",       /\^243\[0-9\]\{9\}\$/],
  ['mobile 8… ou 9…',         "'^[89][0-9]{8}$'",      /\^\[89\]\[0-9\]\{8\}\$/],
  ['forme finale E.164',      "'^\\+[1-9][0-9]{7,14}$'", /\^\\\+\[1-9\]\[0-9\]\{7,14\}\$/],
];

const manques = [];
for (const [nom, litteralSql, motifJs] of REGLES) {
  const dansSql = corpsSql.includes(litteralSql);
  const dansJs  = motifJs.test(corpsJs);
  if (!dansSql) manques.push(`la règle « ${nom} » n'est plus dans le SQL de ChatGPT — relire ${fichier}`);
  else if (!dansJs) manques.push(`la règle « ${nom} » est dans le SQL et PAS dans window._telE164`);
}

// ── 2. Comportement : des réponses écrites à la main ─────────────────────────
const CAS = [
  // ce qu'on tape à l'école                        ce qui doit être enregistré
  ['+243810000111',      '+243810000111'],
  ['+243 810 000 111',   '+243810000111'],
  ['+243-810-000-111',   '+243810000111'],
  ['+243 (810) 000.111', '+243810000111'],
  ['  +243810000111  ',  '+243810000111'],
  ['00243810000111',     '+243810000111'],
  ['00 243 810 000 111', '+243810000111'],
  ['243810000111',       '+243810000111'],
  ['0810000111',         '+243810000111'],
  ['08 10 00 01 11',     '+243810000111'],
  ['810000111',          '+243810000111'],
  ['910000111',          '+243910000111'],
  ['+32470123456',       '+32470123456'],   // un parent en Belgique
  ['+1 202 555 0143',    '+12025550143'],
  // ce qui doit être REFUSÉ — refuser vaut mieux qu'interpréter
  ['',                   null],
  ['   ',                null],
  [null,                 null],
  [undefined,            null],
  ['abc',                null],
  ['+243 81O 000 111',   null],   // la LETTRE O, pas le chiffre
  ['081000011',          null],   // un chiffre de trop peu
  ['08100001111',        null],   // un chiffre de trop
  ['+0243810000111',     null],   // un indicatif ne commence pas par 0
  ['+243',               null],
  ['+',                  null],
  ['12345',              null],
  ['710000111',          null],   // pas un mobile RDC
  ['+243810000111x',     null],
  ['1234567',            null],
  ['++243810000111',     null],
];

const echecs = [];
for (const [entree, attendu] of CAS) {
  let obtenu;
  try { obtenu = _telE164(entree); } catch (e) { obtenu = 'ERREUR: ' + e.message; }
  if (obtenu !== attendu) {
    echecs.push(`${JSON.stringify(entree)} → ${JSON.stringify(obtenu)} au lieu de ${JSON.stringify(attendu)}`);
  }
}

// ── 3. Idempotence : normaliser deux fois ne change rien ─────────────────────
for (const [entree] of CAS) {
  const une = _telE164(entree);
  if (une !== null && _telE164(une) !== une) {
    echecs.push(`normaliser deux fois ${JSON.stringify(entree)} change le résultat`);
  }
}

// ── Verdict ─────────────────────────────────────────────────────────────────
console.log('\n═══ LE NUMÉRO DU NAVIGATEUR ET CELUI DU SERVEUR ═══\n');
console.log(`   référence serveur : ${fichier}`);
console.log(`   ${REGLES.length} règles comparées · ${CAS.length} numéros éprouvés\n`);

if (manques.length || echecs.length) {
  for (const m of manques) console.log('   ✗ ' + m);
  for (const e of echecs)  console.log('   ✗ ' + e);
  console.log(`\n✗ ${manques.length + echecs.length} écart(s). Un numéro qui n'est pas écrit`);
  console.log('  comme le serveur l\'écrit, c\'est un compte introuvable.\n');
  process.exit(1);
}

console.log('✓ Le navigateur écrit un numéro exactement comme le serveur l\'écrira.\n');
