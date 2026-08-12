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

const okCount = checks.filter(c => c.ok).length;
for (const c of checks) console.log(`${c.ok ? 'OK' : 'FAIL'} — ${c.name}`);
console.log(`\n${okCount}/${checks.length} contrôles réussis.`);
if (process.exitCode) process.exit(process.exitCode);
