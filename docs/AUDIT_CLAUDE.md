# AUDIT INITIAL — SchoolSafe

**Mission :** audit sans refonte (protocole v1.0, §8)
**Dépôt :** `medygoo/SchoolSafe-` · production `main`
**Branche d'audit :** `claude/new-session-guwhgl`
**Auteur :** Claude Code · **Date :** 3 août 2026

> Aucune ligne de `dist/` n'a été modifiée. Aucune table, colonne, fonction ou
> politique RLS n'a été touchée. Aucun secret n'est reproduit dans ce rapport.

---

## 1. État du dépôt

`main` et la branche de travail sont au même commit (`0697b1f`). Historique
complet : 6 commits.

```
0697b1f  Publier le redesign SchoolSafe
625d868  Autoriser la page de mot de passe dans le déploiement
41d4ca5  Fiabiliser la création du mot de passe depuis les e-mails
75b576a  Ajouter la création et la récupération du mot de passe
f38065d  Connecter la connexion e-mail à Supabase
8f4099d  Publier SchoolSafe assaini
```

### Inventaire

144 fichiers, dont 128 images/vidéos. **Le dépôt ne contient que `dist/`** — il
n'existe aucune source, aucun outil de compilation, aucun test. `dist/index.html`
**est** la source : 2,1 Mo, 27 961 lignes, HTML + CSS + JavaScript dans un seul
fichier.

| Chemin | Rôle |
|---|---|
| `dist/index.html` | l'application entière — 2,1 Mo, 6 blocs `<script>`, 504 fonctions exposées |
| `dist/auth.html` | création / réinitialisation du mot de passe (Supabase Auth) |
| `dist/sw.js` | service worker v3 — cache `schoolsafe-v67`, Background Sync, Web Push |
| `dist/manifest.json` | PWA — `start_url` et `scope` pointent `./index.html` |
| `dist/site.html` `ecole.html` `programmes.html` `galerie.html` `contact.html` | site public |
| `dist/assets/site.{css,js}`, `site-data.js` | site public |
| `.github/workflows/pages.yml` | déploiement GitHub Pages, déclenché sur `main` |
| `pages.yml` (racine) | **copie orpheline** du workflow — voir §7.2 |

### Dépendances

Six bibliothèques, toutes chargées depuis un CDN au moment de l'exécution ; pas
de gestionnaire de paquets pour l'application :
`@supabase/supabase-js@2.111.0`, `jsQR@1.4.0`, `qrcodejs@1.0.0`, `jszip@3.10.1`,
`html2pdf@0.10.1`, `html2canvas@1.4.1`.

---

## 2. Architecture observée

**Une application locale qui se synchronise**, pas un client serveur.

1. À la connexion, `loadFromSupabase()` (ligne 2488) tire **47 tables en un seul
   `Promise.all`** vers un objet `DB` en mémoire.
2. Tous les écrans lisent `DB`, jamais le serveur.
3. Les écritures passent par `pushSync()` (ligne 2635), qui écrit en direct ou
   met en file d'attente si hors ligne.
4. `DB` est mis en cache dans `localStorage`, chiffré AES-GCM avec une clé
   dérivée PBKDF2-SHA256, 100 000 itérations (`CRYPT_STORE`, ligne 2734).

L'accès aux données se fait en `fetch` direct sur PostgREST (`_get` / `_post` /
`_patch` / `_del` / `_upsert`, lignes 2450-2460) — le client `supabase-js` ne
sert qu'à l'authentification. Aucun appel `.rpc()` : **aucune fonction serveur
n'est utilisée aujourd'hui**.

**Authentification** : Supabase Auth e-mail + mot de passe. `OPS_SUPA_URL` et
`OPS_SUPA_KEY` sont renseignés (clé `sb_publishable_…`, publique par
construction), donc `window._authClient` existe toujours et le chemin de
connexion historique par nom + PIN (lignes 4084-4145) est **inatteignable**.

**Cloudflare R2 : absent.** Les photos passent par Supabase Storage (bucket
`photos`, lignes 21954-22002). La convention `schools/{school_id}/…` du
protocole §6 n'est implémentée nulle part.

---

## 3. Les défauts d'exécution — vérifiés, reproductibles

Le paquet de transfert fourni par Loms contient dix outils d'audit. Ils ont été
déposés dans `tools/` et adaptés à ce dépôt (une ligne par outil : `index.html`
→ `dist/index.html`). Ce qui suit est leur sortie, pas une impression.

```
$ npm install && node tools/audit-portee.mjs

═══ UN NOM LU HORS DE SA PORTÉE ═══
    39166 références examinées dans 6 blocs <script>

  ✗ canSeeCorr                   ligne 13791
  ✗ totalDette                   ligne 17722
  ✗ _tbm                         lignes 17724, 17724

✗ 3 nom(s) introuvable(s) — 4 lecture(s)

═══ UN NOM LU AVANT SA PROPRE DÉCLARATION ═══
  ✗ trimD2                       ligne 5924
  ✗ parentKidCids                ligne 6981

✗ 2 lecture(s) en zone morte temporelle
```

**Ces cinq lectures sont du JavaScript valide. Elles lèvent une `ReferenceError`
à l'exécution et interrompent le rendu de l'écran entier — l'utilisateur voit
une page blanche, sans message.** Chacune a été confirmée à la main :

| # | Écran | Fait vérifié | Déclenchement |
|---|---|---|---|
| **B1** | Devoirs du parent | `canSeeCorr` lu en 13791, déclaré en 13829 dans `kids.forEach` d'une **autre** fonction. La lecture est dans la branche `isEpreuve` du rendu. | **dès qu'une interrogation ou un examen existe** |
| **B2** | Accueil du parent | `parentKidCids` lu en 6981, `const` en 6990 — zone morte temporelle dans `dashboardParent()` | dès qu'une interro/examen est à venir |
| **B3** | Accueil Direction 2 | `trimD2` lu en 5924, `const` en 5931 dans `dashboardDirection2()` | dès qu'une classe a élèves **et** matières |
| **B4** | État financier (PDF) | `_tbm` et `totalDette` lus dans `exportEtatFinancierPDF()` (17703) ; ils appartiennent à la fonction voisine (17594-17597) | **à chaque export** — aucun PDF ne sort |

B1, B2 et B3 ne se déclenchent **que lorsqu'il y a enfin quelque chose à
afficher** : jamais pendant un essai sur base vide, systématiquement en service.
C'est la totalité de l'explication d'un « les parents ne reçoivent rien ».

`docs/notes/deja-resolu.md` décrit exactement ces quatre pannes, rencontrées
ailleurs sur la même application. Elles sont ici intactes.

---

## 4. Confidentialité par rôle — trois écarts avec le dossier du point 19

### 4.1 Le Gardien voit le motif financier et un symbole monétaire

`processScanEntry()`, ligne 15464 :

```js
showScanResult('red', _cur(), 'FRAIS NON RÉGLÉS', student.name,
               `Frais ${fc.trimestre} non payés — Entrée refusée`, time);
```

Cet écran plein écran est celui du Gardien. Le dossier §3.3 dit : *« Gardien :
photo, identité, classe et instruction. Aucun montant »*, et §5.3 interdit toute
raison financière dans son navigateur. `_cur()` est le symbole de la devise de
l'école ; le libellé nomme le trimestre impayé.

### 4.2 Direction 2 reçoit une notification financière

Lignes 15457-15462, sur le même refus :

```js
DB.users.filter(u => u.role==='direction' || u.role==='direction2').forEach(u => {
  … msg: `💰 Frais non réglés — ${student.name} (…) refusé(e) à l'entrée · ${fc.trimestre}`
```

Le dossier §3.3, encadré « Protection de Direction 2 » : *« aucune raison
financière, aucun montant et aucun statut de paiement ne doivent lui être
retournés »*. La notification est écrite en base ; la masquer à l'affichage ne
suffirait pas.

### 4.3 Chaque rôle tire les 47 tables de l'école

```
$ node tools/audit-portee-parent.mjs

  47 tables LUES par le parent :
     … advances audit_log daily_expenses direct_primes evaluations grades
       journal_entries medical salaries versements …
```

`loadFromSupabase()` est le même code pour tous les rôles. Un téléphone de
parent — comme celui d'un Gardien — reçoit donc les salaires du personnel, le
journal comptable, le journal d'audit, les dossiers médicaux et les cotes de
tous les élèves de l'école. **Rien dans l'interface ne filtre : la seule barrière
est RLS.** Si une politique manque ou est trop large, la donnée est déjà sur
l'appareil.

C'est exactement ce que le dossier du point 19 demande d'empêcher, et cela
conditionne le contrat API : le filtrage doit porter sur **les lignes que le
serveur renvoie**, pas sur ce que l'interface choisit d'afficher.

### 4.4 Le garde de navigation n'est pas une sécurité

`window.go()` (3485) refuse les pages absentes du menu du rôle. C'est utile,
mais c'est du rendu : les fonctions restent appelables depuis la console, et
`audit-gardes.mjs` liste **16 mutations exposées sans contrôle de rôle**, dont
`saveFeeType`, `toggleFeeType`, `saveBudgetDepenses`, `_seedFeeTypes`,
`genRecuNo`, `executePassage`, `_saveSettings`.

---

## 5. Contrôle des frais existant — ce qu'il fait aujourd'hui

### 5.1 Le solde est calculé dans le navigateur, sur un booléen

Le modèle actuel est celui décrit au §4 du dossier : `payments(sid, t, paid,
date, …)`. Le contrôle au portail (15450-15452) est :

```js
const hasPaidFc = (DB.payments||[]).some(p => p.sid===student.id
                                           && p.t===fc.trimestre && p.paid);
if (!hasPaidFc) { … entrée refusée … }
```

Conséquence mécanique : **une famille ayant versé 80 % du trimestre est traitée
exactement comme une famille n'ayant rien versé, et l'enfant est renvoyé du
portail.** Il n'existe ni versement partiel, ni échéancier, ni dérogation, ni
type de frais dans cette décision.

### 5.2 Un refus est enregistré comme une entrée

Tous les refus écrivent `type:'entry'` dans `scan_log` (15425, 15454, 15475,
15485, 15531). Une fonction correcte existe — `window._estIncident` (15812) —
mais **elle n'est appelée qu'à un seul endroit** (l'historique des scans, 15863).
Quatorze autres lectures filtrent encore sur `l.type==='entry'` brut :

| Ligne | Effet d'un refus compté comme entrée |
|---|---|
| 23809 | l'espace parent affiche **« Arrivé(e) à l'école à HH:MM »** |
| 11334 | la validation des présences affiche l'enfant comme scanné |
| 6737 | le tableau du Gardien le compte parmi les élèves **encore dans l'école** |
| 4704 · 5367 · 6618 · 11261 · 11351 · 11380 · 24408 · 25682 | totaux, listes et notifications d'absence |

Un enfant renvoyé pour frais impayés est donc annoncé « arrivé » à sa famille.
Ce défaut est déjà dans le module de frais ; il se rejouera tel quel dans le
scanner financier si la règle « **un refus n'est pas un passage** » n'est pas
posée dans une fonction unique.

### 5.3 Autres constats du même module

- `existingRefused` (15446) ne teste que `status==='refused'` : un élève refusé
  pour frais (`refused_fees`) peut être re-scanné dans la journée.
- `toggleFeesControl` (8638) — l'interrupteur du contrôle des frais — est une
  fonction **sans aucun appelant** ; il n'est joignable par aucun écran.
- `togglePay` (10657) et `sendCaisseReceipt` (17206) sont également sans appelant.

---

## 6. Sécurité — ce qui est vu depuis le dépôt

**Aucun secret dans le dépôt.** `service_role` n'apparaît que dans deux
commentaires qui en interdisent l'usage (1581, 2412). Les clés présentes sont
des clés publiables Supabase, publiques par construction. Elles ne protègent
donc rien par elles-mêmes : **toute la sécurité repose sur RLS**, ce que le §4.3
rend critique.

| | Constat |
|---|---|
| **CSP** | absente de `index.html` et `auth.html` |
| **SRI** | 0 attribut `integrity` sur 6 scripts CDN. La page porte une session Supabase ; un CDN compromis lit tout. Le service worker **précache** ces mêmes URL (`sw.js`, `PRECACHE`) — une version altérée survivrait au correctif |
| **Échappement** | `esc()` (2995) passe par `textContent`→`innerHTML` : il **n'échappe ni `"` ni `'`**. 8 attributs `onclick` interpolent `esc()` entre apostrophes — un nom comme `N'Goma` casse le bouton |
| **PIN en clair** | l'écran des comptes affiche `${u.pin_hashed ? '••••••' : u.pin}` (9292) : le PIN des comptes non migrés est écrit en clair dans le DOM |
| **Auth** | mot de passe ≥ 8 caractères côté client. La protection « mots de passe compromis » de Supabase Auth relève de ChatGPT (dossier §5.2) |
| **Verrouillage** | le compteur de tentatives est dans `localStorage` (4088) — effaçable par l'utilisateur |

---

## 7. Cohérence des données et du déploiement

### 7.1 Deux tables lues mais non déclarées

```
$ node tools/audit-invariant.mjs
  49 tables déclarées · 53 lues · 49 écrites
  ✗ toute table lue est déclarée — exit_scans, exetat : undefined au démarrage
  ✗ toute table écrite ET relue a son miroir local — exetat
```

`DB.exit_scans` et `DB.exetat` valent `undefined` au démarrage : toute lecture
non gardée par `|| []` donne un résultat silencieusement faux. `exetat` est de
plus écrit puis relu sans miroir local — la donnée saisie disparaît jusqu'au
prochain chargement complet.

### 7.2 Le workflow dupliqué

`pages.yml` existe **deux fois** : `.github/workflows/pages.yml` (actif, exige
`144` fichiers — la valeur juste) et `pages.yml` à la racine (ajouté au dernier
commit, exige `147`). Seul le premier s'exécute. Le second est mort, et il
affiche une valeur fausse à qui le lit.

### 7.3 Manifeste et icônes

`manifest.json` déclare `icon-180/192/512.png` : les trois existent. `sw.js`
précache `./icon-192.png` et `./icon-512.png` : présents.
`dist/auth.html` charge `logo-schoolsafe.png` : présent.
**Aucun lien cassé de ce côté.**

### 7.4 Écritures dont l'échec est invisible

`audit-writes.mjs` relève **215 occurrences dans 110 fonctions** où le retour de
`pushSync` n'est pas examiné. L'utilisateur reçoit une confirmation alors que
l'opération peut n'avoir jamais atteint le serveur — c'est le mécanisme du
symptôme n° 1 décrit dans `docs/notes/la-base-vue-du-frontend.md`.

### 7.5 Dette technique

- **Le fichier unique.** 27 961 lignes ; deux agents qui y écrivent en parallèle
  produisent des conflits qui ne se résolvent pas proprement (tâche A11).
- **14 fonctions exposées sans appelant** (`audit-mort.mjs`), dont
  `activateLicense` — reste d'un système de licence retiré (`showSupaSetup()`
  ligne 7259 commence par `return; // Supabase supprimé`).
- **Le chemin de connexion nom + PIN** (4084-4145) est inatteignable mais
  toujours présent, avec sa comparaison de PIN côté navigateur.

---

## 8. Ce que les outils ne disent pas encore

Honnêteté sur le harnais, conformément au principe n° 2 du paquet de transfert :

- **`verif-coherence.mjs` ne s'exécute pas ici** — les fonctions de calcul ne se
  chargent pas dans son stub de DOM. *La chaîne de calcul (cotes → bulletin →
  classement) n'est donc vérifiée par personne aujourd'hui.* Adapter le harnais
  est une tâche à part entière.
- **`audit-charte.mjs` et `audit-logo.mjs` sont calibrés sur une autre charte** —
  le gris/blanc/or de `CLAUDE.md`, hérité de l'autre installation. Leurs
  « 505 couleurs hors charte » et « 10 documents sans emblème » ne sont **pas**
  505 défauts : ils décrivent l'écart avec une charte que ce dépôt n'a pas
  adoptée. À arbitrer par Loms avant d'en tirer quoi que ce soit.
- **`audit-schema.mjs` n'a rien à comparer** : aucun fichier `.sql` dans le
  dépôt. Il redeviendra utile quand ChatGPT y déposera les migrations.
- `npm run audit` enchaîne les outils avec `&&` : il s'arrête au premier échec.
  Les lancer un par un tant que des défauts subsistent.

---

## 9. Priorités proposées

Rien n'est engagé sans validation. Ordre proposé, du plus grave au moins :

| | Sujet | Pour qui |
|---|---|---|
| **P1** | B1-B4 : quatre pages blanches, quatre corrections locales de portée | Claude |
| **P2** | §4.1 et §4.2 : le motif financier retiré de l'écran Gardien et de la notification Direction 2 | Claude — **règle métier à confirmer par Loms** |
| **P3** | §5.2 : « un refus n'est pas un passage » — une fonction unique, quatorze appels | Claude |
| **P4** | §4.3 : le chargement des 47 tables par rôle — impossible sans contrat serveur | **ChatGPT d'abord** |
| **P5** | Modèle de paiement (dossier §4.1), fonctions serveur (§4.3), RLS par rôle | **ChatGPT** |
| **P6** | §7.1 `exit_scans` / `exetat` ; §7.2 workflow orphelin | Claude |
| **P7** | SRI + CSP — **touche le service worker**, donc à signaler avant de coder | Claude, après accord |
| **P8** | Découpage du monolithe (A11) — le plus risqué, en dernier | Claude |

---

## 10. Questions à ChatGPT et à Loms

**À ChatGPT :**

1. Le contrat API du point 19 : quels champs exactement pour
   `get_parent_fee_summary`, `get_gate_access_status`, `get_cashier_student_fee_detail` ?
   Rien ne sera déduit côté navigateur.
2. Comment un rôle doit-il charger ses données une fois le nouveau contrat en
   place ? Le `Promise.all` de 47 tables est-il remplacé par des vues filtrées ?
3. Durée de validité d'un statut de frais mis en cache hors ligne, au-delà de
   laquelle l'écran doit afficher « contrôle manuel requis » ?
4. La table `exetat` et `exit_scans` existent-elles réellement en base ?

**À Loms :**

5. §4.1/§4.2 : confirmez-vous que le Gardien ne doit voir qu'« à orienter vers
   la Caisse », sans devise ni trimestre, et que Direction 2 ne doit plus rien
   recevoir de financier ? La correction change ce que voient deux rôles.
6. Le sel des mots de passe et la clé du cache chiffré de l'autre installation
   doivent-ils être repris ? Si des comptes ou des caches existants doivent
   continuer de fonctionner, ce sont deux chaînes à ne pas deviner
   (`docs/notes/LISEZ-MOI-transfert.md`).
7. La charte gris/blanc/or de `CLAUDE.md` s'applique-t-elle à ce dépôt ?

---

## 11. Fichiers ajoutés par cet audit

Aucun fichier existant n'a été modifié.

```
CLAUDE.md                              mémoire de travail (paquet de transfert)
package.json  package-lock.json        acorn + acorn-walk, rien d'autre
.gitignore                             node_modules/
tools/*.mjs                    (10)    outils d'audit, chemin adapté à dist/
docs/AUDIT_CLAUDE.md                   ce rapport
docs/notes/collaboration.md            protocole opérationnel
docs/notes/deja-resolu.md              mission A1-A12 : ce qui a déjà cassé
docs/notes/la-base-vue-du-frontend.md  reconnaître un symptôme de base de données
docs/notes/LISEZ-MOI-transfert.md      ce que contient le paquet, et ce qu'il exclut
```

**Retour arrière :** supprimer ces fichiers. Aucun effet sur l'application
déployée — `dist/` est intact et le workflow ne compte que les fichiers de
`dist/`.

**Impact Supabase / RLS / Auth / R2 / PWA : aucun.**
