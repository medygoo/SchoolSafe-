import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const cssPath = path.join(root, 'prototypes', '03-v3-harmonisation.css');
const htmlPath = path.join(root, 'prototypes', '03-v3-harmonisation.html');

function fail(msg) {
  console.error(`FAIL: ${msg}`);
  process.exitCode = 1;
}

if (!fs.existsSync(cssPath)) fail('la feuille CSS V3 doit exister');
if (!fs.existsSync(htmlPath)) fail('le wrapper de prévisualisation V3 doit exister');

if (fs.existsSync(cssPath)) {
  const css = fs.readFileSync(cssPath, 'utf8');
  const protectedTerms = ['.splash-screen', '.login-screen', '.login-container', '.login-bg', 'login-kid', 'LH_IMG', '_LH_PHOTOS'];
  for (const term of protectedTerms) {
    if (css.includes(term)) fail(`la CSS V3 ne doit pas cibler ${term}`);
  }

  if (!css.includes('.app {')) fail('la palette principale doit être scoped à .app');
  if (!css.includes('.dark .app {')) fail('la palette sombre doit rester scoped à .app');
  if (!css.includes('body[data-role="direction"] .app')) fail('les accents de rôle doivent être scoped à .app');

  const bannedProps = /(^|[;{]\s*)(transform|animation|transition|width|height|padding|margin|display|position|grid-template|flex|border-radius)\s*:/gm;
  const matches = [...css.matchAll(bannedProps)].map(m => m[2]);
  if (matches.length) {
    fail(`la passe couleur ne doit pas changer la géométrie/mouvement: ${[...new Set(matches)].join(', ')}`);
  }
}

if (fs.existsSync(htmlPath)) {
  const html = fs.readFileSync(htmlPath, 'utf8');
  if (!html.includes('../dist/index.html')) fail('le wrapper doit charger exactement l’application existante dist/index.html');
  if (!html.includes('03-v3-harmonisation.css')) fail('le wrapper doit injecter uniquement la feuille V3');
  if (!html.includes("addEventListener('load'")) fail('le wrapper doit attendre le chargement de l’application avant injection');
}

if (!process.exitCode) console.log('PASS: garde-fous V3 respectés');
