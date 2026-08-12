// ══════════════════════════════════════════════════════════════════════════
//  LE 12 AOÛT, LA MESSAGERIE A CHANGÉ DE FICHIER — ET L'OUTIL NE L'A PAS SU
//
//  Cet outil lisait `dist/messages-frontend-v2.js` et y cherchait la
//  messagerie. Le 12 août au matin, ce fichier a été scindé en deux : le
//  bootstrap d'authentification est resté sous ce nom, et la messagerie —
//  conservée octet pour octet — est partie dans
//  `messages-frontend-v2-core.js`. L'outil a alors annoncé 17 pannes sur 20.
//
//  Aucune des dix-sept n'existait. La messagerie était intacte ; c'est l'outil
//  qui regardait au mauvais endroit. Un contrôle qui nomme un fichier en dur
//  ne contrôle pas une fonction, il contrôle un chemin — et le jour où le
//  chemin bouge, il crie au feu dans une maison qui n'a rien.
//
//  Corrigé, et la chaîne de chargement est désormais vérifiée elle aussi :
//  index.html → bootstrap → core. Elle a maintenant un maillon de plus, et ce
//  maillon échoue en silence (un `console.warn`). Un maillon qui se casse sans
//  bruit doit être tenu par le filet, sinon la messagerie peut disparaître de
//  l'école sans qu'une seule ligne ne le dise.
//
//    node tools/recette-messages-v2.mjs            — la recette
//    node tools/recette-messages-v2.mjs --preuve   — la recette se prouve
// ══════════════════════════════════════════════════════════════════════════
import fs from 'node:fs';
import vm from 'node:vm';

const indexPath = 'dist/index.html';
const bootPath  = 'dist/messages-frontend-v2.js';       // bootstrap Auth + chargeur
const corePath  = 'dist/messages-frontend-v2-core.js';  // la messagerie elle-même

const preuve = process.argv.includes('--preuve');

const index = fs.readFileSync(indexPath, 'utf8');
let boot = fs.readFileSync(bootPath, 'utf8');
let patch = fs.readFileSync(corePath, 'utf8');

// ── LA PREUVE ────────────────────────────────────────────────────────────
// Une vérification qui ne sait dire que « oui » ne vérifie rien. On réinjecte
// dans la vraie source les deux défauts que cet outil existe pour voir : la
// messagerie amputée, et le maillon de chargement coupé. S'il ne les voit
// pas, c'est l'outil qui est en panne, pas l'application.
if (preuve) {
  // Le sabotage doit VRAIMENT effacer le motif cherché. Un premier essai
  // ajoutait un suffixe — `openForwardParentMessageXX` contient encore
  // `openForwardParentMessage`, et le contrôle passait sur une messagerie
  // pourtant amputée. On préfixe donc, ce qui ne laisse rien à trouver.
  patch = patch.replace(/openForwardParentMessage/g, 'XXForwardParentMessage');
  boot  = boot.replace("messages-frontend-v2-core.js?v=20260812-core1", 'nexiste-pas.js');
}

const tag = '<script src="messages-frontend-v2.js?v=20260812" defer></script>';

const checks = [];
const check = (name, ok) => {
  checks.push({ name, ok: !!ok });
  if (!ok) process.exitCode = 1;
};

check('loader présent exactement une fois', index.split(tag).length - 1 === 1);
const tagPos = index.lastIndexOf(tag);
const bodyPos = index.lastIndexOf('</body>');
check('loader placé avant le vrai </body> final', tagPos >= 0 && bodyPos > tagPos && bodyPos - tagPos < 200);

// ── LA CHAÎNE DE CHARGEMENT, MAILLON PAR MAILLON ─────────────────────────
check('la messagerie existe sous son propre nom', fs.existsSync(corePath));
const srcCore = (boot.match(/['"](messages-frontend-v2-core\.js[^'"]*)['"]/) || [])[1] || '';
check('le bootstrap charge bien le fichier de messagerie', srcCore.startsWith('messages-frontend-v2-core.js'));
check('le fichier chargé est celui qui existe sur le disque',
      srcCore ? fs.existsSync('dist/' + srcCore.split('?')[0]) : false);
check('le bootstrap crée le client Auth que index.html n’a pas pu créer',
      boot.includes('window._authClient = client'));

for (const [nom, fichier, texte] of [['bootstrap', bootPath, boot], ['messagerie', corePath, patch]]) {
  try {
    new vm.Script(texte, { filename: fichier });
    check(`syntaxe JavaScript valide — ${nom}`, true);
  } catch (e) {
    check(`syntaxe JavaScript valide — ${nom} (${e.message})`, false);
  }
}

const needles = [
  ['ancien parent_direct redirigé', "mode === 'parent_direct'"],
  ['nouveau chemin parent_to_dir', "mode === 'parent_to_dir'"],
  ['routage Direction → enseignant', 'openForwardParentMessage'],
  ['envoi Direction → enseignant', 'sendForwardParentMessage'],
  ['routage réponse enseignant → parent', 'openRelayTeacherMessage'],
  ['envoi réponse Direction → parent', 'sendRelayTeacherMessage'],
  ['archives accessibles', 'openArchivedMessages'],
  ['lecture individuelle locale préparée', 'ss_msg_read_v2_'],
  ['archives individuelles locales préparées', 'ss_msg_archived_v2_'],
  ['chiffrement sujet conservé', '_encryptMsgField(msg.subject)'],
  ['chiffrement corps conservé', '_encryptMsgField(msg.body)'],
  ['enseignant/autres rôles délèguent au composer existant', 'return original.openComposeMsg()'],
  ['modes non V2 délèguent à sendMsg existant', 'return original.sendMsg(mode)'],
];

for (const [name, needle] of needles) check(name, patch.includes(needle));

// ── AJOUT CLAUDE, 12 août 2026 — L'HONNÊTETÉ DE L'ENVOI ───────────────────
// `pushSync` MET EN FILE, il ne confirme rien. Les quatre annonces disaient
// « Message envoyé » sans le savoir : hors ligne, le parent croyait que la
// Direction avait reçu sa demande alors que rien n'était parti. C'est la leçon
// déjà écrite deux fois dans ce dépôt — l'écran ne dit pas « envoyé » quand la
// file dit « en attente ». Corrigé, et gardé ici.
check('l’état réel de l’envoi est relevé après la mise en file',
      patch.includes('dernierEnvoiEnFile'));
check('les annonces le lisent au lieu d’affirmer',
      (patch.match(/enFile\(\)/g) || []).length >= 8);
check('hors ligne, aucune annonce ne dit « envoyé »',
      !/toast\('Message envoyé à la Direction 1 \/ Direction 2', 'success'\)/.test(patch)
      && patch.includes('dès le retour du réseau'));
check('et le ton change aussi — un envoi différé n’est pas un succès',
      patch.includes("enFile() ? 'warning' : 'success'"));

const okCount = checks.filter(c => c.ok).length;
for (const c of checks) console.log(`${c.ok ? 'OK' : 'FAIL'} — ${c.name}`);
console.log(`\n${okCount}/${checks.length} contrôles réussis.`);
if (process.exitCode) process.exit(process.exitCode);
