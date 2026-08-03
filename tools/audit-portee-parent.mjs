// ══════════════════════════════════════════════════════════════════════════
//  audit-portee-parent.mjs — de quelles tables un PARENT a-t-il besoin ?
//
//  `loadFromSupabase` tire les 47 tables de l'école à chaque réception : les
//  salaires, les dépenses, le journal comptable, les notes de tous les élèves.
//  Un parent en reçoit autant qu'une Direction. À 250 familles et une réception
//  par minute, cela fait ~11 750 requêtes par minute — et le téléphone d'une
//  famille détient la paie du personnel.
//
//  Réduire la liste À LA MAIN serait deviner : il suffit d'oublier une table
//  qu'un assistant partagé lit — `getStudentBalance` lit `fee_types`, `_classer`
//  lit `conduct` — pour qu'un écran se vide sans rien dire.
//
//  L'outil part des écrans du parent, suit les appels de fonction en fonction,
//  y compris ceux posés dans les `onclick` des gabarits, et rend la fermeture
//  transitive des tables lues.
//
//  Usage : node tools/audit-portee-parent.mjs [--detail]
// ══════════════════════════════════════════════════════════════════════════
import fs from 'fs';
import * as acorn from 'acorn';
import * as walk from 'acorn-walk';

const src = fs.readFileSync(new URL('../dist/index.html', import.meta.url), 'utf8');
const detail = process.argv.includes('--detail');
const blocs = [...src.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)].map(m => m[1]);

// ── Les écrans que la navigation du parent ouvre ───────────────────────────
const NAV_PARENT = ['dashboard','children','attendance','cahier_texte','timetable',
  'devoirs_parent','palmares_parent','recus_parent','cantine_parent','activites_parent',
  'messages','convocations','absences','authorized','scan_history','calendar',
  'notifications','profil_parent'];

// ── Recenser chaque fonction : ses lectures de DB, ses appels ──────────────
const fonctions = new Map();   // nom -> {tables:Set, appels:Set}
const EST_FN = t => /^(FunctionDeclaration|FunctionExpression|ArrowFunctionExpression)$/.test(t);

function analyser(node, nom) {
  if (!fonctions.has(nom)) fonctions.set(nom, { tables: new Set(), appels: new Set() });
  const f = fonctions.get(nom);
  const visiter = (n, dansFnImbriquee) => {
    if (!n || typeof n.type !== 'string') return;
    // DB.<table>
    if (n.type === 'MemberExpression' && !n.computed &&
        n.object.type === 'Identifier' && n.object.name === 'DB' &&
        n.property.type === 'Identifier') f.tables.add(n.property.name);
    // appel : nom nu, ou window.nom
    if (n.type === 'CallExpression') {
      const c = n.callee;
      if (c.type === 'Identifier') f.appels.add(c.name);
      else if (c.type === 'MemberExpression' && !c.computed && c.property.type === 'Identifier' &&
               c.object.type === 'Identifier' && (c.object.name === 'window' || c.object.name === 'R'))
        f.appels.add(c.property.name);
    }
    // Les gabarits posent des appels dans des attributs : onclick="fn('x')"
    if (n.type === 'TemplateLiteral')
      n.quasis.forEach(q => {
        for (const m of String(q.value.raw).matchAll(/\b(?:onclick|onchange|oninput|onsubmit)\s*=\s*["']?([A-Za-z_$][\w$]*)\s*\(/g))
          f.appels.add(m[1]);
      });
    if (n.type === 'Literal' && typeof n.value === 'string')
      for (const m of n.value.matchAll(/\b(?:onclick|onchange|oninput)\s*=\s*["']?([A-Za-z_$][\w$]*)\s*\(/g))
        f.appels.add(m[1]);
    for (const k in n) {
      const v = n[k];
      if (Array.isArray(v)) v.forEach(x => visiter(x, dansFnImbriquee));
      else if (v && typeof v === 'object' && typeof v.type === 'string') visiter(v, dansFnImbriquee);
    }
  };
  visiter(EST_FN(node.type) ? node.body : node, false);
}

for (const code of blocs) {
  let ast; try { ast = acorn.parse(code, { ecmaVersion:'latest', allowReturnOutsideFunction:true }); }
  catch (e) { console.error('✗ analyse impossible :', e.message); process.exit(2); }
  walk.simple(ast, {
    AssignmentExpression(n) {
      if (n.left.type !== 'MemberExpression' || n.left.computed) return;
      if (n.left.property.type !== 'Identifier') return;
      const o = n.left.object;
      const base = o.type === 'Identifier' ? o.name : null;
      if (base !== 'window' && base !== 'R') return;
      if (EST_FN(n.right.type)) analyser(n.right, n.left.property.name);
    },
    FunctionDeclaration(n) { if (n.id) analyser(n, n.id.name); },
    VariableDeclarator(n) {
      if (n.id.type === 'Identifier' && n.init && EST_FN(n.init.type)) analyser(n.init, n.id.name);
    },
  });
}

// ── Fermeture transitive depuis les écrans du parent ───────────────────────
const racines = [...NAV_PARENT, 'dashboardParent', 'getPendingCount', 'buildUI',
                 'render', 'goToMyProfile', 'updateSyncIndicator'];
const vus = new Set(), tables = new Map();   // table -> première fonction qui la lit
const file = [...racines];
while (file.length) {
  const nom = file.shift();
  if (vus.has(nom)) continue;
  vus.add(nom);
  const f = fonctions.get(nom);
  if (!f) continue;
  f.tables.forEach(t => { if (!tables.has(t)) tables.set(t, nom); });
  f.appels.forEach(a => { if (!vus.has(a)) file.push(a); });
}

// ── Ce que le serveur envoie aujourd'hui ──────────────────────────────────
const tirees = [...src.matchAll(/_get\('([a-z_0-9]+)'/g)].map(m => m[1]);
const tireesU = [...new Set(tirees)];

console.log('═══ DE QUELLES TABLES UN PARENT A-T-IL BESOIN ? ═══');
console.log(`    ${vus.size} fonctions atteintes depuis ses ${NAV_PARENT.length} écrans\n`);

const besoin = [...tables.keys()].filter(t => tireesU.includes(t)).sort();
const inutiles = tireesU.filter(t => !tables.has(t)).sort();

console.log(`  ${besoin.length} tables LUES par le parent :`);
if (detail) besoin.forEach(t => console.log(`     · ${t.padEnd(24)} (via ${tables.get(t)})`));
else console.log('     ' + besoin.join(' '));

console.log(`\n  ${inutiles.length} tables tirées SANS QU'AUCUN écran du parent les lise :`);
console.log('     ' + inutiles.join(' '));

const orphelines = [...tables.keys()].filter(t => !tireesU.includes(t) && t !== 'settings').sort();
if (orphelines.length) {
  console.log(`\n  ⚠ lues par le parent mais JAMAIS tirées du serveur :`);
  console.log('     ' + orphelines.join(' '));
}
