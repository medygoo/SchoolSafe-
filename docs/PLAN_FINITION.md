# Plan de finition — SchoolSafe pour 350 élèves

**Auteur :** Claude · **Date :** 3 août 2026 · **Délai fixé par Loms : 7 jours**
**Base de données :** ChatGPT · **Intégration, tests et publication `main` :** Claude
**Données actuelles : toutes de test.** Aucune donnée réelle d'élève, de parent
ou de paiement n'est en jeu — ce plan en tire parti (voir §0.3).

---

## 0. Le point de départ, mesuré

### 0.1 L'application existe

| | |
|---|---|
| `dist/index.html` | 28 004 lignes · 2,12 Mo · **502 fonctions exposées** |
| Rôles | Direction 1 · Direction 2 · Caisse · Enseignant · Gardien · Parent |
| Écrans | Direction **48** · Direction 2 **38** · Enseignant **19** · Parent **18** · Caisse **12** · Gardien **8** |
| Tables lues | **47**, en un seul `Promise.all` au démarrage |
| Écritures | **311 appels `pushSync`** répartis sur 47 tables |

Présences, notes, bulletins, palmarès, caisse, comptabilité, paie, cantine,
santé, convocations, sanctions, TENAFEP, EXETAT, cartes d'élèves, scanner
d'entrée et de sortie, espace parent : **tout est écrit.**

**Ce plan n'ajoute aucune fonctionnalité.** Il branche ce qui existe.

### 0.2 Ce qui manque tient en trois phrases

**1 — Ce que l'école saisit n'arrive pas toujours dans la base, et l'écran dit
que si.** `audit-writes` compte **215 écritures dont l'échec est invisible**,
dans 110 fonctions. L'inscription d'un élève affichait « 🎉 inscrit » avant
toute réponse du serveur : refusée par la base, la famille restait inscrite à
l'écran et absente du système.

**2 — Ce qui est dans la base n'arrive pas toujours à l'écran.** Quatre écrans
devenaient entièrement blancs — et seulement quand l'école avait enfin quelque
chose à montrer. La saisie EXETAT partait au serveur puis disparaissait au
rechargement.

**3 — Certaines parties ne sont branchées à rien.** « Mon site web » n'atteint
jamais le site. Le contrôle des frais décide sur un booléen par trimestre : une
famille ayant versé 80 % est traitée exactement comme une famille n'ayant rien
versé, et l'enfant est renvoyé du portail.

### 0.3 Ce que « données de test » autorise

C'est une **simplification majeure**, et elle change l'ordre du travail :

- aucune migration de données réelles à préparer ;
- on peut **vider et recharger** une table sans procédure de sauvegarde ;
- une régression coûte un rechargement, pas la scolarité d'un enfant ;
- **le sel des mots de passe et la clé du cache chiffré n'ont pas à être
  repris** — aucun compte existant, aucun cache hors ligne à préserver.

En contrepartie : **rien n'a encore été éprouvé sur du volume.** Tout ce plan
suppose une recette finale sur un jeu d'essai de **350 élèves**, sans quoi on ne
saura pas si l'application tient (§H).

### 0.4 Ce que 350 élèves changent

Chaque ouverture de l'application tire **les 47 tables**, le même code pour tous
les rôles. Un téléphone de parent reçoit les salaires du personnel, le journal
comptable, le journal d'audit et les notes de tous les élèves.

À 350 élèves : environ **400 appareils × 47 requêtes**, concentrées sur la
demi-heure d'arrivée du matin — et **chaque coupure de réseau relance le cycle
complet**.

Ce n'est pas une question de confort. C'est ce qui décidera si l'application
tient le matin de la rentrée. **C'est la partie B, et c'est la plus urgente
après les écritures.**

### 0.5 Déjà fait (branche `claude/new-session-guwhgl`)

| Commit | |
|---|---|
| `8ae6510` | audit initial — `docs/AUDIT_CLAUDE.md` |
| `8f029f9` | **4 pages blanches** corrigées (accueil parent, accueil Direction 2, devoirs parent, export état financier) |
| `879a7f7` | site : 56 images rapatriées, partage WhatsApp/Google, adresse corrigée |
| `a0203e9` | l'éditeur retiré — 139 lignes : numéro, licence, activation |
| `27968f1` | `exit_scans` → `scan_log` · `exetat` déclarée et rechargée |
| `04c385e` | **`save_student_profile`** + briques `_rpc` / `_edgeFn` / `_CODE_MSG` / `_btnBusy` |

---

## Comment lire ce plan

Chaque partie dit la même chose dans le même ordre :

> **Ce qui existe** · **Ce qui manque** · **🔌 La ligne dont j'ai besoin de
> ChatGPT** · **Ce que je fais** · **Comment on vérifie** · **Fini quand**

La ligne 🔌 est le contrat de raccordement : le nom de la porte, ses champs, ses
erreurs. **Sans elle je n'invente rien — je m'arrête et je demande.**

---

# PARTIE A — Les écritures confirmées par le serveur

> **La règle : une confirmation ne s'affiche jamais avant la réponse positive du
> serveur. Une mise en file d'attente n'est pas un enregistrement.**

### Ce qui existe

`pushSync()` (311 appels) écrit ou met en file. Le mécanisme est bon : file
persistante, recul progressif, « pousser avant de tirer ».

### Ce qui manque

**215 de ces 311 écritures ignorent le résultat.** La confirmation part avant la
réponse. Les tables les plus touchées :

```
notifs 76 · settings 19 · students 15 · users 14 · scan_log 13
rattrapages 11 · attendance 11 · classes 9 · payments 8 · messages 7
convocations 7 · cahier_prep 7 · approbations 7 · sanctions 6 · grades 6
```

### 🔌 Ligne dont j'ai besoin de ChatGPT

| | Statut |
|---|---|
| `save_student_profile(p_student)` | ✅ **reçu et intégré** |
| `save_school_user_profile(p_user)` | ✅ reçu — **bloqué, voir ci-dessous** |
| `invite-school-account` | ✅ reçu |
| **Le PIN** | ❓ **question ouverte** |

> **Question bloquante.** `save_school_user_profile` accepte
> `id, name, role, initials, phone, photo_url, email, status`. **`pin` n'y est
> pas.** Or `saveUser` en écrit un, et `resetUserPin` le réécrit.
> Je penche pour : **le PIN est mort**, l'authentification étant passée à
> e-mail + mot de passe. Mais c'est une décision de sécurité — donc la vôtre.

**Et pour les 45 autres tables** : faut-il une RPC par table, ou l'écriture
directe reste-t-elle acceptable dès lors que le frontend **vérifie et affiche**
le refus ? Mon avis : garder `pushSync` partout sauf `students`, `users`,
`payments` et `settings`, et rendre l'échec visible partout. **Une RPC par table
serait 47 contrats pour un gain nul sur 40 d'entre elles.**

### Ce que je fais

1. `saveUser` → `save_school_user_profile`, puis `invite-school-account` quand
   `requires_invitation === true`. Succès affiché seulement après
   `ACCOUNT_INVITED`.
2. **Un garde-fou unique** appliqué aux 110 fonctions : bouton désactivé →
   `await` → vérification → **message du serveur, formulaire ouvert** en cas de
   refus → confirmation seulement après succès.
3. Hors ligne : la file reste, **le message change** — « en attente d'envoi, pas
   encore enregistré ».
4. Les **15 mutations sans contrôle de rôle** relevées par `audit-gardes`
   reçoivent leur garde. Cacher un bouton ne protège rien.

### Comment on vérifie

`npm run audit` — `audit-writes` doit tomber de 215 à ~0 sur les fonctions
traitées, `audit-gardes` de 15 à 0. Et un test manuel qui ne trompe pas :
**couper le réseau, enregistrer, lire le message.**

### Fini quand

Aucun écran n'affiche une confirmation que le serveur n'a pas donnée.

---

# PARTIE B — Le chargement par rôle

> **La partie la plus urgente après A, et la plus structurante. C'est elle qui
> décide si l'application tient à 350 élèves.**

### Ce qui existe

`loadFromSupabase()` — un `Promise.all` de 47 requêtes, **identique pour les six
rôles**. `safe()` distingue déjà correctement « table vide » et « lecture
échouée », ce qui est le point difficile et il est déjà juste.

### Ce qui manque

Le filtrage. Un parent reçoit `salaries`, `advances`, `journal_entries`,
`audit_log`, `medical`, et les `grades` de toute l'école. **La seule barrière
est RLS.** Si une politique manque ou est trop large, la donnée est déjà sur
l'appareil.

### 🔌 Ligne dont j'ai besoin de ChatGPT

Il a écrit le **quoi** (`API_CONTRACTS_V1.md` §5). Il me manque le **comment** :

1. **Une liste de tables par rôle** — pas une intention, une liste. Pour chacun
   des six rôles : les tables, et pour chacune les **colonnes** et le **filtre**.
2. **Des vues ou des RPC** quand le filtre ne s'exprime pas en PostgREST.
   Exemple : l'enseignant ne doit voir que les élèves de **ses** classes.
3. **La liste minimale du Gardien** — contient-elle le **matricule** ? J'en ai
   besoin pour résoudre `matricule → sid` : le QR de la carte porte le
   matricule, `check_gate_access_status` attend un `sid`.
4. **Le comportement quand une table est refusée** : ligne vide, ou erreur ?
   Aujourd'hui `safe()` traite `[]` comme une réponse légitime — **un parent
   privé d'accès verrait donc des écrans vides sans message.**

### Ce que je fais

1. Une **table de chargement par rôle** en un seul endroit du code, lisible d'un
   coup d'œil — pas six fonctions qui divergeront.
2. `loadFromSupabase()` la consulte au lieu de tirer les 47.
3. **Chargement en deux temps** : ce que l'écran d'accueil exige d'abord, le
   reste en arrière-plan. Un parent doit voir son enfant en deux secondes, pas
   attendre le journal comptable.
4. Distinguer **« aucune donnée »** de **« accès refusé »** — deux écrans
   différents. Un écran vide sans explication est un défaut.
5. La cadence : **du désaccord** (± 25 % d'écart aléatoire, sinon 400 téléphones
   repartent à la même seconde), **du recul** en cas d'échec, et **du silence
   quand rien ne change** — une empreinte des données suffit à savoir si la
   réception a rapporté quelque chose, sans reconstruire la page.

### Comment on vérifie

`node tools/audit-portee-parent.mjs` doit tomber de **47 tables pour le parent**
à la liste convenue. Puis, en conditions réelles : ouvrir une session parent et
compter les requêtes.

### Fini quand

Aucun rôle ne reçoit une table dont aucun de ses écrans ne se sert, et un parent
ouvre son accueil en moins de trois secondes sur un réseau moyen.

---

# PARTIE C — L'argent : frais, reçus, caisse

### Ce qui existe

Écrans Caisse, état financier, trésorerie, comptabilité, paie, types de frais,
reçus. Table `payments` : *(élève, trimestre, booléen payé)*.

### Ce qui manque

**Une seule définition du solde.** Aujourd'hui il est recalculé dans le
navigateur, et le modèle ne sait pas représenter un versement partiel. Une
famille ayant versé 80 % d'un trimestre est affichée **exactement comme une
famille n'ayant rien versé**.

Côté parent, la rubrique **« Frais scolaires » n'existe pas** : le menu ne
propose que « Mes Reçus ». Devoirs et Interrogations ne sont pas séparés.

### 🔌 Ligne dont j'ai besoin de ChatGPT

| | Statut |
|---|---|
| `get_parent_fee_summary(p_sid)` — obligations et reçus champ par champ | ✅ **reçu** (`API_CONTRACTS_V1.md` §3) |
| `get_cashier_student_fee_detail(p_sid)` | ✅ reçu |
| `record_payment_transaction(...)` | ✅ décrit (`PAYMENT_CONTROL_API.md`) |
| `reverse_payment_transaction`, dérogations | ✅ décrits |
| **Le SQL des paiements dans le dépôt** | ❌ `20260802205234_add_payment_control_backend_v1` est référencé par le README mais **le fichier `.sql` est absent** |
| **Le numéro de reçu** | ❓ le serveur le génère-t-il ? séquentiel par année scolaire ? |

> Sur le numéro de reçu : un registre de délivrance se tient par **numéro
> d'ordre séquentiel par année scolaire**. Une administration doit pouvoir dire
> « montrez-moi le n° 42 ». Une référence dérivée d'un identifiant interne ne
> s'ordonne pas et ne se vérifie pas.

### Ce que je fais

1. Espace parent : **trois cartes de même niveau** — Devoirs · Interrogations ·
   Frais scolaires. Les deux premières vivent dans la même table, séparées par
   `category`.
2. Page **Frais scolaires** du parent : statut, montants par devise, solde,
   prochaine échéance, échéancier, historique, reçus. **Aucun calcul dans le
   navigateur** — j'affiche ce que le serveur répond.
3. Sélecteur multi-enfants, avec **revérification du lien parent-enfant à chaque
   rendu** — le menu ne propose que ses enfants, mais on ne fait pas confiance
   au DOM.
4. Écran **Caisse** : scan du QR existant ou saisie du matricule →
   `get_cashier_student_fee_detail` → `record_payment_transaction` → numéro de
   reçu **rendu par le serveur**.
5. **Un lecteur de montant dédié**, jamais `parseFloat` : `parseFloat('12,50')`
   vaut **12** — la virgule est le séparateur décimal ici. Il accepte
   « 12,50 », « 1 200 », « 1.200,50 » et **refuse** « 1O0 » (la lettre O).
6. Un bloc **« Autres versements »** : un encaissement hors des types de frais
   actifs doit apparaître quelque part. *Un reçu qu'on ne retrouve pas est un
   reçu qu'on croit perdu.*

### Comment on vérifie

Un versement partiel, un versement total, une correction. Le même élève ouvert
côté parent et côté caisse : **les deux écrans annoncent le même solde.**

### Fini quand

Le parent voit ses trois cartes, ses montants sont exacts, et aucun solde n'est
calculé dans le navigateur.

---

# PARTIE D — Le portail, le scanner, les présences

### Ce qui existe

`processScanEntry`, scanner d'entrée et de sortie, signature HMAC du QR,
historique, alerte intrusion après 3 QR inconnus. **Le contrôle des frais au
portail existe déjà.**

### Ce qui manque

**Le défaut le plus grave de l'application, et il est déjà en production.**

Un refus au portail est enregistré avec `type:'entry'`. Une fonction correcte
existe — `_estIncident` — mais **elle n'est appelée qu'à un seul endroit** ;
**25 lectures** filtrent encore sur `type==='entry'` brut. Conséquences
vérifiées dans le code :

| Ligne | Ce qui se passe |
|---|---|
| espace parent | **« Arrivé(e) à l'école à 7h42 »** pour un enfant renvoyé à la maison |
| validation des présences | l'enfant compte comme scanné |
| tableau du Gardien | il est compté parmi les élèves **encore dans l'école** |

Et le contrôle des frais décide sur le booléen `paid` : il renvoie chez elle une
famille qui a versé 80 %.

### 🔌 Ligne dont j'ai besoin de ChatGPT

| | Statut |
|---|---|
| `check_gate_access_status(p_sid, p_source)` | ✅ reçu (`GATE_ACCESS_CONTRACT_V1.md`) |
| Six états et leurs messages exacts | ✅ reçus |
| Cache hors ligne : **5 minutes**, puis « contrôle manuel requis » | ✅ reçu |
| **`matricule` dans la liste minimale du Gardien** | ❓ voir partie B |
| Corrections `SECURITY DEFINER` du scanner | 🔄 annoncées sur branche dédiée |

### Ce que je fais

1. **« Un refus n'est pas un passage. »** Une fonction unique répond à « qui est
   entré », et elle exclut les refus. Les **25 lectures** passent par elle.
2. Le contrôle des frais passe à `check_gate_access_status`. **Le navigateur ne
   décide plus.**
3. Les **six états visuels** : vert, bleu, orange, rouge, violet, gris — chacun
   portant **aussi un mot**. Une couleur ne doit jamais être seule porteuse d'un
   état : un orange et un rouge se confondent au soleil, sur un téléphone bon
   marché, à travers une vitre de guérite.
4. Cache **5 minutes** depuis `checked_at`, puis « contrôle manuel requis ».
   **Le cache ne convertit jamais un « en retard » en « bloqué ».**
5. Un refus pour frais impayés ne doit plus pouvoir être re-scanné dans la
   journée — `existingRefused` ne teste que `status==='refused'`.

### Comment on vérifie

Scanner un élève à jour, un élève en retard, un élève bloqué, un QR inconnu, un
QR falsifié, et hors ligne. Puis **ouvrir l'espace parent** : un enfant refusé
ne doit jamais y apparaître comme arrivé.

### Fini quand

Aucun écran ne compte un refus comme une entrée, et le statut vient du serveur.

---

# PARTIE E — Fichiers, photos et documents administratifs

### Ce qui existe

Photos d'élèves, de personnel, de personnes autorisées, cartes d'élèves, PDF de
devoirs — aujourd'hui vers **Supabase Storage** (bucket `photos`), parfois en
base64. **Cloudflare R2 n'est branché nulle part.**

Le **registre des documents administratifs — eau, électricité, assurance, loyer,
taxes, CNSS, fournisseurs — n'existe pas dans l'application.** ChatGPT l'a
construit en base ; Loms l'attend.

### 🔌 Ligne dont j'ai besoin de ChatGPT

| | Statut |
|---|---|
| `create_administrative_document(...)`, 18 types, archivage | ✅ reçu |
| `r2-upload` v4 · `r2-files` v5 · `r2-archives` | ✅ reçus |
| Codes `401 · 403 · 409 · 413 · 415 · 500`, idempotence | ✅ reçus |
| **Contradiction à trancher** | ⚠️ `ADMINISTRATIVE_DOCUMENTS_API.md` dit d'envoyer par `r2-files` action `upload` ; `TASKS.md` et `R2_IMAGE_OPTIMIZATION_API.md` imposent `r2-upload`. **Je pars sur `r2-upload`**, consigne la plus récente. |
| **Version de `r2-upload`** | ⚠️ `R2_STORAGE_API.md` dit version 1, les deux autres documents version 4 |

### Ce que je fais

1. **Un client R2 unique** : `r2-upload` pour tout envoi, `r2-files` pour
   `list`/`download`/`delete`, `r2-archives` pour Direction 1. Clé
   d'idempotence stable, progression, double-clic empêché, `reused=true` traité
   comme un succès.
2. **Le registre des documents administratifs** : fiche d'abord
   (`create_administrative_document`), pièces ensuite. Plusieurs pièces par
   dossier — recto, verso, pages, preuve de paiement. Recherche, filtres par
   type / année / fournisseur, état vide.
3. **La matrice d'accès du registre** : Direction 1 tout · Caisse le financier
   seulement · Direction 2 **jamais `is_financial=true`** · Enseignant, Parent et
   Gardien aucun accès.
4. Basculer les photos existantes vers `r2-upload`. **Aucune image en base64 en
   base.**
5. Les messages d'erreur en clair : `413` « fichier trop lourd », `415`
   « image illisible » — jamais « erreur ».

### Comment on vérifie

Envoyer une facture d'eau en deux pages, la retrouver, l'ouvrir, l'archiver, la
restaurer. Couper le réseau au milieu d'un envoi et **reprendre avec la même clé
d'idempotence** : une seule copie doit exister.

### Fini quand

La Direction enregistre une facture depuis son téléphone et la retrouve un mois
plus tard.

---

# PARTIE F — La confidentialité par rôle

> **Un contrôle dans le rendu n'est pas une sécurité. Cacher un bouton ne
> protège rien.**

### Ce qui manque — trois écarts vérifiés

1. **Le Gardien voit le motif financier.** `processScanEntry` affiche
   `FRAIS NON RÉGLÉS`, le symbole de la devise et le trimestre impayé.
2. **Direction 2 reçoit une notification financière** — `💰 Frais non réglés —
   <élève> refusé(e) à l'entrée`, **écrite en base**. La masquer à l'affichage
   ne suffirait pas.
3. **Chaque rôle tire les 47 tables** (partie B).

### 🔌 Ligne dont j'ai besoin de ChatGPT

Les messages génériques sont déjà fixés :

```
allowed     → Accès autorisé
exception   → Accès temporairement autorisé
orient      → Accès autorisé — suivi administratif requis
blocked     → Accès non autorisé — orienter vers la Caisse
unavailable → Contrôle manuel requis
```

**Il me manque une décision de Loms**, pas de ChatGPT : confirmez-vous que le
Gardien ne voit plus **ni devise ni trimestre**, seulement « orienter vers la
Caisse » ? Cela change ce que voient deux rôles.

### Ce que je fais

1. Le motif financier retiré de l'écran Gardien et de la notification
   Direction 2.
2. Le scanner financier **entièrement masqué** pour Direction 2 et Enseignant —
   et les fonctions correspondantes **vérifient le rôle elles-mêmes**.
3. Les documents qui **engagent l'école** — certificats, attestations — se
   délivrent et se **tracent**. Ils ne se téléchargent pas.

### Comment on vérifie

Six sessions, une par rôle. Pour chacune : ce qui s'affiche, **et ce qui revient
du serveur**. Une donnée absente de l'écran mais présente dans la réponse est un
échec.

### Fini quand

Aucun montant n'atteint le navigateur d'un Gardien, d'un Enseignant ou de
Direction 2.

---

# PARTIE G — Les documents officiels imprimés

### Ce qui existe

**38 documents** : bulletins, reçus, convocations, certificats, palmarès, fiches
de paie, TENAFEP, EXETAT, rapport SECOPE.

### Ce qui manque

- **10 documents sur 38 sans emblème de l'école.**
- Les PDF sont **rastérisés** (`html2canvas`, `html2pdf`). Quand une condition
  manque — largeur de fenêtre, images en retard, mémoire du téléphone — **on
  n'obtient pas une erreur, on obtient du blanc.** C'est ce qui rend le défaut
  introuvable.
- **Aucun numéro d'ordre** : pas de registre de délivrance.

### 🔌 Ligne dont j'ai besoin de ChatGPT

Une **table de registre de délivrance** — numéro séquentiel par année scolaire,
type de document, élève, date, auteur — et la RPC qui attribue le numéro **côté
serveur**. Deux tirages du même document doivent porter le même numéro, et un
duplicata se déclare sur sa face en gardant le numéro d'origine.

### Ce que je fais

1. **Passer de la photographie à l'impression.** Le navigateur sait imprimer :
   vraies polices, texte sélectionnable, « Enregistrer au format PDF » offert
   partout, fichier dix fois plus léger. Et il sait ce qu'une image ne saura
   jamais : répéter l'en-tête d'un tableau à chaque page, ne couper aucune
   ligne en deux, **ne jamais couper le bloc des signatures** — une signature
   séparée de son intitulé ne signe plus rien.
2. L'en-tête réglementaire congolais : République · **Ministère de l'Éducation
   Nationale et Nouvelle Citoyenneté** (un **réglage**, pas une constante — il a
   déjà changé) · Province · Sous-division · emblème · **SERNIE**.
3. Les signatures en **trois colonnes** : bénéficiaire à gauche · acteur ·
   autorité à droite. **Le visa imprimé n'efface jamais la ligne de celui qui
   accomplit l'acte** — le caissier signe de sa main devant la famille.
4. Le pied de page officiel est **appelé par quatorze documents** : il se
   corrige **à part**. Ce qui est partagé se corrige une fois.
5. **Ne rien afficher plutôt qu'afficher faux** : une ligne dont la valeur manque
   ne s'imprime pas. Un numéro d'agrément inventé serait pire que son absence.

### Comment on vérifie

Imprimer les 38 documents sur un jeu d'essai. Vérifier qu'aucun ne sort blanc,
qu'aucune signature n'est coupée. Et d'abord : **vérifier que le contenu
existe** — un PDF vide ne vient jamais de la mise en page.

### Fini quand

Les 38 documents sortent, portent l'emblème, un numéro d'ordre, et leurs
signatures ne se coupent jamais.

---

# PARTIE H — La tenue à 350 élèves

### Ce qui manque

**Rien n'a jamais été éprouvé sur du volume.** L'application n'a jamais vu
350 élèves.

### Ce que je fais

1. **Un jeu d'essai de 350 élèves** — noms fictifs, 14 classes, une année de
   présences, de notes et de versements. Aucune donnée réelle.
2. Mesurer, pour chacun des six rôles : temps d'ouverture, nombre de requêtes,
   poids reçu, mémoire du téléphone.
3. **La cadence** : écart aléatoire ± 25 % (sinon 400 téléphones repartent à la
   même seconde), recul progressif en cas d'échec, remise à zéro au premier
   succès. Et **du silence quand rien ne change** : reconstruire la page à
   chaque réception fait sauter la position de lecture et referme les menus,
   toutes les minutes, pour rien — **c'est cela que l'utilisateur appelle
   « instable »**.
4. Le **hors ligne** : file persistante, aucune opération jetée, âge du cache
   affiché, et **jamais de fausse confirmation**.
5. `verif-coherence.mjs` **ne s'exécute pas** aujourd'hui. Réparer son harnais —
   *la chaîne cotes → bulletin → classement n'est vérifiée par personne.*
   Attention au piège : si le stub de `createElement` ne sait pas échapper, la
   fonction d'échappement rend une chaîne vide et **tout texte échappé disparaît
   du test**.

### Fini quand

Six sessions ouvertes simultanément sur un jeu de 350 élèves, sans écran blanc,
sans attente supérieure à trois secondes.

---

# PARTIE I — Le site de l'école et `cslesage.com`

### Déjà fait

56 images rapatriées · partage WhatsApp et Google sur les cinq pages · adresse
corrigée (11 occurrences) · numéro de l'éditeur retiré.

### Ce qui manque

- **Deux dépôts sont nécessaires** : GitHub Pages n'accorde qu'un domaine
  personnalisé par dépôt. `cslesage.com` (site) et `medygoo.github.io` (app)
  demandent deux cibles.
- **« Mon site web » écrit dans le vide** : `SITE_LICENSE_KEY = '__SCHOOL_KEY__'`,
  `_SS_CENTRAL = ''`, `_SS_CKEY = ''`. Ce que la Direction règle n'atteint
  jamais le site.
- `manifest.json` porte `"scope": "./index.html"` — une portée doit être un
  **préfixe de chemin**, pas un fichier.

### 🔌 Ligne dont j'ai besoin de ChatGPT

1. L'URL du projet central, sa clé **publique**, et l'identifiant de l'école ;
2. **`cslesage.com` dans les origines autorisées Supabase et le CORS des Edge
   Functions.** Sans cela le site n'aura jamais ses annonces, avec une erreur
   CORS que personne ne pense à regarder ;
3. DNS, HTTPS, redirections, et la seconde cible d'hébergement.

### Fini quand

`cslesage.com` affiche le site, le bouton mène à l'application, et ce que la
Direction règle dans « Mon site web » se voit sur le site.

---

# PARTIE J — La recette et la publication

**Je suis responsable de la fusion vers `main` et du déploiement.**

### Ce que je fais

1. **La recette des six rôles**, sur le jeu de 350 élèves. Pour chacun : ses
   écrans, ses écritures, ses documents, son hors ligne.
2. `npm run audit` — les six outils, sortie collée dans la Pull Request. **C'est
   une preuve, pas une formalité.**
3. Une **note de version** : ce qui change, ce qui est corrigé, ce qui reste.
4. **Demander votre autorisation.** Puis fusionner, vérifier le déploiement
   GitHub Pages, et contrôler l'application en ligne.
5. La **procédure de retour arrière**, écrite avant la mise en production.

### Deux points de sécurité, à trancher avant publication

| | |
|---|---|
| **CSP absente**, `integrity` absent sur **6 scripts CDN** | Ils sont **précachés par le service worker** : une version altérée survivrait au correctif. La page porte une session Supabase. |
| `esc()` n'échappe ni `"` ni `'` | **8 attributs `onclick`** concernés. Un nom comme `N'Goma` casse le bouton. |

Le premier touche le service worker : **je le signale avant de coder**, comme la
règle l'exige.

---

# Le calendrier — 7 jours

| Jour | Parties | Pourquoi cet ordre |
|---|---|---|
| **J1** | **A** — écritures confirmées | Sans cela, tout le reste écrit dans le vide. Rien ne sert de brancher un écran qui ment. |
| **J2** | **B** — chargement par rôle | Le plus structurant. Il conditionne C, D et F, et c'est lui qui décide de la tenue à 350. |
| **J3** | **C** — argent, frais, reçus | Le point 19, la demande d'origine. Les contrats sont reçus. |
| **J4** | **D + F** — portail et confidentialité | Ensemble : la fuite financière et le refus-compté-comme-entrée sont dans la même fonction. |
| **J5** | **E** — documents administratifs et R2 | Contrats reçus, indépendant du reste. |
| **J6** | **G + H** — documents imprimés et tenue à 350 | Le jeu d'essai de 350 sert aussi à éprouver les documents. |
| **J7** | **I + J** — site, recette, publication | Recette des six rôles, autorisation, fusion. |

**Ce calendrier suppose que les réponses 🔌 arrivent au fil de l'eau.** Une seule
manquante déplace sa partie, pas les autres — c'est pourquoi elles sont
découpées ainsi.

---

# Ce que j'attends de ChatGPT — récapitulatif

| # | Demande | Bloque |
|---|---|---|
| 1 | **Le PIN** : mort, RPC dédiée, ou écriture directe conservée ? | **A · J1** |
| 2 | **La liste des tables et colonnes par rôle**, et les vues/RPC quand le filtre ne s'exprime pas en PostgREST | **B · J2** |
| 3 | La **liste minimale du Gardien** contient-elle le **matricule** ? | **B · D** |
| 4 | Distinguer **« aucune donnée »** de **« accès refusé »** | **B** |
| 5 | Le SQL des paiements — `20260802205234` absent du dépôt | **C** |
| 6 | Le **numéro de reçu** : généré par le serveur ? séquentiel par année ? | **C · G** |
| 7 | Registre de délivrance des documents officiels + RPC de numérotation | **G** |
| 8 | `r2-upload` ou `r2-files upload` ? et quelle version — 1 ou 4 ? | **E** |
| 9 | URL du projet central, clé publique, identifiant de l'école | **I** |
| 10 | **`cslesage.com` dans les origines Supabase et le CORS** | **I** |

# Ce que j'attends de Loms

| # | Décision |
|---|---|
| 1 | Le **Gardien** ne voit plus ni devise ni trimestre — seulement « orienter vers la Caisse ». Confirmez-vous ? |
| 2 | **Direction 2** ne reçoit plus aucune notification financière. Confirmez-vous ? |
| 3 | La **charte gris bleuté · blanc · or** s'applique-t-elle au site, ou seulement aux documents imprimés ? |
| 4 | Le **numéro d'agrément DGEP** et le **code école SERNIE** — ils doivent figurer sur les documents officiels, et **je ne les inventerai pas**. |
| 5 | L'autorisation de mise en production, à J7. |

---

## Une chose que ce plan ne promet pas

Sept jours suffisent à **brancher** ce qui existe et à le rendre honnête. Ils ne
suffisent pas à découper le fichier de 28 000 lignes — c'est le changement le
plus risqué du lot, parce qu'il touche tout. **Il vient après la rentrée, pas
avant.**

Et une règle qui vaut pour toute la semaine : **on ne fusionne qu'après avoir
lancé les audits.** Ils trouvent en quelques secondes une page blanche ou deux
écrans qui se contredisent. Sans eux, travailler à deux agents sur un fichier
unique est une prise de risque.
