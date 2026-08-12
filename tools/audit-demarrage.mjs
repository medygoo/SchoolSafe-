// ══════════════════════════════════════════════════════════════════════════
//  AUDIT — CE QUI RETARDE L'OUVERTURE DE L'APPLICATION
//
//  Loms, 11 août 2026 : « l'application prend du temps à l'ouverture ».
//  Mesuré, pas deviné. Quatre causes trouvées, et cet outil les tient.
//
//  1. Le service worker attendait le réseau AVANT d'afficher quoi que ce soit.
//     Trois stratégies s'étaient succédé, chacune corrigeant la précédente en
//     cassant autre chose ; la dernière bornait l'attente à 4 s, donc sur un
//     réseau de Kinshasa **les 4 secondes s'écoulaient en entier à chaque
//     ouverture** — pendant qu'une version utilisable dormait dans le cache.
//     La fraîcheur et l'attente étaient traitées comme un seul curseur ; ce
//     sont deux problèmes. On sert le cache tout de suite, on va chercher la
//     nouvelle version derrière, et **on le dit**.
//
//  2. Six bibliothèques extérieures chargées SANS `defer` : l'analyse du
//     document s'arrêtait à chaque balise, le temps d'un aller-retour CDN,
//     avant même que la première ligne de SchoolSafe soit lue.
//
//  3. JSZip téléchargée à chaque démarrage — **zéro appel** dans tout le
//     fichier.
//
//  4. Un commentaire annonçait un splash « auto après 1.5s » qu'aucune
//     minuterie n'a jamais fait.
//
//  Éprouvé dans les deux sens : `--preuve` remet les défauts et vérifie que
//  l'outil les revoit.
// ══════════════════════════════════════════════════════════════════════════
import { readFileSync } from 'node:fs';

const RACINE = new URL('../dist/', import.meta.url);
let html = readFileSync(process.env.SS_HTML || new URL('index.html', RACINE), 'utf8');
let sw   = readFileSync(new URL('sw.js', RACINE), 'utf8');
const PREUVE = process.argv.includes('--preuve');

if (PREUVE) {
  // L'ORDRE COMPTE : réinjecter JSZip AVANT de retirer les `defer`, sinon
  // l'ancre a déjà changé et la bibliothèque morte ne revient jamais. Une
  // preuve qui se sabote elle-même ne prouve rien.
  html = html.replace('<script defer src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>',
    '<script defer src="https://cdnjs.cloudflare.com/ajax/libs/qrcodejs/1.0.0/qrcode.min.js"></script>\n'
    + '<script src="https://cdnjs.cloudflare.com/ajax/libs/jszip/3.10.1/jszip.min.js"></script>');
  html = html.replace(/<script defer src=/g, '<script src=');
  sw = sw.replace('if (cached) { evt.waitUntil(reseau); return cached; }',
                  'if (cached) { return (await reseau) || cached; }');
}

// Les commentaires expliquent souvent le défaut RETIRÉ : les compter
// reviendrait à échouer sur la note qui documente la correction. Ce piège
// s'est déjà refermé trois fois dans ce dépôt.
const sansCommentaires = (src) => src
  .split('\n').map(l => l.replace(/^\s*\/\/.*$/, '')).join('\n')
  .replace(/<!--[\s\S]*?-->/g, '')
  // ⚠️ Le `/*` doit être en DÉBUT DE LIGNE. Sans cette ancre, `accept="image/*"`
  // — un attribut HTML parfaitement normal — ouvre un faux commentaire CSS que
  // le premier `*/` venu referme : mesuré, **351 Ko avalés d'un coup**, dont la
  // seule ligne qui emploie `jsQR`. L'outil déclarait alors « bibliothèque
  // téléchargée sans être appelée » sur une bibliothèque parfaitement utilisée.
  // Un nettoyeur qui ne comprend pas le contexte n'omet pas : il INVENTE.
  .replace(/^[ \t]*\/\*[\s\S]*?\*\//gm, '');

const codeHtml = sansCommentaires(html);
const codeSw   = sansCommentaires(sw);

const R = []; const ok = (q, v, d = '') => R.push({ q, v: !!v, d });

// ── 1 · AUCUN SCRIPT EXTÉRIEUR NE BLOQUE L'AFFICHAGE ──────────────────────
const _lignesHtml = codeHtml.split('\n');
const _ligneDe = (i) => codeHtml.slice(0, i).split('\n').length - 1;
const balises = [...codeHtml.matchAll(/<script\b[^>]*\bsrc="(https?:\/\/[^"]+)"[^>]*>/g)]
  // Les DOCUMENTS imprimés embarquent leur propre <script src> dans un
  // littéral de gabarit, refermé par `<\\/script>`. Ce n'est pas le chargement
  // de l'application : les compter ferait échouer l'outil sur du code qui
  // n'ouvre aucun écran. C'est la frontière de ce qu'il regarde, et elle est
  // écrite dans sa sortie.
  .filter(m => !/<\\\/script>/.test(_lignesHtml[_ligneDe(m.index)] || ''));
const bloquantes = balises.filter(m => !/\bdefer\b|\basync\b/.test(m[0]));
ok('aucune bibliothèque extérieure ne bloque l’affichage',
   bloquantes.length === 0,
   bloquantes.map(m => m[1].split('/').pop()).join(', '));
ok('les bibliothèques extérieures sont toujours là — on n’a rien cassé',
   balises.length >= 4, balises.length + ' balise(s)');

// ── 2 · AUCUNE BIBLIOTHÈQUE TÉLÉCHARGÉE POUR PERSONNE ─────────────────────
// La bonne question n'est pas « est-elle chargée ? » mais « quelqu'un
// l'appelle-t-il ? ». Un audit qui liste sans vérifier l'usage invente.
const GLOBALES = { 'qrcode.min.js':'QRCode', 'jsQR.min.js':'jsQR', 'jszip.min.js':'JSZip',
  'html2pdf.bundle.min.js':'html2pdf', 'html2canvas.min.js':'html2canvas',
  'supabase.js':'supabase' };
const orphelines = [];
for (const m of balises) {
  const fichier = m[1].split('/').pop();
  const g = GLOBALES[fichier];
  if (!g) continue;
  // on cherche l'emploi HORS des balises de chargement elles-mêmes
  const emplois = (codeHtml.replace(/<script\b[^>]*\bsrc="[^"]*"[^>]*>\s*<\/script>/g, '')
    .match(new RegExp('\\b' + g + '\\b', 'g')) || []).length;
  if (emplois === 0) orphelines.push(fichier);
}
ok('aucune bibliothèque n’est téléchargée sans être appelée',
   orphelines.length === 0, orphelines.join(', '));

// ── 3 · LE SERVICE WORKER SERT LE CACHE SANS FAIRE ATTENDRE ───────────────
ok('le service worker répond avec le cache SANS attendre le réseau',
   /if\s*\(cached\)\s*\{\s*evt\.waitUntil\(reseau\)\s*;\s*return cached\s*;/.test(codeSw),
   'la réponse attend encore le réseau');
ok('et la requête réseau continue derrière — la fraîcheur n’est pas perdue',
   /evt\.waitUntil\(reseau\)/.test(codeSw));
ok('plus aucune attente bornée avant d’afficher',
   !/Promise\.race/.test(codeSw) && !/4000/.test(codeSw));
ok('le premier chargement, lui, attend bien le réseau',
   /return \(await reseau\)/.test(codeSw));

// ── 4 · UNE MISE À JOUR NE SE FAIT PAS EN SILENCE ─────────────────────────
// C'est le défaut du Stale-While-Revalidate d'origine : il servait le cache
// ET se taisait. Servir le cache est juste ; se taire ne l'est pas.
ok('le service worker PRÉVIENT quand une nouvelle version est là',
   /SS_MAJ_DISPONIBLE/.test(codeSw) && /postMessage/.test(codeSw));
ok('il ne prévient que si la version a VRAIMENT changé',
   /_aChange\s*\(/.test(codeSw) && /etag/.test(codeSw));
ok('et il ne prétend pas savoir quand aucun repère n’est disponible',
   /return false;/.test(codeSw.slice(codeSw.indexOf('async function _aChange'),
                                     codeSw.indexOf('async function _prevenirLesPages'))));
ok('l’écran écoute ce signal et le montre',
   /SS_MAJ_DISPONIBLE/.test(codeHtml) && /ss-maj/.test(codeHtml));
ok('il PROPOSE de recharger, il ne le fait jamais tout seul',
   /ss-maj-oui/.test(codeHtml) && /ss-maj-non/.test(codeHtml),
   'un rechargement automatique interromprait un scan au portail');

// ── 5 · CE QUE L'OUTIL NE SAIT PAS VOIR, IL LE DIT ────────────────────────
const poids = Buffer.byteLength(html) / 1024;
ok('le poids de l’interface est connu et annoncé', poids > 0, '');

// ── Verdict ───────────────────────────────────────────────────────────────
console.log('\n═══ AUDIT — L’OUVERTURE DE L’APPLICATION ═══\n');
for (const r of R) console.log(`  ${r.v ? '✓' : '✗'} ${r.q}${r.v ? '' : '   → ' + r.d}`);

console.log(`\n  Mesuré : index.html = ${poids.toFixed(0)} Ko · ${balises.length} bibliothèques extérieures au démarrage`);
console.log('  (les <script src> des documents imprimés sont hors du champ de cet outil)');
console.log('  CE QUE CET OUTIL NE PEUT PAS VOIR, et qui compte :');
console.log('    · le poids réel des bibliothèques CDN — pas d’accès sortant ici ;');
console.log('    · le temps d’ouverture sur un vrai téléphone, sur un vrai réseau ;');
console.log('    · le coût d’analyse des 33 000 lignes de l’interface.');
console.log('    Seule une mesure sur l’appareil de l’école tranchera.');

const ko = R.filter(r => !r.v);
if (PREUVE) {
  const bloque = R.find(r => /ne bloque l’affichage/.test(r.q));
  const morte  = R.find(r => /sans être appelée/.test(r.q));
  const attend = R.find(r => /SANS attendre le réseau/.test(r.q));
  const vus = [['les scripts bloquants', bloque], ['la bibliothèque morte', morte],
               ['l’attente du réseau', attend]].filter(([, r]) => r && !r.v).map(([n]) => n);
  if (vus.length === 3) {
    console.log('\n✔ PREUVE TENUE — les trois défauts réinjectés sont revus :');
    console.log('  ' + vus.join(' · ') + '\n');
    process.exit(0);
  }
  console.log('\n✗ PREUVE MANQUÉE — seuls ' + vus.length + '/3 revus (' + (vus.join(', ') || 'aucun') + ').\n');
  process.exit(1);
}
console.log(`\n${ko.length ? '✗ ' + ko.length + ' sur ' + R.length + ' en échec'
                           : '✓ les ' + R.length + ' points passent'}\n`);
process.exit(ko.length ? 1 : 0);
