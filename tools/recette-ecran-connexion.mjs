// ══════════════════════════════════════════════════════════════════════════
//  recette-ecran-connexion.mjs — l'écran que voit TOUT LE MONDE
//
//  Loms, 12 août 2026 : « l'écran de connexion est lent, en retard, et quand
//  j'écris le mail ça bugue ».
//
//  Trois causes, aucune mystérieuse, aucune mesurée jusque-là :
//
//    1. Le splash n'avait AUCUNE minuterie. L'application était entièrement
//       chargée et attendait un doigt. Pour qui ouvre, une attente d'appui et
//       un calcul lent sont le même écran figé.
//    2. L'aperçu sous le champ affichait le REFUS en rouge à chaque touche.
//       En tapant `loms@gmail.com` on lisait « Identifiant non reconnu », puis
//       « Adresse e-mail incomplète » jusqu'au dernier caractère. Une saisie
//       juste, condamnée en cours de route.
//    3. Le fond tournait toutes les 7 s en téléchargeant 50 à 100 Ko, décodés
//       sur le fil principal — pendant la frappe.
//
//  Ce que cette recette tient, c'est la règle, pas le réglage : on peut changer
//  1600 ms en 1200, mais on ne peut plus supprimer la minuterie sans que le
//  filet le dise.
//
//    node tools/recette-ecran-connexion.mjs
//    node tools/recette-ecran-connexion.mjs --preuve
// ══════════════════════════════════════════════════════════════════════════
import fs from 'node:fs';
import vm from 'node:vm';

const preuve = process.argv.includes('--preuve');
let h = fs.readFileSync('dist/index.html', 'utf8');

// ── LA PREUVE ────────────────────────────────────────────────────────────
// On réinjecte dans la vraie source les trois défauts que Loms a vus, plus le
// chargement inutile de la seconde photo. Une recette qui ne sait dire que
// « oui » ne vérifie rien.
if (preuve) {
  h = h.replace('setTimeout(goLogin, window._SPLASH_MS);', '/* plus de minuterie */');
  h = h.replace('window._apercuRefusT = setTimeout(refuser, window._RETARD_REFUS_MS);', 'refuser();');
  h = h.replace("if(actif && (actif.id === 'LN' || actif.id === 'LP')) return;", '');
  h = h.replace('<img class="login-bg-img" id="LH_IMG_B" alt=""',
                '<img class="login-bg-img" id="LH_IMG_B" src="login-kid-2.jpg" alt=""');
}

const pts = [];
const ok = (nom, cond) => { pts.push({ nom, ok: !!cond }); };

// ── 1. LE SPLASH S'EFFACE SEUL ───────────────────────────────────────────
ok('le splash a une minuterie', /setTimeout\(goLogin,\s*window\._SPLASH_MS\)/.test(h));
const ms = (h.match(/window\._SPLASH_MS\s*=\s*(\d+)/) || [])[1];
ok('la minuterie est réglée et courte (≤ 3 s)', ms && +ms > 0 && +ms <= 3000);
ok('l’appui coupe toujours court', /splash\.addEventListener\('click',\s*goLogin/.test(h));
ok('goLogin ne peut pas s’exécuter deux fois',
   /if\(window\._splashGone\s*\|\|\s*window\._splashTransitionBusy\)\s*return;/.test(h));

// ── 2. ON CONFIRME PENDANT LA FRAPPE, ON NE REFUSE QU'APRÈS ──────────────
ok('le refus est différé pendant la frappe',
   /window\._apercuRefusT\s*=\s*setTimeout\(refuser,\s*window\._RETARD_REFUS_MS\)/.test(h));
ok('la frappe suivante annule le refus en attente', /clearTimeout\(window\._apercuRefusT\)/.test(h));
ok('le refus relit le champ avant de s’afficher',
   /const maintenant = \(ln\.value \|\| ''\)\.trim\(\)/.test(h));
ok('quitter le champ affiche le refus tout de suite',
   /addEventListener\('blur',\s*\(\)\s*=>\s*window\._telApercuConnexion\(\{\s*immediat:\s*true\s*\}\)\)/.test(h));
ok('la confirmation, elle, reste immédiate',
   /vu\.style\.color = 'rgba\(255,255,255,\.82\)';\s*\n\s*return;/.test(h));

// L'aperçu tourné pour de vrai : on extrait `_voieDe` et on tape une adresse
// lettre par lettre. AUCUN préfixe d'une adresse valide ne doit être présenté
// comme définitivement faux — c'est exactement ce que Loms a vu.
const bloc = (h.match(/window\._voieDe = \(saisie\) => \{[\s\S]*?\n\};/) || [])[0];
ok('`_voieDe` est extractible pour être exécutée', !!bloc);
if (bloc) {
  const ctx = { window: { _telE164: (v) => (/^(\+243|0)\d{9}$/.test(String(v).replace(/[\s().-]/g, '')) ? '+243' + String(v).replace(/[\s().-]/g, '').replace(/^(\+243|0)/, '') : null) } };
  vm.createContext(ctx);
  new vm.Script(bloc).runInContext(ctx);
  const voieDe = ctx.window._voieDe;

  const adresse = 'loms@gmail.com';
  const prefixes = [];
  for (let i = 1; i < adresse.length; i++) prefixes.push(adresse.slice(0, i));
  const refusesEnRoute = prefixes.filter(p => !voieDe(p).valeur);
  // Le constat que Loms décrit : la plupart des préfixes d'une adresse juste
  // sont « non reconnus ». C'est un fait de `_voieDe`, et il est NORMAL — d'où
  // la nécessité de ne pas l'afficher pendant la frappe.
  ok('taper une adresse traverse bien des états « non reconnus »', refusesEnRoute.length > 0);
  ok('l’adresse complète, elle, est reconnue', voieDe(adresse).valeur === 'loms@gmail.com');
  ok('un numéro complet est reconnu', voieDe('0810000111').voie === 'tel');
  ok('une abréviation est reconnue', voieDe('DIR1').voie === 'identifiant' && !!voieDe('DIR1').valeur);
}

// ── 3. LE DÉCOR NE PASSE PAS DEVANT LA SAISIE ────────────────────────────
ok('la rotation du fond saute son tour pendant la saisie',
   /actif\.id === 'LN' \|\| actif\.id === 'LP'/.test(h));
ok('la rotation saute son tour quand l’onglet est caché', /if\(document\.hidden\) return;/.test(h));
ok('la seconde photo n’est plus chargée à l’ouverture',
   /<img class="login-bg-img" id="LH_IMG_B" alt=""/.test(h));
ok('les deux photos de fond se décodent hors du fil principal',
   (h.match(/id="LH_IMG_[AB]"[^>]*decoding="async"/g) || []).length === 2);

// ── 4. CE QUI NE DOIT PAS REVENIR ────────────────────────────────────────
// Le SDK Supabase et jsQR restent différés : c'est la correction d'ouverture
// du 11 août, et elle a déjà coûté une régression de connexion.
ok('le SDK Supabase reste différé', /<script defer src="[^"]*supabase-js/.test(h));
ok('le bootstrap qui rattrape ce différé est toujours chargé',
   /<script src="messages-frontend-v2\.js[^"]*" defer><\/script>/.test(h));

for (const p of pts) console.log(`${p.ok ? '✓' : '✗'} ${p.nom}`);
const ratés = pts.filter(p => !p.ok);
console.log(ratés.length ? `\n✗ ${ratés.length} point(s) sur ${pts.length} en échec`
                         : `\n✓ les ${pts.length} points passent`);
process.exit(ratés.length ? 1 : 0);
