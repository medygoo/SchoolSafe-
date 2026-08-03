// ── Mutations exposées sans contrôle de rôle ─────────────────────────────
// Toute fonction sur window qui écrit en base doit vérifier S.user.role.
// Un contrôle dans le RENDU (`const canModify = …`) n'est pas une sécurité :
// la fonction reste appelable depuis la console du navigateur.
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
const ECRIT = /pushSync\s*\(/;
const GARDE = /S\.user|_requireRole|_denyRole|Accès non autorisé|role\s*===|includes\(S\.user\.role\)|role!==/;
const LECTURE_SEULE = /^(R\.|render|show|open|print|export|dl|_fit|_b64|_lire|_est|_msg|_school|_cible|_uid|_hash)/;

const suspects = [];
for (const node of ast.body) {
  if (node.type !== 'ExpressionStatement') continue;
  const e = node.expression;
  if (e.type !== 'AssignmentExpression') continue;
  const t = e.left;
  if (t.type !== 'MemberExpression' || t.object?.name !== 'window') continue;
  const nom = t.property?.name; if (!nom) continue;
  const corps = src.slice(e.right.start, e.right.end);
  if (!ECRIT.test(corps)) continue;             // n'écrit pas → hors sujet
  if (GARDE.test(corps)) continue;              // contrôle présent
  if (LECTURE_SEULE.test(nom)) continue;        // helper de rendu
  suspects.push({ nom, ligne: ligneDe(e.start), taille: corps.length });
}
console.log('═══ MUTATIONS SANS CONTRÔLE DE RÔLE ═══\n');
if (!suspects.length) console.log('✓ aucune');
else {
  suspects.sort((a,b)=>a.ligne-b.ligne)
    .forEach(s => console.log(`  ${String(s.ligne).padStart(6)}  ${s.nom}`));
  console.log(`\n${suspects.length} fonction(s) à examiner`);
}
