import fs from 'node:fs';
import vm from 'node:vm';

const indexPath = 'dist/index.html';
const patchPath = 'dist/messages-frontend-v2.js';

const index = fs.readFileSync(indexPath, 'utf8');
const patch = fs.readFileSync(patchPath, 'utf8');
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

try {
  new vm.Script(patch, { filename: patchPath });
  check('syntaxe JavaScript valide', true);
} catch (e) {
  check(`syntaxe JavaScript valide (${e.message})`, false);
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
