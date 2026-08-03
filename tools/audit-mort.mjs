// ── Code mort : fonctions exposées que plus personne n'appelle ───────────
// Une fonction sans appelant n'est pas forcément à jeter — elle peut être
// branchée depuis un attribut HTML. On cherche donc son nom PARTOUT dans le
// fichier, attributs compris, et non seulement dans le JavaScript.
import { readFileSync } from 'fs';
import { parse } from 'acorn';

const html = readFileSync('dist/index.html', 'utf8');
const blocks = [...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)];
let src = '', map = [];
for (const b of blocks) {
  map.push({ start: src.length, line: html.slice(0, b.index).split('\n').length });
  src += b[1] + '\n;\n';
}
const ligneDe = p => { let o = map[0]; for (const x of map) if (x.start <= p) o = x;
  return o.line + src.slice(o.start, p).split('\n').length - 1; };

const ast = parse(src, { ecmaVersion: 2022 });
const definies = [];
for (const node of ast.body) {
  if (node.type !== 'ExpressionStatement') continue;
  const e = node.expression;
  if (e.type !== 'AssignmentExpression') continue;
  const t = e.left;
  if (t.type !== 'MemberExpression' || t.object?.name !== 'window') continue;
  const nom = t.property?.name;
  if (!nom || !e.right || !/Function|Arrow/.test(e.right.type)) continue;
  definies.push({ nom, start: e.start, taille: e.end - e.start });
}

// Les renderers R.xxx sont appelés par table de routage : hors sujet ici.
const orphelines = definies.filter(d => {
  const re = new RegExp('\\b' + d.nom.replace(/\$/g, '\\$') + '\\b', 'g');
  const occ = (html.match(re) || []).length;
  return occ <= 1;                       // seulement sa propre définition
});

console.log('═══ FONCTIONS SANS AUCUN APPELANT ═══\n');
if (!orphelines.length) console.log('✓ aucune');
else {
  orphelines.sort((a, b) => b.taille - a.taille).forEach(o =>
    console.log(`  ligne ${String(ligneDe(o.start)).padStart(6)}  ${o.nom.padEnd(30)} ${String(o.taille).padStart(6)} caractères`));
  const total = orphelines.reduce((s, o) => s + o.taille, 0);
  console.log(`\n${orphelines.length} fonction(s) · ${total} caractères`);
}
console.log(`\n(${definies.length} fonctions exposées au total)`);
