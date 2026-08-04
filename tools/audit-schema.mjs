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
import { readFileSync, existsSync, readdirSync } from 'fs';
import * as acorn from 'acorn';

const ROOT = new URL('..', import.meta.url).pathname;

// Le schéma se lit là où il est réellement écrit : `supabase/migrations`.
//
// Cet outil cherchait six fichiers SQL nommés en dur — ceux de l'AUTRE
// installation, absents d'ici. Il ne trouvait donc aucune table, comparait
// 306 écritures à un schéma vide, et annonçait « 49 problèmes » : quarante-neuf
// tables parfaitement normales, déclarées introuvables parce qu'il regardait
// au mauvais endroit. Un audit qui se trompe de source ne trouve pas moins de
// défauts que la réalité — il en invente.
//
// Les fichiers historiques restent lus s'ils existent : une installation plus
// ancienne peut encore les porter.
const HERITAGE = [
  'supabase_setup.sql', 'supabase_missing_tables.sql', 'supabase_fix_columns.sql',
  'supabase_fix_columns_v2.sql', 'supabase_fix_columns_v3.sql', 'supabase_migration_finale.sql',
];
function fichiersSql() {
  const liste = [];
  const dir = ROOT + 'supabase/migrations';
  if (existsSync(dir)) {
    // L'ordre chronologique compte : une colonne ajoutée puis retirée doit
    // suivre le même chemin que sur la base.
    for (const f of readdirSync(dir).filter(f => f.endsWith('.sql')).sort())
      liste.push('supabase/migrations/' + f);
  }
  for (const f of HERITAGE) if (existsSync(ROOT + f)) liste.push(f);
  return liste;
}

const args = process.argv.slice(2);
const only = args.includes('--table') ? args[args.indexOf('--table') + 1] : null;
const verbose = args.includes('--verbose');

// ── 1. Schéma déclaré ────────────────────────────────────────────────────
// Une déclaration de colonne commence par un nom ; une contrainte de table
// commence par un mot-clé. Sans cette liste, `primary`, `constraint` ou `check`
// entrent au schéma comme des colonnes, et l'outil accepte n'importe quoi.
const MOTS_CLES = new Set(['primary', 'foreign', 'unique', 'check', 'constraint', 'exclude', 'like']);

function loadSchema() {
  const cols = new Map(), policies = new Map(), fichiers = fichiersSql();
  // Une table n'est vérifiable COLONNE PAR COLONNE que si le dépôt porte son
  // CREATE TABLE. Trois colonnes ajoutées par un ALTER à une table créée
  // ailleurs ne disent rien des trente autres : les compter comme le schéma
  // complet ferait déclarer « absentes » toutes celles qu'on ne voit pas.
  const creees = new Set();
  const sansSchema = (t) => t.replace(/^"?(public|private)"?\./i, '').replace(/"/g, '');
  for (const f of fichiers) {
    const sql = readFileSync(ROOT + f, 'utf8');

    for (const m of sql.matchAll(/CREATE TABLE\s+(?:IF NOT EXISTS\s+)?([a-z_0-9."]+)\s*\(([\s\S]*?)\n\s*\);/gi)) {
      // `private.` n'est pas exposé à PostgREST : le navigateur n'y écrit
      // jamais, et le porter au schéma ferait croire l'inverse.
      if (/^"?private"?\./i.test(m[1])) continue;
      const t = sansSchema(m[1]);
      const set = cols.get(t) || new Set();
      for (const c of m[2].matchAll(/^\s+"?([A-Za-z_][A-Za-z_0-9]*)"?\s+[A-Za-z]/gm))
        if (!MOTS_CLES.has(c[1].toLowerCase())) set.add(c[1].toLowerCase());
      cols.set(t, set); creees.add(t);
    }
    for (const m of sql.matchAll(/ALTER TABLE\s+(?:IF EXISTS\s+)?([a-z_0-9."]+)([\s\S]*?);/gi)) {
      if (/^"?private"?\./i.test(m[1])) continue;
      const t = sansSchema(m[1]);
      const set = cols.get(t) || new Set();
      for (const c of m[2].matchAll(/ADD COLUMN\s+(?:IF NOT EXISTS\s+)?"?([A-Za-z_][A-Za-z_0-9]*)"?/gi)) set.add(c[1].toLowerCase());
      for (const c of m[2].matchAll(/DROP COLUMN\s+(?:IF EXISTS\s+)?"?([A-Za-z_][A-Za-z_0-9]*)"?/gi)) set.delete(c[1].toLowerCase());
      if (set.size) cols.set(t, set);
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
  return { cols, policies, creees, fichiers };
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
const { cols, policies, creees, fichiers } = loadSchema();
const { code, offset } = loadScript();
const ast = acorn.parse(code, { ecmaVersion: 2022, locations: true, allowReturnOutsideFunction: true });
const writes = analyse(ast);

const missing = new Map();   // table → Map(colonne → [lignes])
const opsByTable = new Map();
// Champs que l'analyse n'a pas su résoudre — un objet construit dans une
// boucle, par exemple. L'outil les taisait : une écriture pouvait ainsi
// porter des colonnes inconnues sans qu'il dise un mot. Il ne peut pas les
// vérifier, mais il doit dire qu'il ne les vérifie pas.
const opaques = new Map();

// Tables écrites dont le dépôt ne porte pas la déclaration. Ce n'est PAS la
// même chose qu'une table absente de la base : le schéma de fond vit dans le
// projet Supabase et n'a jamais été déposé ici. L'outil ne peut donc rien en
// dire — et il le dit, au lieu de les compter comme des défauts.
const horsPortee = new Set();

for (const w of writes) {
  if (only && w.table !== only) continue;
  (opsByTable.get(w.table) || opsByTable.set(w.table, new Set()).get(w.table)).add(w.op);
  if (!creees.has(w.table)) { horsPortee.add(w.table); continue; }
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
console.log(`${fichiers.length} fichier(s) SQL lus · ${creees.size} table(s) déclarées dans le dépôt`);
console.log(`${writes.length} écritures analysées · ${opsByTable.size} table(s) écrites par le code\n`);

if (opaques.size) {
  console.log('── Non vérifiable : objets construits dynamiquement ──');
  console.log('   (l\'outil ne peut pas en lire les champs — à contrôler à la main)');
  for (const [t, vars] of [...opaques].sort())
    console.log(`   ~ ${t} ← ${[...vars].join(', ')}`);
  console.log();
}

if (horsPortee.size) {
  console.log('── HORS DE PORTÉE : le dépôt ne porte pas la déclaration de ces tables ──');
  console.log('   Elles existent dans le projet Supabase ; leur schéma n\'a pas été');
  console.log('   déposé ici. L\'outil ne peut donc PAS dire si le code écrit des');
  console.log('   colonnes qui existent. Ce ne sont pas des défauts — ce sont des');
  console.log('   angles morts, et ils le resteront tant que le schéma manquera.');
  const l = [...horsPortee].sort();
  for (let i = 0; i < l.length; i += 6) console.log('     ' + l.slice(i, i + 6).join(' · '));
  console.log(`   → ${l.length} table(s) non vérifiables sur ${opsByTable.size} écrites.`);
  console.log('     Demandé à ChatGPT : coordination/DEMANDES_A_CHATGPT.md · P0-7\n');
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

// Trois verdicts, pas deux. « Aucun écart » quand rien n'a pu être comparé
// serait le pire des mensonges : un feu vert posé sur un angle mort.
const verifiees = opsByTable.size - horsPortee.size;
if (problems) {
  console.log(`✗ ${problems} problème(s) sur ${verifiees} table(s) vérifiable(s)`);
  process.exit(1);
}
if (!verifiees) {
  console.log('⚠ CET AUDIT NE VÉRIFIE RIEN POUR L\'INSTANT.');
  console.log('  Aucune des tables écrites par le code n\'est déclarée dans le dépôt :');
  console.log('  il n\'a rien à comparer, et un « ✓ » ici ne voudrait rien dire.');
  console.log('  Il retrouvera son utilité le jour où le schéma sera déposé.');
  process.exit(1);
}
console.log(`✓ Aucun écart entre le code et le schéma, sur ${verifiees} table(s) vérifiable(s)`);
process.exit(0);
