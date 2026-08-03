#!/usr/bin/env node
/**
 * Contrôle de conformité entre le code et le schéma de la base.
 *
 * Pourquoi un analyseur syntaxique plutôt que des expressions régulières :
 * une écriture prend de nombreuses formes — objet en clair, variable, spread,
 * champ ajouté sous condition. Trois audits successifs par expressions
 * régulières ont laissé passer 8 tables et 96 colonnes, chacun révélé par un
 * bug en production. Lire l'arbre du programme supprime cet angle mort.
 *
 * Usage :  node tools/audit-schema.mjs [--table students] [--verbose]
 */
import { readFileSync, existsSync } from 'fs';
import * as acorn from 'acorn';

const ROOT = new URL('..', import.meta.url).pathname;
const SQL_FILES = [
  'supabase_setup.sql',
  'supabase_missing_tables.sql',
  'supabase_fix_columns.sql',
  'supabase_fix_columns_v2.sql',
  'supabase_fix_columns_v3.sql',
  // Migration consolidée : c'est ce fichier qui est réellement exécuté sur
  // la base de l'école. Les v2/v3 restent lus pour l'historique.
  'supabase_migration_finale.sql',
];

const args = process.argv.slice(2);
const only = args.includes('--table') ? args[args.indexOf('--table') + 1] : null;
const verbose = args.includes('--verbose');

// ── 1. Schéma déclaré ────────────────────────────────────────────────────
function loadSchema() {
  const cols = new Map(), policies = new Map();
  for (const f of SQL_FILES) {
    const p = ROOT + f;
    if (!existsSync(p)) continue;
    const sql = readFileSync(p, 'utf8');

    for (const m of sql.matchAll(/CREATE TABLE IF NOT EXISTS\s+([a-z_0-9]+)\s*\(([\s\S]*?)\n\);/gi)) {
      const set = cols.get(m[1]) || new Set();
      for (const c of m[2].matchAll(/^\s+"?([A-Za-z_][A-Za-z_0-9]*)"?\s+[A-Z]/gm)) set.add(c[1].toLowerCase());
      cols.set(m[1], set);
    }
    for (const m of sql.matchAll(/ALTER TABLE\s+([a-z_0-9]+)([\s\S]*?);/gi)) {
      const set = cols.get(m[1]) || new Set();
      for (const c of m[2].matchAll(/ADD COLUMN IF NOT EXISTS\s+"?([A-Za-z_][A-Za-z_0-9]*)"?/gi)) set.add(c[1].toLowerCase());
      cols.set(m[1], set);
    }
    // Migration consolidée : les colonnes y sont déclarées en tuples
    // ('table','colonne','type') passés à une boucle, et non en ALTER TABLE.
    for (const m of sql.matchAll(/^\s*\('([a-z_0-9]+)','([A-Za-z_][A-Za-z_0-9]*)','[^']/gm)) {
      const set = cols.get(m[1]) || new Set();
      set.add(m[2].toLowerCase());
      cols.set(m[1], set);
    }

    // Policies littérales
    for (const m of sql.matchAll(/CREATE POLICY\s+"?([\w ]+)"?\s+ON\s+([a-z_0-9.]+)\s+FOR\s+(\w+)/gi)) {
      const t = m[2].replace(/^public\./, '');
      const set = policies.get(t) || new Set();
      set.add(m[3].toUpperCase()); policies.set(t, set);
    }
    // Policies créées en boucle : EXECUTE format(... FOR <CMD> ...) sur une liste
    for (const blk of sql.matchAll(/FOREACH\s+tbl\s+IN\s+ARRAY\s+ARRAY\[([\s\S]*?)\]([\s\S]*?)END LOOP/gi)) {
      const tables = [...blk[1].matchAll(/'([a-z_0-9]+)'/g)].map(x => x[1]);
      const cmds = [...blk[2].matchAll(/FOR\s+(SELECT|INSERT|UPDATE|DELETE)/gi)].map(x => x[1].toUpperCase());
      for (const t of tables) {
        const set = policies.get(t) || new Set();
        cmds.forEach(c => set.add(c)); policies.set(t, set);
      }
    }
  }
  return { cols, policies };
}

// ── 2. Code : extraire le script principal ───────────────────────────────
function loadScript() {
  const html = readFileSync(ROOT + 'dist/index.html', 'utf8');
  const blocks = [...html.matchAll(/<script(?![^>]*\ssrc=)[^>]*>([\s\S]*?)<\/script>/gi)];
  const main = blocks.sort((a, b) => b[1].length - a[1].length)[0];
  // Décalage vers les lignes du FICHIER : un numéro relatif au script extrait
  // n'aide personne à retrouver le code fautif.
  const offset = html.slice(0, main.index + main[0].indexOf('>') + 1).split('\n').length - 1;
  return { code: main[1], offset };
}

// ── 3 et 4. Portées, résolution des champs, relevé des écritures ─────────
// Un même nom de variable — `n`, `data`, `obj` — est réutilisé des dizaines de
// fois dans le fichier. Les résoudre globalement attribuait à une table les
// champs d'une autre. Il faut donc suivre les portées : une variable se résout
// dans le bloc où elle est lue, puis en remontant les portées englobantes.
const SCOPED = new Set([
  'Program', 'FunctionDeclaration', 'FunctionExpression', 'ArrowFunctionExpression',
  'BlockStatement', 'ForStatement', 'ForOfStatement', 'ForInStatement',
]);

function analyse(ast) {
  const writes = [];

  function fieldsOf(node, chain, seen = new Set(), depth = 0) {
    if (!node || depth > 5) return new Set();

    if (node.type === 'Identifier') {
      if (seen.has(node.name)) return new Set();
      seen.add(node.name);
      // Remonter la chaîne de portées, de la plus proche à la plus large.
      for (let i = chain.length - 1; i >= 0; i--) {
        const decl = chain[i].get(node.name);
        if (decl) return fieldsOf(decl, chain.slice(0, i + 1), seen, depth + 1);
      }
      return new Set(['?' + node.name]);         // non résoluble : ignoré au rapport
    }
    if (node.type === 'ConditionalExpression')
      return new Set([...fieldsOf(node.consequent, chain, seen, depth + 1),
                      ...fieldsOf(node.alternate,  chain, seen, depth + 1)]);
    if (node.type === 'LogicalExpression')
      return new Set([...fieldsOf(node.left,  chain, seen, depth + 1),
                      ...fieldsOf(node.right, chain, seen, depth + 1)]);
    if (node.type === 'AssignmentExpression')
      return fieldsOf(node.right, chain, seen, depth + 1);
    if (node.type !== 'ObjectExpression') return new Set();

    const out = new Set();
    for (const p of node.properties) {
      if (p.type === 'SpreadElement') {
        for (const f of fieldsOf(p.argument, chain, seen, depth + 1)) out.add(f);
      } else if (p.key) {
        out.add(p.key.type === 'Identifier' ? p.key.name : String(p.key.value));
      }
    }
    return out;
  }

  function noteCall(node, chain) {
    const c = node.callee;
    const name = c.type === 'Identifier' ? c.name
               : (c.type === 'MemberExpression' && c.property?.type === 'Identifier') ? c.property.name : null;
    const a = node.arguments;

    // L'opération s'écrit souvent `ancien ? 'patch' : 'post'`. Exiger un
    // littéral faisait IGNORER l'écriture entière : dix colonnes du cahier de
    // préparation manquaient au schéma sans que l'outil dise un mot. C'est
    // pour l'op qu'on est indulgent — la TABLE, elle, doit rester littérale,
    // sinon on ne sait pas contre quoi comparer.
    const opsLitteraux = (n) => {
      if (!n) return [];
      if (n.type === 'Literal') return [n.value];
      if (n.type === 'ConditionalExpression')
        return [...opsLitteraux(n.consequent), ...opsLitteraux(n.alternate)];
      if (n.type === 'LogicalExpression')
        return [...opsLitteraux(n.left), ...opsLitteraux(n.right)];
      return [];
    };

    if (name === 'pushSync' && a.length >= 3 && a[0].type === 'Literal') {
      const ops = opsLitteraux(a[1]);
      if (!ops.length) {
        console.warn(`  ⚠ ligne ${node.loc?.start.line} : pushSync('${a[0].value}', …) — opération non littérale, écriture non analysée`);
      }
      for (const op of ops)
        writes.push({ table: a[0].value, op, fields: fieldsOf(a[2], chain), line: node.loc?.start.line });
    }
    else if ((name === '_post' || name === '_upsert') && a.length >= 2 && a[0].type === 'Literal')
      writes.push({ table: a[0].value, op: name === '_post' ? 'post' : 'upsert', fields: fieldsOf(a[1], chain), line: node.loc?.start.line });
    else if (name === '_patch' && a.length >= 3 && a[0].type === 'Literal')
      writes.push({ table: a[0].value, op: 'patch', fields: fieldsOf(a[2], chain), line: node.loc?.start.line });
    else if (name === '_del' && a.length >= 1 && a[0].type === 'Literal')
      writes.push({ table: a[0].value, op: 'delete', fields: new Set(), line: node.loc?.start.line });
  }

  // Deux passes par portée : d'abord enregistrer les déclarations du bloc,
  // ensuite descendre. Sans cela, une variable définie après son usage dans le
  // même bloc — cas fréquent avec les fonctions — resterait introuvable.
  function walk(node, chain) {
    if (!node || typeof node.type !== 'string') return;
    let ch = chain;

    if (SCOPED.has(node.type)) {
      const scope = new Map();
      const body = node.body?.body || node.body || [];
      const stmts = Array.isArray(body) ? body : [body];
      for (const st of stmts) {
        if (st?.type === 'VariableDeclaration')
          for (const d of st.declarations)
            if (d.id.type === 'Identifier' && d.init) scope.set(d.id.name, d.init);
        if (st?.type === 'ExpressionStatement' && st.expression?.type === 'AssignmentExpression'
            && st.expression.left.type === 'Identifier')
          scope.set(st.expression.left.name, st.expression.right);
      }
      ch = [...chain, scope];
    }
    if (node.type === 'CallExpression') noteCall(node, ch);

    for (const k in node) {
      if (k === 'loc' || k === 'start' || k === 'end') continue;
      const v = node[k];
      if (Array.isArray(v)) v.forEach(c => c && typeof c === 'object' && walk(c, ch));
      else if (v && typeof v === 'object' && typeof v.type === 'string') walk(v, ch);
    }
  }

  walk(ast, []);
  return writes;
}

// ── 5. Rapport ───────────────────────────────────────────────────────────
const { cols, policies } = loadSchema();
const { code, offset } = loadScript();
const ast = acorn.parse(code, { ecmaVersion: 2022, locations: true, allowReturnOutsideFunction: true });
const writes = analyse(ast);

const missing = new Map();   // table → Map(colonne → [lignes])
const noTable = new Set();
const opsByTable = new Map();
// Champs que l'analyse n'a pas su résoudre — un objet construit dans une
// boucle, par exemple. L'outil les taisait : une écriture pouvait ainsi
// porter des colonnes inconnues sans qu'il dise un mot. Il ne peut pas les
// vérifier, mais il doit dire qu'il ne les vérifie pas.
const opaques = new Map();

for (const w of writes) {
  if (only && w.table !== only) continue;
  (opsByTable.get(w.table) || opsByTable.set(w.table, new Set()).get(w.table)).add(w.op);
  if (!cols.has(w.table)) { noTable.add(w.table); continue; }
  const known = cols.get(w.table);
  for (const f of w.fields) {
    if (f.startsWith('?')) {                         // valeur non résoluble
      (opaques.get(w.table) || opaques.set(w.table, new Set()).get(w.table)).add(f.slice(1));
      continue;
    }
    if (known.has(f.toLowerCase())) continue;
    const m = missing.get(w.table) || new Map();
    (m.get(f) || m.set(f, []).get(f)).push(w.line + offset);
    missing.set(w.table, m);
  }
}

let problems = 0;
console.log('═══ CONFORMITÉ CODE ↔ SCHÉMA ═══\n');
console.log(`${writes.length} écritures analysées · ${cols.size} tables déclarées\n`);

if (opaques.size) {
  console.log('── Non vérifiable : objets construits dynamiquement ──');
  console.log('   (l\'outil ne peut pas en lire les champs — à contrôler à la main)');
  for (const [t, vars] of [...opaques].sort())
    console.log(`   ~ ${t} ← ${[...vars].join(', ')}`);
  console.log();
}

if (noTable.size) {
  problems += noTable.size;
  console.log('── Tables écrites mais absentes du schéma ──');
  [...noTable].sort().forEach(t => console.log('   ✗', t));
  console.log();
}

if (missing.size) {
  console.log('── Colonnes écrites mais absentes ──');
  for (const t of [...missing.keys()].sort()) {
    const m = missing.get(t);
    problems += m.size;
    console.log(`\n${t}`);
    for (const c of [...m.keys()].sort()) {
      console.log(`   ✗ ${c}${verbose ? '   (lignes ' + m.get(c).slice(0, 4).join(', ') + ')' : ''}`);
    }
  }
  console.log();
}

// Un upsert est un INSERT : sans policy INSERT il est rejeté, même quand
// l'opération se résout finalement en mise à jour.
const rls = [];
for (const [t, ops] of opsByTable) {
  if (!cols.has(t)) continue;
  const p = policies.get(t);
  if (!p) continue;
  if ((ops.has('upsert') || ops.has('post')) && !p.has('INSERT')) rls.push(`${t} — écrit en ${[...ops].join('/')} mais aucune policy INSERT`);
  if (ops.has('patch') && !p.has('UPDATE')) rls.push(`${t} — écrit en patch mais aucune policy UPDATE`);
  if (ops.has('delete') && !p.has('DELETE')) rls.push(`${t} — supprime mais aucune policy DELETE`);
}
if (rls.length) {
  problems += rls.length;
  console.log('── Droits d\'accès insuffisants ──');
  rls.forEach(r => console.log('   ✗', r));
  console.log();
}

console.log(problems ? `✗ ${problems} problème(s)` : '✓ Aucun écart entre le code et le schéma');
process.exit(problems ? 1 : 0);
