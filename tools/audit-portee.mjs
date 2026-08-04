// ══════════════════════════════════════════════════════════════════════════
//  audit-portee.mjs — un nom lu hors de la portée où il est déclaré
//
//  `R.devoirs_parent` définissait `renderDevoirItem` au niveau de la page,
//  puis `canSeeCorr` DANS la boucle sur les enfants. La fonction lisait
//  pourtant `canSeeCorr`. À la première interrogation affichée :
//
//      ReferenceError: canSeeCorr is not defined
//
//  Le rendu entier s'interrompt — le parent voyait une page vide et croyait
//  n'avoir reçu aucun devoir. `new Function(corps)` ne voit rien : c'est du
//  JavaScript parfaitement valide, la faute n'existe qu'à l'exécution.
//
//  L'outil reconstruit la chaîne des portées et signale toute lecture d'un
//  nom qu'aucune portée englobante ne déclare.
//
//  Approximation assumée : les portées de BLOC (let/const dans un `if`) sont
//  rabattues sur la fonction qui les contient. On perd les fautes de bloc,
//  on ne produit AUCUN faux positif de ce fait. Ce qui compte ici, ce sont
//  les noms cherchés dans une AUTRE fonction — la faute ci-dessus.
//
//  Usage : node tools/audit-portee.mjs
// ══════════════════════════════════════════════════════════════════════════
import fs from 'fs';
import * as acorn from 'acorn';
import * as walk from 'acorn-walk';

const src = fs.readFileSync(new URL('../dist/index.html', import.meta.url), 'utf8');

// ── Les blocs <script> internes, avec leur décalage de ligne ──────────────
const blocs = [];
const re = /<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g;
let m;
while ((m = re.exec(src)) !== null) {
  const avant = src.slice(0, m.index + m[0].indexOf('>') + 1);
  blocs.push({ code: m[1], ligne0: avant.split('\n').length });
}

// ── Ce qui existe sans être déclaré dans le fichier ───────────────────────
const GLOBAUX = new Set([
  // langage
  'undefined','NaN','Infinity','globalThis','Object','Array','String','Number',
  'Boolean','Symbol','BigInt','Math','JSON','Date','RegExp','Error','TypeError',
  'RangeError','SyntaxError','Promise','Map','Set','WeakMap','WeakSet','Proxy',
  'Reflect','Intl','Function','parseInt','parseFloat','isNaN','isFinite',
  'encodeURIComponent','decodeURIComponent','encodeURI','decodeURI','escape',
  'unescape','console','arguments','eval',
  // navigateur
  'window','document','navigator','location','history','screen','localStorage',
  'sessionStorage','indexedDB','caches','crypto','fetch','Request','Response',
  'Headers','Blob','File','FileReader','FormData','URL','URLSearchParams',
  'XMLHttpRequest','WebSocket','Worker','Notification','Image','Audio','Video',
  'Option','FontFace','AbortController','AbortSignal','TextEncoder','TextDecoder',
  'setTimeout','clearTimeout','setInterval','clearInterval','requestAnimationFrame',
  'cancelAnimationFrame','requestIdleCallback','queueMicrotask','alert','confirm',
  'prompt','print','open','close','postMessage','addEventListener',
  'removeEventListener','getComputedStyle','matchMedia','atob','btoa','structuredClone',
  'Element','HTMLElement','Node','NodeList','Event','CustomEvent','MutationObserver',
  'IntersectionObserver','ResizeObserver','DOMParser','XPathResult','BarcodeDetector',
  'Uint8Array',
  'Int8Array','Uint16Array','Uint32Array','Float32Array','Float64Array','ArrayBuffer',
  'DataView','performance','self','top','parent','frames','CSS','SVGElement',
  // bibliothèques chargées par <script src=…>
  'QRCode','jsQR','JSZip','html2pdf','html2canvas','jspdf','Chart','supabase',
]);

// ── Motifs de déclaration ─────────────────────────────────────────────────
function nomsDuMotif(n, out) {
  if (!n) return;
  switch (n.type) {
    case 'Identifier': out.push(n.name); break;
    case 'ObjectPattern': n.properties.forEach(p =>
      nomsDuMotif(p.type === 'RestElement' ? p.argument : p.value, out)); break;
    case 'ArrayPattern': n.elements.forEach(e => nomsDuMotif(e, out)); break;
    case 'AssignmentPattern': nomsDuMotif(n.left, out); break;
    case 'RestElement': nomsDuMotif(n.argument, out); break;
  }
}

const EST_FN = t => t === 'FunctionDeclaration' || t === 'FunctionExpression' ||
                    t === 'ArrowFunctionExpression';

// Tout ce qu'une portée de fonction déclare : ses paramètres, et toute
// déclaration de son corps SAUF celles des fonctions imbriquées.
function declaréesDans(scope) {
  const out = [];
  if (EST_FN(scope.type)) {
    scope.params.forEach(p => nomsDuMotif(p, out));
    if (scope.id) out.push(scope.id.name);          // récursion par son nom
    out.push('this', 'arguments');
  }
  const corps = EST_FN(scope.type) ? scope.body : scope;
  const descendre = (n) => {
    if (!n || typeof n.type !== 'string') return;
    if (n !== corps && EST_FN(n.type)) {
      if (n.type === 'FunctionDeclaration' && n.id) out.push(n.id.name);
      return;                                        // on n'entre pas
    }
    if (n.type === 'VariableDeclaration') n.declarations.forEach(d => nomsDuMotif(d.id, out));
    if (n.type === 'ClassDeclaration' && n.id) out.push(n.id.name);
    if (n.type === 'CatchClause' && n.param) nomsDuMotif(n.param, out);
    if (n.type === 'ImportDeclaration') n.specifiers.forEach(s => out.push(s.local.name));
    for (const k in n) {
      const v = n[k];
      if (Array.isArray(v)) v.forEach(descendre);
      else if (v && typeof v === 'object' && typeof v.type === 'string') descendre(v);
    }
  };
  descendre(corps);
  return new Set(out);
}

// ── Analyse ───────────────────────────────────────────────────────────────
const trouvés = [];
let refs = 0;

for (const bloc of blocs) {
  try {
    bloc.ast = acorn.parse(bloc.code, { ecmaVersion: 'latest', locations: true, allowReturnOutsideFunction: true });
  } catch (e) {
    console.error(`✗ analyse impossible (ligne ~${bloc.ligne0}) : ${e.message}`);
    process.exit(2);
  }
}

// Noms posés sur window.* — ils existent globalement dès leur affectation, et
// TOUS les blocs <script> partagent le même objet global. Les collecter bloc
// par bloc faisait passer pour introuvable `openPhotoCrop`, défini au dernier
// bloc et appelé au premier — après un `if (window.openPhotoCrop)`.
const surWindow = new Set();
for (const bloc of blocs) {
  walk.simple(bloc.ast, {
    AssignmentExpression(n) {
      if (n.left.type === 'MemberExpression' && !n.left.computed &&
          n.left.object.type === 'Identifier' && n.left.object.name === 'window' &&
          n.left.property.type === 'Identifier') surWindow.add(n.left.property.name);
    },
  });
}

for (const bloc of blocs) {
  const cache = new Map();
  const portéeDe = (n) => { if (!cache.has(n)) cache.set(n, declaréesDans(n)); return cache.get(n); };

  walk.ancestor(bloc.ast, {
    Identifier(n, _st, ancestors) {
      const parent = ancestors[ancestors.length - 2];
      if (!parent) return;
      // Ni un nom de propriété, ni une clé, ni une étiquette, ni une déclaration.
      if (parent.type === 'MemberExpression' && parent.property === n && !parent.computed) return;
      if (parent.type === 'Property' && parent.key === n && !parent.computed) return;
      if (parent.type === 'MethodDefinition' && parent.key === n && !parent.computed) return;
      if (parent.type === 'LabeledStatement' || parent.type === 'BreakStatement' ||
          parent.type === 'ContinueStatement') return;
      if (parent.type === 'VariableDeclarator' && parent.id === n) return;
      if (EST_FN(parent.type) && (parent.id === n || parent.params.includes(n))) return;
      if (parent.type === 'ClassDeclaration' || parent.type === 'ClassExpression') return;
      if (parent.type === 'ImportSpecifier' || parent.type === 'ExportSpecifier') return;
      // Motifs de déclaration et d'affectation : traités par nomsDuMotif.
      for (let i = ancestors.length - 2; i >= 0; i--) {
        const a = ancestors[i];
        if (a.type === 'VariableDeclarator' || a.type === 'CatchClause') return;
        if (EST_FN(a.type)) break;
        if (!['ObjectPattern','ArrayPattern','AssignmentPattern','RestElement','Property'].includes(a.type)) break;
      }

      refs++;
      if (GLOBAUX.has(n.name) || surWindow.has(n.name)) return;
      // Remonter la chaîne des portées.
      for (let i = ancestors.length - 1; i >= 0; i--) {
        const a = ancestors[i];
        if (a.type === 'Program' || EST_FN(a.type)) {
          if (portéeDe(a).has(n.name)) return;
        }
      }
      trouvés.push({ nom: n.name, ligne: bloc.ligne0 + n.loc.start.line - 1 });
    },
  });
}

// ══════════════════════════════════════════════════════════════════════════
//  ZONE MORTE TEMPORELLE — un `const` lu avant sa propre ligne
//
//  `dashboardParent` lisait `parentKidCids` dix lignes au-dessus de sa
//  déclaration, dans le rappel d'un `.filter()`. Tant que `DB.devoirs` était
//  vide, le rappel ne s'exécutait pas : rien ne paraissait. Au PREMIER devoir
//  publié, l'accueil du parent s'interrompait.
//
//  On ne signale que le cas certain : la lecture est dans un rappel passé
//  DIRECTEMENT en argument, donc exécuté sur place. Une fonction nommée ou
//  affectée peut être appelée plus tard — sa lecture est licite, et c'est le
//  motif le plus courant du fichier.
// ══════════════════════════════════════════════════════════════════════════
const SYNCHRONES = new Set(['map','filter','forEach','reduce','reduceRight','some',
  'every','find','findIndex','findLast','findLastIndex','sort','flatMap','from']);
const zonesMortes = [];
const _cacheG = new Map();
const portéeDeGlobale = (n) => {
  if (!_cacheG.has(n)) _cacheG.set(n, declaréesDans(n));
  return _cacheG.get(n);
};
for (const bloc of blocs) {
  // Position de chaque déclaration let/const/class, par portée de fonction.
  const decls = new Map();   // scopeNode -> Map(nom -> start)
  walk.ancestor(bloc.ast, {
    VariableDeclaration(n, _st, anc) {
      if (n.kind === 'var') return;
      const scope = [...anc].reverse().find(a => a.type === 'Program' || EST_FN(a.type));
      if (!scope) return;
      if (!decls.has(scope)) decls.set(scope, new Map());
      const noms = []; n.declarations.forEach(d => nomsDuMotif(d.id, noms));
      noms.forEach(nm => { if (!decls.get(scope).has(nm)) decls.get(scope).set(nm, n.start); });
    },
  });

  walk.ancestor(bloc.ast, {
    Identifier(n, _st, anc) {
      const parent = anc[anc.length - 2];
      if (!parent) return;
      if (parent.type === 'MemberExpression' && parent.property === n && !parent.computed) return;
      if (parent.type === 'Property' && parent.key === n && !parent.computed) return;
      if (parent.type === 'VariableDeclarator' && parent.id === n) return;

      // Trouver la portée qui déclare ce nom.
      let iScope = -1, tardive = false;
      for (let i = anc.length - 1; i >= 0; i--) {
        const a = anc[i];
        if (a.type !== 'Program' && !EST_FN(a.type)) continue;
        const d = decls.get(a);
        if (d && d.has(n.name)) { iScope = i; tardive = n.start < d.get(n.name); break; }
        if (portéeDeGlobale(a).has(n.name)) return;   // déclaré autrement ici
      }
      if (iScope < 0 || !tardive) return;

      // La lecture s'exécute-t-elle vraiment avant la déclaration ? Il faut que
      // CHAQUE frontière de fonction franchie jusqu'à cette portée soit un
      // rappel passé directement en argument — donc exécuté sur place. Une
      // fonction affectée à un nom (`R.x = () => …`) est appelée bien plus tard :
      // elle lit alors un `const` de toute façon initialisé, et c'est le motif
      // le plus courant du fichier.
      for (let i = anc.length - 2; i > iScope; i--) {
        const a = anc[i];
        if (!EST_FN(a.type)) continue;
        const sup = anc[i - 1];
        if (!(sup && sup.type === 'CallExpression' && sup.arguments.includes(a))) return;
        // Un rappel passé en argument n'est pas forcément exécuté sur place :
        // `addEventListener`, `setTimeout`, `.then` le gardent pour plus tard.
        // Seules les méthodes d'itération le sont à coup sûr — d'où une liste
        // fermée plutôt qu'une exclusion, toujours incomplète.
        const c = sup.callee;
        const nom = c && c.type === 'MemberExpression' && !c.computed &&
                    c.property.type === 'Identifier' ? c.property.name : null;
        if (!SYNCHRONES.has(nom)) return;
      }
      zonesMortes.push({ nom: n.name, ligne: bloc.ligne0 + n.loc.start.line - 1 });
    },
  });
}
console.log('═══ UN NOM LU HORS DE SA PORTÉE ═══');
console.log(`    ${refs} références examinées dans ${blocs.length} blocs <script>\n`);

// Regrouper : le même nom manquant, plusieurs fois, est une seule faute.
const parNom = new Map();
for (const t of trouvés) {
  if (!parNom.has(t.nom)) parNom.set(t.nom, []);
  parNom.get(t.nom).push(t.ligne);
}
for (const [nom, lignes] of [...parNom].sort((a, b) => a[1][0] - b[1][0])) {
  console.log(`  ✗ ${nom.padEnd(28)} ligne${lignes.length > 1 ? 's' : ''} ${lignes.join(', ')}`);
}
console.log(trouvés.length
  ? `\n✗ ${parNom.size} nom(s) introuvable(s) — ${trouvés.length} lecture(s)`
  : '\n✓ Tout nom lu est déclaré dans une portée englobante');

console.log('\n═══ UN NOM LU AVANT SA PROPRE DÉCLARATION ═══');
for (const z of zonesMortes) console.log(`  ✗ ${z.nom.padEnd(28)} ligne ${z.ligne}`);
console.log(zonesMortes.length
  ? `\n✗ ${zonesMortes.length} lecture(s) en zone morte temporelle`
  : '✓ Aucune lecture avant sa déclaration');

process.exit(trouvés.length + zonesMortes.length ? 1 : 0);
