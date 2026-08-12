// ══════════════════════════════════════════════════════════════════════════
//  recette-presence-personnel.mjs — le registre de présence du personnel
//
//  Loms, 12 août 2026, trois décisions :
//    · la feuille du jour est tenue par la Direction ET chacun se déclare ;
//    · elle couvre TOUT le personnel, pas seulement les enseignants ;
//    · les absences alimentent la paie sous forme d'une retenue PROPOSÉE.
//
//  Ce que cette recette tient, ce sont les trois règles qui peuvent coûter
//  cher si elles cèdent en silence :
//
//   1. Une écriture refusée par le serveur n'est JAMAIS annoncée comme un
//      succès. C'est la faute exacte qu'on a trouvée en inspectant : la RLS
//      n'ouvre `teacher_absences` qu'à Direction 1, l'enseignant lisait
//      « ✅ Absence signalée », et rien n'était enregistré.
//   2. La retenue ne porte QUE sur les jours explicitement refusés. Un jour
//      « en attente » n'est pas un jour injustifié : c'est un jour sur lequel
//      personne ne s'est prononcé. Retenir dessus, ce serait juger avant
//      d'avoir décidé.
//   3. Rien ne s'applique tout seul sur un salaire. Le montant est proposé,
//      affiché avec son calcul, et il faut un geste pour l'inscrire.
//
//  Le calcul est EXÉCUTÉ, pas relu : les fonctions sont extraites du vrai
//  fichier et lancées sur des cas construits.
//
//    node tools/recette-presence-personnel.mjs
//    node tools/recette-presence-personnel.mjs --preuve
// ══════════════════════════════════════════════════════════════════════════
import fs from 'node:fs';
import vm from 'node:vm';

const preuve = process.argv.includes('--preuve');
let h = fs.readFileSync('dist/index.html', 'utf8');

// ── LA PREUVE ────────────────────────────────────────────────────────────
// Quatre défauts réinjectés dans la vraie source : le succès annoncé sur un
// refus, la retenue qui mord sur les jours en attente, l'application
// automatique sans geste, et la table retirée du chargement de Direction 2.
if (preuve) {
  h = h.replace("  const ok = await pushSync('teacher_absences','post',entry);\n  if(!ok && window.DB_ONLINE){",
                "  const ok = await pushSync('teacher_absences','post',entry);\n  if(false){");
  // Le défaut à revoir : la retenue mord sur les jours EN ATTENTE, c'est-à-dire
  // sur des absences que la Direction n'a pas encore tranchées.
  h = h.replace('const { refused } = window._bilanAbsences(uid, mois);',
                'const { refused: _r, pending: _p } = window._bilanAbsences(uid, mois); const refused = _r + _p;');
  h = h.replace('onclick="window._appliquerRetenue(', 'data-auto="1" onclick="window._appliquerRetenue(');
  h = h.replace("      personnel:      ['teacher_absences',\n", "      personnel:      [\n");
}

const pts = [];
const ok = (nom, cond) => { pts.push({ nom, ok: !!cond }); };

// ── 1. L'ÉCRITURE REFUSÉE N'EST PAS UN SUCCÈS ────────────────────────────
const blocDecl = (h.match(/window\.saveTeacherAbsence = async \(\) => \{[\s\S]*?\n\};/) || [''])[0];
ok('la déclaration attend la réponse du serveur', /const ok = await pushSync\('teacher_absences','post',entry\)/.test(blocDecl));
ok('un refus serveur retire la ligne affichée',
   /if\(!ok && window\.DB_ONLINE\)\{[\s\S]*?DB\.teacher_absences=DB\.teacher_absences\.filter/.test(blocDecl));
ok('un refus serveur est annoncé comme un refus',
   /Le serveur a refusé la déclaration/.test(blocDecl));
ok('le refus dit POURQUOI', /_writeErrorLabel\(e\)/.test(blocDecl));
ok('hors ligne ≠ refus — le ton change', /Absence retenue sur l'appareil/.test(blocDecl));
ok('la décision Direction se retire aussi si le serveur refuse',
   /a\.status = avant\.status; a\.approved_by = avant\.approved_by;/.test(h));
ok('consigner pour autrui se retire aussi si le serveur refuse',
   /rien n’a été consigné/.test(h));

// ── 2. TOUT LE PERSONNEL, PAS SEULEMENT LES ENSEIGNANTS ──────────────────
ok('tout le personnel peut se déclarer',
   /_denyRole\('enseignant','gardien','direction2','direction3','direction'\)/.test(h));
ok('le registre couvre la même population que la paie',
   /window\._personnelRegistre = \(\) => window\._personnelPaye\(\)/.test(h));
for (const [role, motif] of [['gardien','gardien'], ['direction2','Direction 2'], ['direction3','Caisse']]) {
  ok(`« Mes absences » est au menu — ${motif}`,
     new RegExp(`${role}:[\\s\\S]{0,4200}?id:'mes_absences'`).test(h));
}
ok('Direction 2 charge enfin `teacher_absences`',
   /personnel:      \['teacher_absences',\n\s+_T\('salaries'/.test(h));
ok('le gardien relit ce qu’il a déclaré',
   /_T\('teacher_absences', \(\) => 'select=\*&uid=eq\.'/.test(h));

// ── 3. LE CALCUL, EXÉCUTÉ ────────────────────────────────────────────────
const prendre = (nom) => {
  const i = h.indexOf(`window.${nom} =`);
  if (i < 0) return null;
  const fin = h.indexOf('\n};', i);
  return fin < 0 ? null : h.slice(i, fin + 3);
};
const sources = ['_statutAbsence', '_absencesDuMois', '_joursOuvrablesMois', '_bilanAbsences', '_retenueProposee']
  .map(prendre);
ok('les fonctions de calcul sont extractibles', sources.every(Boolean));

if (sources.every(Boolean)) {
  const ABS = [
    { uid:'u1', date:'2026-08-03', status:'refused'  },
    { uid:'u1', date:'2026-08-04', status:'refused'  },
    { uid:'u1', date:'2026-08-05', status:'pending'  },
    { uid:'u1', date:'2026-08-06', status:'approved' },
    { uid:'u1', date:'2026-07-30', status:'refused'  },   // autre mois
    { uid:'u2', date:'2026-08-03', status:'refused'  },   // autre personne
    { uid:'u1', date:'2026-08-07'                    },   // ligne ancienne, sans statut
  ];
  const ctx = { window:{}, DB:{ teacher_absences:ABS, settings:{} } };
  ctx.globalThis = ctx; vm.createContext(ctx);
  new vm.Script(sources.join('\n')).runInContext(ctx);
  const W = ctx.window;

  ok('une ligne sans statut est lue « en attente », jamais « justifiée »',
     W._statutAbsence({}) === 'pending' && W._statutAbsence({status:'approved'}) === 'approved');

  const b = W._bilanAbsences('u1', '2026-08');
  ok('le bilan ne mélange ni les mois ni les personnes', b.total === 5);
  ok('le bilan sépare les trois états',
     b.refused === 2 && b.pending === 2 && b.approved === 1);

  // 260 / 26 = 10 par jour ; 2 jours non justifiés = 20.
  ok('la retenue porte sur les jours NON JUSTIFIÉS', W._retenueProposee('u1','2026-08',260) === 20);
  ok('les jours EN ATTENTE ne sont jamais retenus', W._retenueProposee('u1','2026-08',260) !== 40);
  ok('les jours JUSTIFIÉS ne sont jamais retenus', W._retenueProposee('u1','2026-08',260) !== 30);
  ok('sans salaire de base, aucune retenue n’est inventée', W._retenueProposee('u1','2026-08',0) === 0);
  ok('sans absence refusée, la retenue est nulle', W._retenueProposee('u2','2026-09',260) === 0);

  ctx.DB.settings.jours_ouvrables_mois = 20;   // 260/20 = 13 ; ×2 = 26
  ok('les jours ouvrables sont un réglage, pas une constante',
     W._joursOuvrablesMois() === 20 && W._retenueProposee('u1','2026-08',260) === 26);
}

// ── 4. RIEN NE S'APPLIQUE TOUT SEUL SUR UN SALAIRE ───────────────────────
ok('la retenue est PROPOSÉE, pas posée', /Retenue proposée :/.test(h));
ok('il faut un geste pour l’inscrire',
   /onclick="window\._appliquerRetenue\('\$\{champId\}',\$\{prop\}\)"/.test(h));
ok('aucune application automatique n’est câblée', !/data-auto="1"/.test(h));
ok('le calcul est montré en clair, pas seulement son résultat',
   /÷ \$\{jo\} j × \$\{b\.refused\}/.test(h));
ok('la fiche de paie du personnel affiche le bloc',
   /\$\{window\._blocAbsencesPaie\(teacherId, month, sal\.amount\|\|0, 'sal_deductions'\)\}/.test(h));
ok('le montant reste corrigeable après report', /vous pouvez encore la corriger/.test(h));

// ── 5. CE QUI DÉPEND DU SERVEUR EST DIT, PAS MAQUILLÉ ────────────────────
ok('un registre non autorisé le dit au lieu de paraître complet',
   /ce n’est pas une école au complet/.test(h));
ok('le refus de lecture est détecté sur la vraie table',
   /window\._readState\.teacher_absences === 'forbidden'/.test(h));
ok('seule la Direction tranche', /window\._trancherAbsence = async \(id, decision\) => \{\n\s+if \(_denyRole\('direction'\)\) return;/.test(h));
ok('le registre est réservé à Direction 1 et 2',
   /window\._requireRole\('direction','direction2'\)/.test(h));

// ── 6. LE DOCUMENT ───────────────────────────────────────────────────────
ok('le registre imprimé existe', /window\.printRegistrePresence = \(mois\) => \{/.test(h));
ok('il prend la charte des documents Finance/RH', /<style>\$\{window\._CSS_DOC\}<\/style>[\s\S]{0,900}?REGISTRE DE PRÉSENCE DU PERSONNEL/.test(h));
ok('il porte la chaîne de responsabilité officielle',
   /\$\{_enteteOfficiel\(\)\}[\s\S]{0,400}?REGISTRE DE PRÉSENCE DU PERSONNEL/.test(h));
ok('il se signe', /REGISTRE DE PRÉSENCE[\s\S]{0,4000}?_officialFooter\(/.test(h));
ok('il explique ce qui donne lieu à retenue et ce qui n’y donne pas',
   /seuls les jours portés « non justifiés » donnent lieu à une retenue/.test(h));

for (const p of pts) console.log(`${p.ok ? '✓' : '✗'} ${p.nom}`);
const ratés = pts.filter(p => !p.ok);
console.log(ratés.length ? `\n✗ ${ratés.length} point(s) sur ${pts.length} en échec`
                         : `\n✓ les ${pts.length} points passent`);
process.exit(ratés.length ? 1 : 0);
