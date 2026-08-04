#!/usr/bin/env node
/**
 * Détecte les écritures dont l'échec est invisible.
 *
 * Motif recherché : une écriture lancée sans être attendue, suivie d'un message
 * de succès. L'utilisateur lit « enregistré » alors que rien n'est peut-être
 * parti. C'est ce qui a laissé le blocage de `settings` passer inaperçu pendant
 * des semaines.
 *
 * Usage :  node tools/audit-writes.mjs [--page saveStudent] [--list]
 */
import { readFileSync } from 'fs';
import * as acorn from 'acorn';

const ROOT = new URL('..', import.meta.url).pathname;
const html = readFileSync(ROOT + 'dist/index.html', 'utf8');
const blocks = [...html.matchAll(/<script(?![^>]*\ssrc=)[^>]*>([\s\S]*?)<\/script>/gi)];
const main = blocks.sort((a, b) => b[1].length - a[1].length)[0];
const offset = html.slice(0, main.index + main[0].indexOf('>') + 1).split('\n').length - 1;
const ast = acorn.parse(main[1], { ecmaVersion: 2022, locations: true, allowReturnOutsideFunction: true });

const args = process.argv.slice(2);
const only = args.includes('--page') ? args[args.indexOf('--page') + 1] : null;
const list = args.includes('--list');

const WRITE = new Set(['pushSync', '_post', '_patch', '_upsert', '_del']);
const SUCCESS = /^(?!.*(erreur|impossible|refus|invalide|non autoris|échec|attention)).*$/i;

const findings = [];

function nameOfFn(node) {
  if (node.id?.name) return node.id.name;
  return null;
}

// Parcourt chaque fonction et examine le corps de ses blocs : une écriture non
// attendue suivie, dans le MÊME bloc, d'un message de succès.
function walk(node, fnName) {
  if (!node || typeof node.type !== 'string') return;

  let cur = fnName;
  if (node.type === 'VariableDeclarator' && node.init &&
      /Function/.test(node.init.type) && node.id.type === 'Identifier') cur = node.id.name;
  if (node.type === 'AssignmentExpression' && /Function/.test(node.right?.type || '') &&
      node.left.type === 'MemberExpression' && node.left.property?.name) cur = node.left.property.name;
  if (node.type === 'FunctionDeclaration' && node.id) cur = node.id.name;

  const body = node.body?.body || (Array.isArray(node.body) ? node.body : null);
  if (Array.isArray(body)) {
    let write = null;
    for (const st of body) {
      if (st.type !== 'ExpressionStatement') continue;
      const e = st.expression;

      // Écriture nue : ni await, ni .then, ni affectation du résultat
      if (e.type === 'CallExpression') {
        const c = e.callee;
        const nm = c.type === 'Identifier' ? c.name
                 : (c.type === 'MemberExpression' && c.property?.type === 'Identifier') ? c.property.name : null;
        if (WRITE.has(nm)) {
          const table = e.arguments[0]?.type === 'Literal' ? e.arguments[0].value : '?';
          write = { line: e.loc.start.line + offset, table, fn: cur };
        }
        // Message de succès dans le même bloc
        if (nm === 'toast' && write) {
          const a1 = e.arguments[1];
          const kind = a1?.type === 'Literal' ? a1.value : 'info';
          const msg = e.arguments[0]?.type === 'Literal' ? e.arguments[0].value
                    : (e.arguments[0]?.type === 'TemplateLiteral'
                       ? e.arguments[0].quasis.map(q => q.value.cooked).join('…') : '');
          if ((kind === 'success' || kind === 'info') && SUCCESS.test(msg)) {
            findings.push({ ...write, msg: (msg || '').slice(0, 58), toastLine: e.loc.start.line + offset });
            write = null;
          }
        }
      }
    }
  }

  for (const k in node) {
    if (k === 'loc') continue;
    const v = node[k];
    if (Array.isArray(v)) v.forEach(c => c && typeof c === 'object' && walk(c, cur));
    else if (v && typeof v === 'object' && typeof v.type === 'string') walk(v, cur);
  }
}
walk(ast, null);

const byFn = new Map();
for (const f of findings) {
  if (only && f.fn !== only) continue;
  (byFn.get(f.fn) || byFn.set(f.fn, []).get(f.fn)).push(f);
}

console.log('═══ ÉCRITURES DONT L\'ÉCHEC EST INVISIBLE ═══\n');
console.log('Une écriture lancée sans être attendue, suivie d\'un message de succès :');
console.log('l\'utilisateur lit « enregistré » alors que rien n\'est peut-être parti.\n');

const fns = [...byFn.keys()].sort((a, b) => byFn.get(b).length - byFn.get(a).length);
for (const fn of fns) {
  const items = byFn.get(fn);
  console.log(`${String(items.length).padStart(3)}  ${fn || '(anonyme)'}`);
  if (list) items.forEach(i => console.log(`       ligne ${i.line} · ${i.table} · « ${i.msg} »`));
}
console.log(`\n${findings.length} occurrence(s) dans ${byFn.size} fonction(s)`);
