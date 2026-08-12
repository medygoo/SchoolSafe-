// ══════════════════════════════════════════════════════════════════════════
//  recette-import-listes.mjs — importer des élèves, et savoir qui les entoure
//
//  Loms, 12 août 2026 : « pour importer les élèves ça doit être par classe et
//  pour toute l'école, et une liste avec les élèves et tous les tuteurs ».
//
//  Le défaut trouvé en chemin est le plus grave des deux : l'encadré de
//  l'import promettait « La classe et le parent doivent exister ou seront
//  créés », et le code ne créait AUCUNE classe. Un fichier dont la classe
//  était mal orthographiée importait les élèves avec `cid:null`, en silence,
//  en annonçant « ✅ 40 élève(s) importé(s) ». Ces élèves sortaient de tout
//  classement, de tout bulletin, de toute liste — et personne ne s'en
//  apercevait avant des semaines.
//
//  Ce que cette recette tient :
//    · un élève n'atterrit JAMAIS sans classe par accident ;
//    · ce qui est refusé est COMPTÉ et DIT, pas tu ;
//    · la liste des tuteurs nomme tout l'entourage, pas seulement le compte
//      parent — parce qu'on la lit le jour où il faut joindre quelqu'un.
//
//    node tools/recette-import-listes.mjs
//    node tools/recette-import-listes.mjs --preuve
// ══════════════════════════════════════════════════════════════════════════
import fs from 'node:fs';
import vm from 'node:vm';

const preuve = process.argv.includes('--preuve');
let h = fs.readFileSync('dist/index.html', 'utf8');

// ── LA PREUVE ────────────────────────────────────────────────────────────
// On réinjecte le défaut historique — la classe introuvable devient `null`
// au lieu de refuser la ligne — plus trois autres régressions plausibles.
if (preuve) {
  h = h.replace('      if(!nom){ refusesClasse++; return; }', '      if(!nom){ cl={id:null}; }');
  h = h.replace('        if(!creer){ refusesClasse++; return; }', '        if(!creer){ cl={id:null}; }');
  h = h.replace("  if(refusesClasse) dits.push(`${refusesClasse} refusé(s) — classe inconnue ou absente`);", '');
  h = h.replace("  (DB.aps||[]).filter(a => a.sid === s.id && a.active !== false)\n    .forEach(a => l.push({ q:a.relation || 'Personne autorisée', n:a.name, t:a.phone || '' }));", '');
}

const pts = [];
const ok = (nom, cond) => { pts.push({ nom, ok: !!cond }); };

// ── 1. IMPORTER PAR CLASSE, OU POUR TOUTE L'ÉCOLE ────────────────────────
ok('la portée de l’import se choisit', /<select class="form-input" id="csv_cid"/.test(h));
ok('« toute l’école » reste possible', /Toute l’école — la classe est écrite dans le fichier/.test(h));
ok('chaque classe existante est proposée',
   /\(DB\.classes\|\|\[\]\)\.map\(c => `<option value="\$\{c\.id\}">\$\{esc\(c\.name\)\}<\/option>`\)/.test(h));
ok('changer de classe cible refait l’aperçu', /window\._csvRelire = \(\) => \{/.test(h));
ok('l’import est réservé à la Direction',
   /window\.openImportCSV = \(\) => \{\n\s+if \(_denyRole\('direction','direction2'\)\) return;/.test(h));

// ── 2. AUCUN ÉLÈVE SANS CLASSE PAR ACCIDENT ──────────────────────────────
const blocImport = (h.match(/window\.importCSVConfirm = \(\) => \{[\s\S]*?\n\};/) || [''])[0];
ok('une ligne sans classe est refusée, pas importée',
   /if\(!nom\)\{ refusesClasse\+\+; return; \}/.test(blocImport));
ok('une classe inconnue non demandée est refusée',
   /if\(!creer\)\{ refusesClasse\+\+; return; \}/.test(blocImport));
ok('la classe créée l’est parce qu’on l’a demandé',
   /if\(!creer\)[\s\S]{0,120}?cl=\{id:_uid\('c_'\),name:nom,cycle:'primaire'\}/.test(blocImport));
ok('la création d’une classe par import laisse une trace',
   /logAudit\('classe_creee_import'/.test(blocImport));
ok('l’élève reçoit une classe RÉELLE, jamais `null`',
   /cid:cl\.id,/.test(blocImport) && !/cid:cl\?\.id\|\|null/.test(blocImport));
ok('les refus sont comptés', /let added=0,skipped=0,refusesClasse=0;/.test(blocImport));
ok('les refus sont DITS à l’écran', /refusé\(s\) — classe inconnue ou absente/.test(blocImport));
ok('le ton change quand des lignes sont refusées',
   /toast\(dits\.join\(' · '\), refusesClasse\?'warning':'success'\)/.test(blocImport));
ok('l’aperçu nomme les classes inconnues AVANT de décider',
   /classe\(s\) inconnue\(s\) de l'école/.test(h));
ok('l’aperçu avertit sur les lignes sans classe',
   /Des lignes n'indiquent aucune classe/.test(h));
ok('père, mère et adresse entrent enfin par le fichier',
   /nom_papa:\(pere\|\|''\)\.trim\(\)\|\|null,nom_maman:\(mere\|\|''\)\.trim\(\)\|\|null,adresse:\(adresse\|\|''\)\.trim\(\)\|\|null/.test(blocImport));
ok('l’encadré ne promet plus une création qui n’avait pas lieu',
   !/La classe et le parent doivent exister ou seront créés/.test(h));

// ── 3. LES TUTEURS, EXÉCUTÉ ──────────────────────────────────────────────
const bloc = (h.match(/window\._tuteursDe = \(s\) => \{[\s\S]*?\n\};/) || [''])[0];
ok('`_tuteursDe` est extractible pour être exécutée', !!bloc);
if (bloc) {
  const ctx = { window:{},
    DB:{ aps:[
      { sid:'s1', name:'Tantine Béa', relation:'Tante', phone:'+243810000222', active:true },
      { sid:'s1', name:'Ancien chauffeur', relation:'Chauffeur', phone:'', active:false },
      { sid:'s9', name:'Voisin', relation:'Voisin', active:true },
    ]},
    gu:(id) => id === 'p1' ? { name:'Maman Kabila', phone:'+243810000111' } : null };
  ctx.globalThis = ctx; vm.createContext(ctx);
  new vm.Script(bloc).runInContext(ctx);
  const T = ctx.window._tuteursDe;

  const complet = T({ id:'s1', pid:'p1', nom_papa:'Jean Kabila', nom_maman:'Marie Kabila' });
  ok('le père est nommé',            complet.some(x => x.q==='Père' && x.n==='Jean Kabila'));
  ok('la mère est nommée',           complet.some(x => x.q==='Mère' && x.n==='Marie Kabila'));
  ok('le compte parent porte le téléphone',
     complet.some(x => x.q==='Compte parent' && x.t==='+243810000111'));
  ok('les personnes autorisées figurent aussi',
     complet.some(x => x.q==='Tante' && x.n==='Tantine Béa'));
  ok('une personne autorisée désactivée ne figure PAS',
     !complet.some(x => x.n==='Ancien chauffeur'));
  ok('l’entourage d’un autre élève ne déborde pas',
     !complet.some(x => x.n==='Voisin'));

  const nu = T({ id:'s7', pid:null });
  ok('un élève sans entourage rend une liste vide, jamais une erreur', Array.isArray(nu) && nu.length === 0);

  const sansCompte = T({ id:'s7', pid:null, nom_papa:'Papa seul' });
  ok('le père seul suffit à remplir la ligne',
     sansCompte.length === 1 && sansCompte[0].n === 'Papa seul');
}

// ── 4. LA LISTE, PAR CLASSE ET POUR TOUTE L'ÉCOLE ────────────────────────
ok('la liste existe', /window\.printListeTuteurs = \(cid\) => \{/.test(h));
ok('elle se limite à une classe quand on le demande',
   /\(DB\.classes\|\|\[\]\)\.filter\(c => !cid \|\| c\.id === cid\)/.test(h));
ok('les élèves sans classe ne sont pas perdus', /Sans classe attribuée/.test(h));
ok('les élèves archivés sont hors liste', /!s\.archived/.test(h));
ok('une fiche sans tuteur est signalée, pas laissée vide',
   /Aucun tuteur enregistré/.test(h));
ok('elle prend la charte des documents officiels',
   /<style>\$\{window\._CSS_DOC\}[\s\S]{0,700}?ÉLÈVES ET TUTEURS/.test(h));
ok('elle porte la chaîne de responsabilité', /\$\{_enteteOfficiel\(\)\}[\s\S]{0,400}?ÉLÈVES ET TUTEURS/.test(h));
ok('elle se signe', /ÉLÈVES ET TUTEURS[\s\S]{0,4000}?_officialFooter\(/.test(h));
ok('le tableur reprend le même entourage', /window\.exportTuteursCSV = \(cid\) => \{/.test(h));
ok('les deux sont réservés à la Direction',
   (h.match(/if \(_denyRole\('direction','direction2'\)\) return;/g)||[]).length >= 3);
ok('le choix de portée est posé une seule fois', /window\.ouvrirListeTuteurs = \(\) => \{/.test(h));
ok('le bouton est dans l’écran Export', /onclick="ouvrirListeTuteurs\(\)"/.test(h));

for (const p of pts) console.log(`${p.ok ? '✓' : '✗'} ${p.nom}`);
const ratés = pts.filter(p => !p.ok);
console.log(ratés.length ? `\n✗ ${ratés.length} point(s) sur ${pts.length} en échec`
                         : `\n✓ les ${pts.length} points passent`);
process.exit(ratés.length ? 1 : 0);
