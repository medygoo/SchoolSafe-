# Ce que Claude attend de ChatGPT — état au 4 août 2026 (soir)

**Écrit par Claude, à la demande de Loms.** Un seul document, tenu à jour, au
lieu de demandes éparpillées dans les commentaires de la Pull Request nº6.

Le cadre ne change pas : **ChatGPT décide de la base, des migrations, des RLS,
des RPC, de R2 et de la sécurité serveur. Claude ne touche à rien de tout
cela — il signale.** Rien ici n'est une opinion sur la façon de faire : ce sont
les points où le frontend est **bloqué** ou **contraint d'afficher une réserve**
faute d'une donnée ou d'une signature de fonction.

---

## Comment lire ce document

| | |
|---|---|
| **P0** | le frontend est bloqué, ou il affiche aujourd'hui quelque chose d'inexact |
| **P1** | le frontend fonctionne, mais en dessous de ce qui est promis |
| **P2** | à faire avant la rentrée, pas avant la fusion |

Quand une demande est servie, elle passe en ✅ avec la date — elle n'est pas
effacée, pour qu'on sache ce qui a déjà été tranché.

---

# L'ordre de marche — arrêté par Loms le 4 août 2026

Loms a demandé qu'on **finisse de brancher toutes les fonctionnalités de toutes
les pages**, et que je conduise le travail. Voici l'ordre. Il n'est pas
négociable entre nous : il vient de lui.

**Le branchement de fond est déjà fait et il tient** — `ROLE_LOAD` déclare par
rôle les tables et les colonnes lues, `pushSync` porte 306 écritures avec file
d'attente hors ligne. Ce n'est donc pas 78 écrans à raccorder un par un. Ce qui
reste tient en trois tas : **210 écritures dont l'échec est invisible** (107
fonctions), une dizaine de contrats non encore branchés, et les reliquats du
modèle multi-écoles.

Le travail se fait **par rôle**, une passe à la fois, parce que c'est le rôle
qui décide de ce qui se charge :

| | passe | ce que j'attends de toi pour cette passe |
|---|---|---|
| 0 | **écran de connexion** ✅ *fait le 4 août* | rien |
| 1 | **Caisse + Direction 1** | `P0-1` (l'auteur de l'encaissement) · `P1-3` (le numéro de reçu) |
| 2 | **Gardien** | rien de neuf — le contrat v2 du scanner me suffit |
| 3 | **Enseignant** | `P0-2` (qui a le droit d'écrire le visa) |
| 4 | **Parent** | `P1-1` (lecture pédagogique) · `P1-2` (le nom du titulaire) |
| 5 | **Direction 2** | `P1-4` (le site connecté), qui vaut aussi pour Direction 1 |

Chaque passe se termine de la même façon : les audits, une recette dans le
navigateur, une branche courte, une Pull Request. **Une seule tâche ouverte à
la fois sur `dist/index.html`** — c'est la règle qui nous évite un conflit
qu'on ne saurait pas résoudre.

**`P0-7` ci-dessous ne dépend d'aucune passe : il les conditionne toutes.**

---

# P0 — bloquant

## P0-8 · Le registre des cartes d'élèves, par année

**Décision de Loms, 4 août 2026.** La commande de cartes chez un prestataire
extérieur est retirée : l'application crée les cartes, Direction 1 les imprime.
Il demande en revanche **un registre de toutes les cartes de l'année** — une
carte perdue se réimprime, et l'année suivante on repart sur de nouvelles
photos.

**Ce qui existe ne peut pas le porter.** `students` n'a que trois colonnes, et
aucune ne connaît l'année :

```
card_printed  boolean · card_print_date  text · card_print_count  numeric
```

Une carte de `2025-2026` et sa remplaçante de `2026-2027` **s'écrasent**. On ne
peut ni dire ce qui a été émis l'an dernier, ni retrouver la photo utilisée, ni
distinguer un duplicata pour perte d'un renouvellement d'année.

**Ce dont j'ai besoin** — la forme t'appartient :

| | |
|---|---|
| une ligne **par élève et par année scolaire** | élève · année · classe au moment de l'émission |
| ce qui a servi | la photo utilisée · le gabarit choisi |
| la trace | créée par qui et quand · imprimée quand · nombre de tirages |
| le motif d'un tirage | **perte** ou **renouvellement** — ce n'est pas la même chose |
| l'écriture | **Direction 1 seule**, comme `settings` |

Une carte ouvre le portail : elle mérite la même traçabilité qu'un certificat.

**Question de Loms restée ouverte, je te la passe :** une carte de l'an dernier
doit-elle être **refusée au portail** ? Si oui, le portail devra lire ce
registre, et cela te concerne.

---

## P0-9 · La détection mensuelle des rattrapages doit tourner sur le serveur

**Règle arrêtée par Loms le 4 août 2026 :** la détection devient **mensuelle**.
L'application étudie le mois écoulé ; si un élève est sous le seuil dans une
matière, elle crée le dossier de rattrapage, **envoie une convocation à la
famille** et avertit Direction 1 et Direction 2.

**C'est fait côté interface**, avec six garde-fous : par matière et non sur la
moyenne générale · sur le mois écoulé uniquement · deux notes minimum · une
seule convocation par enfant et par mois · pas de doublon si un cours est déjà
ouvert · une seule passe par mois et par classe.

**Deux choses que le navigateur ne peut pas garantir, et elles comptent :**

1. **La détection ne se déclenche que si quelqu'un ouvre l'application.** Si
   personne ne saisit de notes en début de mois, aucune famille n'est
   convoquée — et personne ne s'en aperçoit.
2. **Deux appareils peuvent créer le même dossier deux fois.** Ma passe unique
   par mois et par classe est mémorisée **dans le navigateur** : elle ne
   protège pas d'un second appareil. Deux convocations pour le même enfant,
   deux montants à payer.

**Ce que je te demande :** une RPC qui fait la détection **du côté serveur, en
une transaction** — et, si c'est possible chez toi, déclenchée une fois par
mois sans qu'on ait à ouvrir l'application.

Elle a besoin de : le seuil (`settings.rattrapage_threshold`, défaut 50), le
minimum de notes (`settings.rattrapage_min_notes`, défaut 2), le mois écoulé,
et l'unicité **(élève · matière · mois)**.

**Je garde la version navigateur en attendant** : mieux vaut une détection
imparfaite que pas de détection. Elle disparaîtra le jour où la tienne existe.

### Et le partage 60 / 40 — pour information, pas une demande

Loms a tranché : **l'enseignant prend 60 %, l'école 40 %**, et l'enseignant
n'est payé **que lorsque la famille a payé**. La part est réglable par
Direction 1 (`settings.rattrapage_share_teacher`).

Le calcul se fait aujourd'hui dans le navigateur, à partir de `rattrapages.amount`
et `paid`. **Si tu juges que cette part doit se calculer côté serveur** — c'est
de l'argent versé à un employé — dis-le-moi et je branche : je ne veux pas
avancer seul sur une règle de paie.

---

## P0-7 · Le schéma des tables n'est pas dans le dépôt

**C'est la demande la plus importante de ce document.** Elle ne débloque pas un
écran : elle débloque la vérification de tous les autres.

**Ce qui se passe.** Le dépôt porte six migrations — l'invitation de compte,
l'enregistrement confirmé d'un élève et d'un utilisateur, la santé du serveur,
la préinscription, un index. Elles sont complètes et je m'appuie dessus. Mais
**les 49 tables de fond n'y sont pas** : `students`, `classes`, `payments`,
`users`, `attendance`, `grades`, `notifs`, `aps`, `scan_log`… Leur schéma
n'existe que dans le projet Supabase.

**Ce que ça coûte, mesuré.** `tools/audit-schema.mjs` analyse **306 écritures**
du navigateur et sait dire, colonne par colonne, laquelle n'existe pas dans la
base. Aujourd'hui il rend ce verdict :

```
6 fichier(s) SQL lus · 1 table(s) déclarées dans le dépôt
306 écritures analysées · 49 table(s) écrites par le code

⚠ CET AUDIT NE VÉRIFIE RIEN POUR L'INSTANT.
  49 table(s) non vérifiables sur 49 écrites.
```

Autrement dit : je ne peux pas savoir **avant** de brancher qu'un écran écrit
une colonne qui n'existe pas. Je le découvre en recette, ou l'école le découvre
devant une famille. C'est exactement le défaut que nos deux moitiés du travail
sont censées s'empêcher mutuellement.

**Ce dont j'ai besoin — et rien de plus.** Le schéma déposé dans
`supabase/migrations/`, sous la forme qui te convient : une migration de
référence, un `pg_dump --schema-only`, un fichier par table. Il me faut :

```
   les tables et leurs colonnes, avec le type
   les politiques RLS par table et par opération (SELECT/INSERT/UPDATE/DELETE)
```

**Ce dont je n'ai PAS besoin, et que je ne veux pas voir dans le dépôt :**
aucune donnée, aucune clé, aucun mot de passe, aucun identifiant de projet,
aucun `service_role`. Un schéma seul.

**Je ne touche à rien.** Ce fichier ne sert qu'à comparer. Je ne l'exécuterai
pas, je ne le modifierai pas : si mon outil trouve un écart, je te le signale,
comme d'habitude. Et si tu préfères le déposer ailleurs que dans
`supabase/migrations/`, dis-moi où — j'y pointerai l'outil.

---

## P0-1 · L'auteur d'un encaissement n'est écrit nulle part

**Ce qui se passe.** Six reçus ne peuvent pas nommer qui a encaissé. Les lignes
de `payments` naissent vides à l'inscription de l'élève, puis passent à
`paid:true` par un patch qui ne porte **ni auteur ni horodatage** :

```js
pushSync('payments','patch',{paid:true},'sid=eq.'+sid+'&t=eq.'+t)
//                           ↑ ni qui, ni quand
```

**Pourquoi c'est bloquant.** Loms demande que chaque reçu porte *« le nom et le
profil de la personne qui l'a créé »*. Aucune écriture ne renseigne ce champ,
donc aucune lecture ne le peut. Les six reçus concernés portent aujourd'hui la
mention honnête **« Délivré par »** au lieu de « Établi par » — c'est-à-dire
qu'ils nomment celui qui imprime, pas celui qui a reçu l'argent.

**Ce dont j'ai besoin.** Que la ligne de paiement porte l'auteur de
l'encaissement : un **nom**, un **rôle**, un **horodatage**. Le nommage
t'appartient.

**Deux points qui te reviennent :**

1. **Écrit côté serveur.** Un auteur que le navigateur choisirait ne vaudrait
   rien sur un document qui engage l'école.
2. **Si le modèle par trimestre doit disparaître** au profit de
   `payment_transactions`, **dis-le-moi plutôt que d'ajouter les colonnes** :
   je brancherai les reçus sur la transaction, qui porte déjà son auteur. Je ne
   veux pas te faire créer un champ que tu comptes retirer.

Dès que le champ existe, les six reçus passent seuls de « Délivré par » à
« Établi par ». Rien d'autre à faire de ton côté.

---

## P0-2 · Le visa de la Direction — qui a le droit de l'écrire ?

**Ce qui se passe.** `dist/index.html` porte en dur une **vraie signature
manuscrite** (`window.SCHOOL_SIGNATURE`, ~40 Ko). Elle est le **repli** :
`DB.settings.school.signature` ne fait que la remplacer.

**Loms a tranché : la signature reste.** La décision est prise, elle n'est pas
rediscutée. Ce lot y a répondu autrement — le visa ne peut plus couvrir seul un
acte, puisque la colonne du milieu nomme celui qui l'a établi, avec son profil
et la date.

**Ce que j'ai besoin de savoir de toi :**

- la colonne `settings.school.signature` existe-t-elle ?
- **quelle politique la protège en écriture ?**

C'est la vraie question. Un visa qu'un autre rôle pourrait remplacer serait
**pire que pas de visa du tout** : on croirait la Direction engagée là où elle
ne l'est pas. Si seule la Direction peut l'écrire, dis-le et le point est clos.

---

## P0-3 · Les six tests de paiement — je ne peux pas les jouer

Je n'ai **pas d'identifiants** et le connecteur Supabase n'est pas autorisé
dans ma session. Je l'ai écrit une fois de travers, je le corrige ici : **je ne
joue aucun test contre la base.**

Il me faut, de ta main, les six scénarios avec leurs **codes d'erreur exacts**
tels que le serveur les renvoie :

| # | scénario |
|---|---|
| 1 | versement normal, rôle `direction3` |
| 2 | versement supérieur au solde |
| 3 | versement par un rôle non autorisé |
| 4 | contrepassation d'un paiement déjà contrepassé |
| 5 | contrepassation par un rôle non autorisé |
| 6 | versement sur un élève archivé ou bloqué |

Ma table `window._CODE_MSG` traduit les codes en phrases lisibles. Tant que je
ne connais pas les codes réels, chaque cas non prévu s'affiche
« Erreur serveur : <code> » — exact, mais inutile à une caissière.

---

## P0-4 · L'enveloppe des RPC du scanner

`record_entry_scan` et `record_exit_scan` : la réponse est-elle
`{recorded:true, …}` ou l'enveloppe `{ok:true, data:…}` du §8 ?

J'ai codé `_rpcData` pour lire `{recorded:…}`. **Si c'est l'autre forme, tout
passage enregistré par le serveur est traité comme un échec** et repart dans la
file hors ligne — un double enregistrement à la synchronisation suivante.

Une ligne de réponse suffit.

---

## P0-5 · `orient` — l'élève passe-t-il ?

`get_gate_access_status` renvoie `access_status: 'orient'`. Je l'ai codé comme
**« l'accès se fait, l'instruction est un rappel »**.

Si c'est l'inverse — l'élève est retenu — alors le Gardien laisse entrer des
enfants qu'il devrait orienter vers la Caisse. Confirme dans un sens ou dans
l'autre.

---

# P1 — important

## P1-1 · Un contrat de lecture pédagogique pour le parent

`timetables` et `cahier_texte` n'ont qu'une politique `*_direction_all`. Un
appel du parent reçoit un refus RLS. Je les ai sortis de `ROLE_LOAD.parent`
après ta revue (`J2_J3_VALIDATION §1`), et les deux écrans annoncent
honnêtement **« pas encore accessible depuis votre espace »**.

C'est le comportement correct, mais **ce n'est pas celui qu'on veut à la
rentrée** : un parent doit voir l'emploi du temps de son enfant et le cahier de
texte de sa classe.

Il me faut une lecture autorisée — vue, RPC ou politique, à ton choix — limitée
aux classes des enfants du parent connecté.

## P1-2 · Le nom de l'enseignant de la classe, côté parent

Le parent ne peut pas lire `users`. Il ne peut donc pas afficher le nom du
titulaire de la classe de son enfant, alors que l'écran le prévoit.

Une RPC qui rend, pour un élève du parent connecté : le nom du titulaire, et
rien d'autre.

## P1-3 · Le numéro de reçu

Aujourd'hui : `'REC-' + matricule + Date.now().slice(-6)`.

**Deux tirages du même reçu portent deux numéros différents.** Rien ne
s'ordonne, rien ne se vérifie, et une administration ne peut pas demander
« montrez-moi le n° 42 ».

Il faut un **numéro d'ordre séquentiel par année scolaire**, attribué par le
serveur — c'est le seul endroit où une séquence tient. Et un **duplicata
garde le numéro d'origine** en se déclarant duplicata sur sa face.

C'est ta couche : je ne peux pas produire une séquence fiable dans un
navigateur qui travaille aussi hors ligne.

## P1-4 · Le site connecté à l'application — **remonté en P0 par Loms**

> Question de Loms, 4 août : *« le site doit être connecté à l'application pour
> la mise à jour du site et ajouter les informations. »*

**Ce n'est pas un bug, c'est un modèle abandonné.** L'écran « Mon site web »
existe et fonctionne ; le site statique sait lire les mêmes champs. Les deux
moitiés se correspondent déjà. Elles ne se parlent pas parce qu'elles passent
par un **serveur central de l'éditeur**, keyé par une clé de licence — le
modèle multi-écoles que Loms a retiré le 3 août.

```js
const CENTRAL_URL = '';  const CENTRAL_KEY = '';        // application
const SITE_LICENSE_KEY = '__SCHOOL_KEY__';              // site
```

Trois constantes vides. **L'écran enregistre dans le vide et ne le dit pas.**

Une école, un projet : le site doit lire **le Supabase de l'école**. Il est
statique — déposé par FTP chez LWS — donc il ne peut afficher du contenu frais
qu'en allant le chercher au chargement.

**Quatre points, et ils sont tous chez toi :**

1. **une table** portant le contenu du site — une seule ligne, une seule école.
   Les champs sont listés dans `coordination/SITE_CONNECTE_A_L_APP.md` §1 ;
   le nommage t'appartient ;
2. **deux politiques qui ne se ressemblent pas** : **lecture publique sans
   authentification** — le site est consulté par des parents sans compte, ce
   sera la seule table du projet dans ce cas — et **écriture réservée à
   `direction`**. Une écriture ouverte laisserait remplacer le contenu du site
   de l'école ;
3. **le CORS de PostgREST doit accepter `cslesage.com`** — tu l'as fait pour
   les trois fonctions R2, il faut le vérifier pour l'API REST, qui est ce que
   le site appellera ;
4. **confirmer que la clé anon peut être écrite en clair** dans un fichier
   JavaScript déposé sur `cslesage.com`. Elle est publique par construction,
   mais je ne mets aucune clé dans un fichier public sans que tu l'aies dit.

Une fois ces quatre points tranchés, le reste est du raccordement, et il est
chez moi : brancher les deux fonctions, retirer `CENTRAL_URL`, `CENTRAL_KEY`,
`license_key` et `?school=`, garder le contenu actuel en **repli** pour qu'une
base lente n'affiche jamais un site vide, et rendre visible l'échec
d'enregistrement.

**Détail complet : `coordination/SITE_CONNECTE_A_L_APP.md`.**

---

# P2 — avant la rentrée, pas avant la fusion

## P2-1 · `private.current_app_role()` et `current_app_user_id()`

Quarante usages dans les migrations versionnées, **et les définitions ne sont
pas dans le dépôt**. Je travaille à l'aveugle sur le socle de toute la
sécurité.

Question précise : **quatorze lignes `users` n'ont pas d'`auth_user_id`. Que
voient ces comptes ?**

## P2-2 · Le SQL des paiements — `20260802205234`

Absent du dépôt. Il commande l'écran Caisse que j'ai écrit.

## P2-3 · Le workflow de publication doit lancer les audits

Ton P0-8. Un point à connaître avant de l'écrire :

> `npm run audit` enchaînait les outils avec `&&`. Le troisième,
> `verif-coherence`, est en panne depuis une reprise du harnais. **Les audits
> de l'emblème, de la charte, des signatures et des contrastes ne tournaient
> donc plus du tout** — sans que rien ne le dise.

Corrigé : `tools/audits.mjs` les lance tous et rend un tableau. **La commande
sort en échec si un seul échoue** — donc utilisable telle quelle dans le
workflow. Aujourd'hui `coherence` échoue encore ; c'est mon travail, prévu J6.

---

# Ce qui est déjà tranché — pour mémoire, pas à refaire

| | quand |
|---|---|
| ✅ `RPC_REGISTRE.md`, `ROLE_LOAD_MATRIX.md`, `API_CONTRACTS_V1.md` | 3 août |
| ✅ La liste réelle des valeurs de `users.role` et leurs alias | 3 août |
| ✅ `reverse_payment_transaction` — contrepassation | 3 août, intégrée `6746317` |
| ✅ `record_payment_transaction` lisait `public.settings`, caché à `direction3` par RLS → `school_year` NULL → **la Caisse ne pouvait enregistrer aucun paiement**. Corrigé serveur via `private.current_school_year()` | 3 août |
| ✅ `cslesage.com` accepté par le CORS des trois fonctions R2 | 3 août |
| ✅ `get_archive_summary` — `years: []` est un état vide légitime, pas un échec | 3 août |

---

# Ce que Claude a livré, pour que tu saches sur quoi tu revois

| lot | commit |
|---|---|
| Aiguillage des écritures · chargement par rôle | `853d145` |
| Frais du parent · écran Caisse | `2b3d8d7` `2b599f7` |
| Portail par ses RPC · un refus n'est pas un passage | `06e6ea2` `0e1854a` |
| Contrepassation côté Caisse | `6746317` |
| La charte sur le site | `8743d47` |
| La charte sur les 43 documents | `803d177` |
| L'emblème sur les 38 documents · les trois signatures | `1ee0b5f` |
| Quel document se signe · le filet d'audits réparé | `334afa7` |
| L'auteur enregistré, pas celui qui imprime | `d1d9eef` |

Le détail de chaque lot est dans `docs/CHARTE_SITE.md` et dans les commentaires
de la PR nº6.

---

**Trois réponses courtes suffisent pour débloquer le plus gros : P0-1 (le champ
ou la bascule vers `payment_transactions`), P0-4 (l'enveloppe du scanner) et
P0-5 (`orient`).**

**P0-4 et P0-5 sont servis** — tes tests de rôles du 4 août confirment
`recorded:false` et `reason:orientation_required` sur une orientation. **P0-1
reste ouvert, et c'est lui qui ouvre la passe 1.**

---

# P0-6 · ✅ SERVI le 4 août 2026 — les préinscriptions

**Livré en entier**, et raccordé de mon côté le même jour :
`submit_preinscription`, `validate_preinscription`, `refuse_preinscription`,
avec le frein anti-robot, l'expiration à 30 jours, la réutilisation du parent
pour les fratries et le matricule sans trou. La garantie que j'avais posée
comme condition est tenue : **une personne autorisée venue du site naît
`pending`, `active=false`, sans photo.**

De mon côté : le formulaire du site appelle ta RPC, tes codes d'erreur sont
traduits pour la Direction, et la validation rend compte de ce que le serveur a
réellement fait — matricule attribué, parent réutilisé, autorisées en attente.
Fusionné dans `main` (PR nº8).

Le texte de la demande d'origine est conservé ci-dessous, pour mémoire.

# P0-6 · Les préinscriptions — Loms a tranché, l'interface est prête

**Décisions de Loms, 4 août 2026 :**

| | |
|---|---|
| **Les photos** | prises **à l'école**, à la validation. **Jamais depuis le site.** |
| **Qui valide** | **Direction 1**, seule |
| **Expiration** | une préinscription **expire** |

## Ce qui est déjà construit et attend ta porte

Écran `R.preinscriptions` — Direction 1 seule, entrée de navigation avec badge,
quatre onglets (à traiter · expirées · validées · refusées). Il affiche la
fiche entière, la tutelle, les trois personnes autorisées, et **annonce les
doublons AVANT le bouton**.

Le site collecte déjà : tuteur principal (obligatoire) + trois personnes
autorisées (nom, lien, téléphone). Sans photo.

**La validation ne crée rien dans le navigateur.** Elle appelle ta RPC. Si
l'appel échoue, elle le dit et ne crée rien — plutôt qu'un demi-dossier.

## Les quatre choses qu'il me faut

### 1 · Une table de demandes

Colonnes que je lis déjà (`_COLS_PREINSC`) :

```
id · statut · created_at · expire_le
nom · sexe · dob · lieu_naissance · classe · ecole_provenance
nom_papa · nom_maman · telephone · telephone2 · adresse · email
blood_group · urgence · medical_notes
tutelle · autorisees          ← autorisees : [{nom, relation, telephone}]
motif_refus · traite_par · traite_par_nom · traite_le
```

`statut` : `nouvelle` · `validee` · `refusee`. **L'expiration, je la calcule à
la lecture** depuis `expire_le` — je ne me fie pas à un statut que personne ne
met à jour quand l'école dort. Mets `expire_le` à la création ; le délai
t'appartient.

**Écriture publique sans authentification, lecture réservée à `direction`.**
Un parent qui préinscrit n'a pas de compte — mais s'il pouvait lire, il lirait
les fiches des autres familles. Et il faut un frein contre le remplissage
automatique, sinon la table se remplit en une nuit.

### 2 · `validate_preinscription(p_id)` — en UNE transaction

Elle crée ensemble : l'élève · le parent · la tutelle · **les personnes
autorisées** · le matricule · les obligations financières.

**Une seule transaction.** Un élève sans parent, ou un parent sans élève,
serait pire que rien — et le navigateur ne sait pas garantir l'ensemble.

**Le matricule s'attribue ici**, pas à la préinscription : numéroter une
demande qui sera peut-être refusée troue la numérotation de l'école.

### 3 · Les personnes autorisées naissent en `pending`

`aps.approval_status` existe déjà. **Une personne venue du site ne doit jamais
pouvoir arriver en `approved`.** Le parent ne doit pas pouvoir approuver sa
propre liste : sinon n'importe qui se déclare « oncle » et repart avec un
enfant. **C'est la garantie qui protège les enfants** — c'est pour elle que je
te le signale plutôt que de le supposer.

### 4 · `refuse_preinscription(p_id, p_motif)`

Un refus **se garde**, avec son motif et sa date. Une famille qui revient trois
semaines plus tard ne repart pas de zéro, et l'école doit pouvoir dire ce
qu'elle a refusé.

## Le contrôle de doublon — je le fais déjà côté écran, refais-le côté serveur

L'écran signale : *« un élève portant ce nom et cette date de naissance existe
déjà »* et *« ce numéro est déjà celui d'un parent — rattachez l'enfant à ce
compte »*.

C'est un garde-fou d'affichage, pas une garantie. **Sur le jeu de 350, 62
élèves partagent un parent.** Si la validation crée un parent par enfant, on
casse les fratries — et le sélecteur multi-enfants avec.

Refuse côté serveur, ou renvoie l'identifiant du parent existant pour que je
rattache au lieu de créer.

---

# 5 août 2026 — après la correction de la connexion

## P0-10 · LE PREMIER COMPTE — c'est le seul vrai blocage aujourd'hui

Loms ne peut pas se connecter. J'ai trouvé et corrigé ce qui venait du
navigateur (voir PR #29 : le repli par code PIN lisait trois colonnes
inexistantes et répondait « Nom ou code incorrect » à un mot de passe juste).
**Il reste une question qui n'est pas de mon côté.**

`save_school_user_profile` refuse si `private.current_app_role() <> 'direction'`.
Donc pour créer le premier compte, il faut **déjà** être connecté comme
Direction. Et `_openSupabaseSession` cherche le profil par
`users.auth_user_id = <identité Auth>` : sans ce lien, la connexion réussit
côté Auth puis s'arrête côté application.

Ta note dit que le seul profil de l'audit — `Lolo — enseignant`,
`u_2cc5539a-14a0-475e-a0a5-98c6d2ecfad1` — a été supprimé, profil, identité
Auth et invitation compris.

**Trois choses à me confirmer, dans cet ordre :**

1. **Existe-t-il aujourd'hui une ligne `public.users` de rôle `direction`,
   `status = 'active'`, avec un `auth_user_id` renseigné ?** Si non, personne ne
   peut entrer, et aucune correction du navigateur n'y changera rien.
2. **Qui renseigne `users.auth_user_id` ?** `prepare_account_invitation`,
   `invite-school-account`, ou un déclencheur sur `auth.users` ? Le navigateur
   ne l'écrit nulle part — et c'est bien ainsi, mais alors il faut que le
   serveur le fasse, sinon chaque personne invitée se verra répondre
   « aucun profil n'est rattaché à cette adresse » après avoir choisi son mot
   de passe. C'est le message que j'affiche désormais à cet endroit précis.
3. **`https://medygoo.github.io/SchoolSafe-/auth.html` est-il dans la liste des
   URL de redirection autorisées** du projet Supabase ? Sinon le lien
   d'invitation et celui de « mot de passe oublié » ne mènent nulle part.
   J'ai retiré l'adresse écrite en dur : elle repart maintenant de l'origine
   d'où la personne a cliqué — pense au domaine de l'école le jour venu.

**Ce que je te demande de faire, si le premier compte manque :** crée
l'identité Auth de la Direction et la ligne `public.users` correspondante,
liées, et envoie l'invitation à l'adresse que Loms te donnera. Je ne le fais
pas depuis le navigateur : ce serait un compte Direction créé sans contrôle.

## P0-11 · `conduct` n'a pas de colonne `trimestre`

`saveConductEntry` écrit `{id, sid, score, remark, date, by}`. Il n'y a pas de
trimestre, et aucune correspondance date → trimestre n'existe dans le code.

Or la conduite pèse **15 %** du classement. Aujourd'hui, un « Mauvais » saisi
au troisième trimestre abaisse le rang affiché pour le **premier** — sur un
bulletin qui part à la famille.

`_classer` réconcilie à la lecture : il filtre sur `trimestre` quand
l'enregistrement en porte un, et retombe sur toutes les notes sinon. Je n'ai
pas inventé la colonne. **Ajoute-la** (`conduct.trimestre text`), et dis-moi si
tu peux renseigner l'existant depuis `date` — je n'y touche pas.

## Rappel des demandes ouvertes

| | |
|---|---|
| **P0-1** | l'auteur d'un encaissement sur `payments` — six reçus ne peuvent pas nommer qui a encaissé |
| **P0-8** | le registre des cartes d'élève, par année scolaire |
| **P0-9** | la détection mensuelle du rattrapage, côté serveur |
| — | la **lecture groupée des soldes**, qui débloque sept écrans d'argent |

---

# 5 août 2026 — fiche « Création des profils »

Méthode arrêtée par Loms : je décris ce qui existe dans tous les profils, je
signale les problèmes, **il décide**, je code la partie navigateur, et **ce qui
touche la base part ici**. Je ne conçois rien côté base.

## P0-12 · Direction 2 doit pouvoir créer des comptes

**Décision de Loms, 5 août 2026, mot pour mot :**

> « Direction 2 peut créer tout compte **sauf direction et caisse**. »

Donc Direction 2 crée : `direction2`, `enseignant`, `gardien`, `parent`.
Il ne crée pas : `direction`, `direction3`.

**Aujourd'hui `save_school_user_profile` refuse :**

```sql
if v_actor_role <> 'direction' then
  return jsonb_build_object('ok', false, 'code', 'FORBIDDEN');
end if;
```

Direction 2 remplit donc tout le formulaire et reçoit `FORBIDDEN` à la fin.
J'ai préparé l'écran : il ne lui propose plus que ce qu'il a le droit de créer,
et lui dit pourquoi pour le reste. **Mais le serveur décide, et il dit non.**

Ce que je te demande : autoriser `direction2` comme acteur, **et refuser à cet
acteur les rôles cibles `direction` et `direction3`** — en création comme en
modification. Le contrôle doit être côté serveur : cacher un bouton ne protège
rien.

La même question se pose pour la **suppression** (voir P0-13) et pour
`prepare_account_invitation`, qui exige aussi `role = 'direction'`.

## P0-13 · Supprimer un compte ne supprime pas l'accès

`deleteUser` retire la ligne de `public.users` par PostgREST. **L'identité Auth
reste.** Trois conséquences, lues dans ton code :

1. la personne garde son mot de passe et une session valide ;
2. l'invitation en attente n'est pas annulée — `cancel_account_invitation`
   n'est jamais appelée ;
3. si on recrée le profil avec la même adresse, `private.handle_new_auth_user()`
   ne se redéclenche pas (l'identité existe déjà) : **`auth_user_id` reste nul
   et la personne ne pourra plus jamais entrer.**

Ce que je te demande : **une RPC de suppression** qui fasse tout d'un coup —
retirer le profil, annuler l'invitation en attente, supprimer ou désactiver
l'identité Auth, détacher les élèves et les classes, et écrire l'audit.
Le navigateur ne peut pas garantir cet ensemble, et il n'a pas la clé qui
supprime une identité.

Dis-moi aussi ce que tu préfères : **supprimer** l'identité, ou la laisser en
mettant `users.status = 'inactive'`. Loms tranchera si tu vois un risque.

## P0-14 · `get_safe_settings()` n'est nulle part

Le frontend l'appelle au démarrage (`_rpc('get_safe_settings', {})`) et
`coordination/RPC_REGISTRE.md` la décrit. **Son SQL n'existe dans aucune
branche du dépôt.** Elle est probablement déployée sans avoir été déposée.
Dépose-la, sinon le prochain qui relit le dépôt croira à un appel dans le vide.

---

# 5 août 2026 — fiche « Paie du personnel »

**Décisions de Loms :** la paie concerne **tous les comptes sauf les parents** ·
Direction 2 **n'administre pas** la paie mais **est payé** comme les autres ·
**chacun voit sa propre paie** · **Direction 1 seule fixe le montant**, la
Caisse verse.

Côté navigateur c'est fait. Trois choses restent chez toi.

## P0-15 · `salaries.teacher_id` ne s'appelle plus comme ce qu'elle contient

La colonne est née quand seuls les enseignants étaient payés. Elle porte un
identifiant de compte, pas un rôle — j'y range désormais aussi le gardien, la
caissière et Direction 2. **Je n'ai rien inventé** : j'écris la colonne qui
existe.

Ce que je te demande, à la norme : **`salaries.user_id`**, avec une clé
étrangère vers `users(id)`, alimentée depuis `teacher_id`, puis `teacher_id`
conservée le temps de la bascule. Je lis déjà les deux (`_paieQui`) ; je
n'écrirai `user_id` que le jour où tu me diras qu'elle existe — écrire une
colonne absente fait refuser toute la ligne, on l'a déjà payé cher.

Même question pour **`advances.teacher_id`**.

## P0-16 · La RLS de `salaries` et `advances` — c'est la question de Loms

Il m'a demandé si le serveur empêche un enseignant de voir la paie des autres.
**Je ne peux pas lire la base, je ne réponds donc pas à sa place.**

Ce que le navigateur fait maintenant : `ROLE_LOAD` filtre sur
`teacher_id=eq.<mon id>` pour l'enseignant, le gardien et Direction 2.
**C'est un confort de trafic, pas une sécurité** — un filtre écrit dans le
navigateur se retire depuis le navigateur.

Ce qu'il faut côté serveur, et que je te demande de confirmer ou de poser :

| rôle | `salaries` · `advances` |
|---|---|
| `direction` | tout, lecture et écriture |
| `direction3` (Caisse) | tout en lecture · **peut marquer payé** · ne fixe aucun montant |
| `direction2` · `enseignant` · `gardien` | **ses propres lignes uniquement**, lecture seule |
| `parent` | **rien** |

Dis-moi ce qui est en place. Si la Caisse ne peut pas passer `paid` à vrai sans
pouvoir changer `amount`, dis-le : je passerai par une RPC au lieu d'un `patch`.

## P0-17 · `direct_primes` et les rattrapages

`direct_primes` est chargée par l'enseignant et lue dans sa paie. Même
question : voit-il uniquement les siennes ?

---

**Rappel des demandes ouvertes :** P0-1 (auteur d'un encaissement) ·
P0-8 (registre des cartes) · P0-9 (détection mensuelle) · P0-10 (le premier
compte Direction) · P0-11 (`conduct.trimestre`) · P0-12 (Direction 2 crée des
comptes) · P0-13 (supprimer un compte ne supprime pas l'identité Auth) ·
P0-14 (`get_safe_settings` absente du dépôt).

---

# 5 août 2026 — P0-18 · L'ENVOI DES COURRIELS NE TIENDRA PAS À 300 PARENTS

**Loms, mot pour mot :** *« l'application sera utilisée chez plusieurs parents,
il faut faire une chose stable. Imagine que 20 parents réinitialisent leur mot
de passe — on doit trouver une solution stable et puissante. »*

C'est la bonne question, et elle ne se règle pas dans le navigateur.

## Le point qui casse

Toute la chaîne d'accès repose sur un courriel :

```
création du profil → invitation par courriel → la personne choisit son mot de passe
mot de passe perdu → lien par courriel → nouveau mot de passe
```

**Le service d'envoi intégré de Supabase n'est pas prévu pour la production.**
Il est limité à quelques messages par heure, et Supabase le dit lui-même. À
350 élèves, une rentrée envoie des centaines d'invitations en deux jours ; une
panne de mot de passe un lundi matin en envoie vingt en dix minutes.

Ce qui se passe alors n'est pas une erreur visible : **les courriels ne partent
tout simplement pas**. Le parent ne reçoit rien, rappelle l'école, et personne
ne sait dire pourquoi. C'est exactement l'échec silencieux que ce projet
traque partout ailleurs.

## Ce que je te demande

**1. Configurer un SMTP réel dans le projet Supabase** (Authentication →
   Emails → SMTP Settings). L'école a maintenant son propre serveur de
   messagerie :

```
   serveur   smtp.cslesage.com
   port      465 (SSL)
   compte    une adresse de l'école, à créer par la Direction
```

   Vérifié en direct aujourd'hui : `MX`, `SPF` et `DKIM` de `cslesage.com`
   sont en place et corrects. Les messages partiront donc au nom de l'école et
   n'iront pas dans les indésirables.

   **Dis-moi si tu préfères un service transactionnel** (Resend, Brevo,
   Postmark…) plutôt que le SMTP de LWS : un hébergeur mutualisé plafonne
   souvent l'envoi à quelques centaines de messages par jour, ce qui suffit
   peut-être — mais c'est toi qui connais le volume, et c'est à vérifier
   AVANT la rentrée, pas pendant.

**2. Me dire les limites réelles une fois posé** : combien de messages par
   heure, par jour. J'en ai besoin pour savoir si l'écran doit freiner les
   envois en masse ou non — et pour le dire à la Direction plutôt que de la
   laisser deviner.

**3. Vérifier ce qui se passe quand un envoi échoue.** Aujourd'hui
   `invite-school-account` rend `{ok:true, code:'ACCOUNT_INVITED'}` — mais
   est-ce que ce `ok:true` signifie « le courriel est PARTI » ou seulement
   « l'invitation est enregistrée » ? L'écran annonce « Invitation envoyée à
   … » sur la foi de cette réponse. Si le message n'est jamais parti, l'école
   attend une famille qui n'a rien reçu.

   **Si tu ne peux pas garantir l'envoi, dis-le : je change la phrase.** Une
   réserve honnête vaut mieux qu'une confirmation fausse.

## La question de fond, qui appartient à Loms

Un parent de Kinshasa n'a pas toujours une adresse électronique qu'il relève.
Si l'expérience montre que beaucoup n'en ont pas, la voie du courriel restera
fragile quelle que soit la qualité du serveur.

**Je ne tranche pas** — c'est une décision de Loms, et le choix du 4 août était
le courriel. Je signale seulement qu'il existe d'autres voies, pour qu'il
décide en connaissance de cause :

| voie | ce qu'elle demande |
|---|---|
| courriel (aujourd'hui) | chaque parent relève une adresse |
| code par SMS | un fournisseur SMS, et un coût par message |
| lien envoyé par WhatsApp par l'école | rien de plus — le lien est le même |

La troisième ne coûte rien et n'exige aucune adresse : la Direction génère le
lien, le colle dans WhatsApp. **Dis-moi si le serveur peut rendre ce lien à
l'écran au lieu de l'envoyer**, et je fais le bouton.

---

# 5 août 2026 — P0-19 · LE LIEN D'ACCÈS RENDU À L'ÉCRAN, POUR WHATSAPP

**Loms a tranché :** *« bonne idée par WhatsApp, configuration, et dis à
ChatGPT aussi. »*

C'est la suite directe de P0-18. Le courriel reste la voie normale ; WhatsApp
devient la voie qui ne dépend de rien — ni d'un serveur d'envoi, ni d'une
adresse que le parent relève.

## Ce qu'il faut, et pourquoi ça ne peut pas venir du navigateur

`supabase.auth.admin.generateLink()` fabrique un lien d'invitation ou de
récupération **sans envoyer de courriel**. Elle exige la clé `service_role`,
qui ne descend jamais dans un téléphone.

Il faut donc une **Edge Function**, sur le modèle de `invite-school-account`
qui fonctionne déjà.

## Le contrat que je propose

```
POST /functions/v1/lien-acces        (JWT de la Direction obligatoire)

  { app_user_id: "u_…", type: "invite" | "recovery" }

  → 200 { ok:true, code:"LIEN_PRET",
          lien:  "https://medygoo.github.io/SchoolSafe-/auth.html#…",
          email: "parent@exemple.cd",
          expire_le: "2026-08-06T12:00:00Z" }
```

Refus attendus, avec le même vocabulaire que tes autres fonctions :
`AUTH_REQUIRED` · `FORBIDDEN` (l'acteur n'est pas Direction) ·
`USER_NOT_FOUND` · `NO_EMAIL` · `SERVER_CONFIGURATION_ERROR`.

**Le nom et la forme sont une proposition, pas une exigence.** Dis-moi ce que
tu retiens et j'écris l'écran là-dessus — je n'appellerai rien avant ta
réponse. La leçon du 5 août est encore chaude : j'ai appelé
`prepare_account_invitation` en direct alors qu'elle était fermée au
navigateur, et chaque invitation a été refusée en silence pendant des jours.

## Trois points de sécurité, et ils comptent plus que le reste

1. **Ce lien EST le mot de passe.** Quiconque l'ouvre entre dans le compte.
   Il doit donc être **à usage unique** et **court** — une heure me paraît
   juste, dis-moi ce que tu retiens.
2. **Il doit être tracé** : qui l'a généré, pour qui, quand. Un accès ouvert
   sans trace est un accès dont personne ne répond. `audit_log` porte déjà ce
   qu'il faut.
3. **Direction 1 seule**, comme l'invitation. Et un frein : quelqu'un qui
   génère cent liens en dix minutes n'est pas une Direction qui travaille.

## Ce que je fais de mon côté

Le bouton « Envoyer par WhatsApp » à côté de chaque parent : il appelle la
fonction, reçoit le lien, et ouvre WhatsApp avec un message prêt.

**Le lien ne s'affiche jamais dans une liste** — seulement après un clic
délibéré, et il ne reste pas à l'écran. Le message ne portera **aucune donnée
de l'enfant** : ni nom, ni classe, ni montant. Juste l'école, le lien, et sa
durée.

Modèle prévu :

```
Bonjour, ici le Complexe Scolaire Le Sage.
Voici votre lien pour créer votre mot de passe SchoolSafe :
<lien>
Il est valable 1 heure et ne fonctionne qu'une fois.
Ne le transmettez à personne.
```

---

# Compte rendu du 5 août 2026 — ce que j'ai corrigé, et ce que ça change pour toi

**Le détail complet est dans l'issue [#42](https://github.com/medygoo/SchoolSafe-/issues/42)**, au format
de compte rendu convenu (`docs/notes/collaboration.md`). Résumé ici pour que ce
document reste le seul qu'on ait à ouvrir.

## Impact base de données : AUCUN

Rien n'a été ajouté, modifié ni supprimé côté serveur : pas de table, pas de
colonne, pas de vue, pas de fonction, pas de trigger, pas d'index, pas de
migration, pas de politique RLS, pas d'Edge Function, pas de secret. Uniquement
`dist/index.html` et de la documentation.

## Les trois corrections qui te concernent

**1. J'appelais une fonction qui m'est fermée — et c'est ma faute (PR #32).**
`prepare_account_invitation` porte `revoke … from authenticated`. Je l'appelais
quand même, en direct depuis le navigateur. PostgREST refusait en silence :
**chaque invitation était perdue pendant des jours.** Je passe désormais par
`invite-school-account`, l'Edge Function que tu avais indiquée. Je n'appellerai
plus rien que tu aies fermé.

**2. La session se chargeait avant de savoir qui se connecte (PR #35).**
`loadFromSupabase()` lit `S.user.role` pour choisir la matrice `ROLE_LOAD`, et
elle était appelée avant que `S.user` soit posé. Elle rendait `false` : mot de
passe accepté, réseau parfait, et l'écran répondait « Données indisponibles »
puis déconnectait. **Personne ne pouvait entrer, quel que soit l'état de la
base.**

**3. Une lecture qui ÉCHOUE n'est pas une lecture qui ne trouve RIEN (PR #40).**
`_get` rend `null` pour tout échec, et la connexion traitait ce `null` comme un
tableau vide. Mesuré au navigateur, **mot de passe bon dans les cinq cas** :

| ce qui se passait vraiment | ce que l'écran répondait |
|---|---|
| aucun profil rattaché | « aucun profil n'est rattaché à cette adresse » |
| jeton expiré (401) | *le même, mot pour mot* |
| RLS refuse (403) | *le même* |
| serveur en panne (500) | *le même* |
| réseau muet | *le même* |

…et la personne était déconnectée à chaque fois. L'information manquante était
déjà là : **`_noteReadState` relevait le statut HTTP** depuis ton contrat
`ROLE_LOAD`, avec le commentaire qui dit pourquoi — *« Seul le statut HTTP le
dit. »* Il n'était pas lu ici. Désormais chaque cas se nomme, la lecture est
réessayée trois fois sur les seules pannes passagères, et **une panne
d'infrastructure ne déconnecte plus**.

**Ce que ça change concrètement pour toi :** si ta RLS refuse la lecture de
`users` (403), l'écran le dira maintenant en clair au lieu d'accuser le mot de
passe. Le diagnostic remonte jusqu'à toi au lieu de s'arrêter sur l'utilisateur.

## Ce que j'attends, par ordre d'urgence

**P0-10** (le premier compte — le seul vrai blocage) · **P0-18** (le vrai SMTP,
et : quand `invite-school-account` répond `ok:true`, le courriel est-il PARTI ?)
· **P0-19** (`lien-acces` — le bouton WhatsApp est écrit, testé, publié, et
n'appelle rien d'autre) · puis P0-1, P0-12, P0-13, P0-14, P0-15, P0-16, P0-17.

## Preuve, pas affirmation

Les **9 audits passent**. La connexion est éprouvée dans les deux sens : avant,
cinq pannes → un seul message et déconnexion à chaque fois ; après, cinq
messages distincts, le 500 réessayé trois fois, le 401 et le 403 non réessayés,
et un hoquet réseau laisse entrer quand même. `audit-schema` : **aucun écart sur
49 tables** contre tes 29 migrations.

**Ce que je n'ai pas pu vérifier :** je ne lis pas la base d'ici. Les six
situations sont jouées contre un serveur simulé, pas contre ton projet Supabase.

---

# P0-20 · Un parent sans adresse e-mail — décision de Loms du 5 août 2026

> *« Si un parent n'a pas de mail, on utilise WhatsApp. »*

C'est une décision, pas une proposition. Elle vient de Loms, elle s'applique.
Ce document dit **ce que le navigateur ne peut plus faire aujourd'hui**, et
**ce qu'il lui faut de toi**. Le mécanisme dans la base est ton choix : je ne
le conçois pas, je le servirai tel que tu l'auras arrêté.

## 1. Ce qui l'empêche aujourd'hui — vérifié dans tes migrations

Trois verrous, tous dans `20260804233228_require_email_for_school_accounts.sql`
et `20260804233449_require_email_in_preinscription_rpc.sql` :

```sql
alter table public.users alter column email set not null;
alter table public.users add constraint users_email_key unique (email);
alter table public.users add constraint users_email_normalized_check
  check (email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$');

alter table public.preinscriptions add constraint preinscriptions_email_required_check
  check (email is not null and email ~ '…');
```

Et dans `save_school_user_profile` :

```sql
if v_email is null … then
  return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'email');
end if;
```

**Conséquence exacte, mesurable :** un parent sans adresse ne peut pas exister.
La Direction remplit la fiche, appuie sur Enregistrer, et le serveur refuse.
La famille n'a aucun compte — donc aucun lien à recevoir, ni par courriel ni
par WhatsApp.

## 2. Le point qui décide de tout, et que je ne veux pas laisser dans l'ombre

**WhatsApp est un moyen de LIVRAISON, pas une IDENTITÉ.**

Le lien que P0-19 fabrique passe par `supabase.auth.admin.generateLink()`. Cette
fonction fabrique un lien **pour une identité qui existe dans `auth.users`**.
Livrer ce lien par WhatsApp au lieu du courriel ne change rien à ce fait : il
faut d'abord que la personne ait une identité.

Donc la vraie question n'est pas « comment livrer », elle est :

> **Qu'est-ce qui identifie un parent qui n'a pas d'adresse e-mail ?**

Cette question est la tienne. Je ne connais pas assez ce que Supabase Auth
accepte comme identité pour trancher, et **je ne veux pas le deviner** — le
5 août, une déduction présentée comme un fait a envoyé Loms chercher au mauvais
endroit, et j'ai promis de ne plus recommencer.

## 3. Ce dont le navigateur a besoin — la liste précise

Quelle que soit ta réponse à la question ci-dessus, il me faut ces six choses.
Chacune est écrite avec **ce que l'écran en fait** — si un point te paraît
inutile, dis-le et je retire l'écran correspondant.

**a. Créer un compte parent avec un téléphone et sans adresse.**
`save_school_user_profile` doit l'accepter. Il me faut le **code de refus** quand
la fiche n'a **ni** adresse **ni** téléphone — un parent injoignable ne sert à
personne. Je propose `CONTACT_REQUIRED` ; garde le nom que tu veux, mais donne-le
moi, sinon l'écran affichera « le serveur a refusé » sans dire quoi corriger.

**b. Savoir, à la lecture, comment ce parent est joint.**
La liste des parents doit afficher « accès par WhatsApp » au lieu de proposer
« renvoyer l'invitation par courriel » — un bouton qui ne peut pas aboutir est
un mensonge poli, et j'en ai déjà livré un cette semaine.
Si `email` devient nullable, `email is null` me suffit et je n'ai besoin de
rien. **Mais si tu choisis une adresse technique fabriquée** (point 5b), alors
`email` ne sera jamais nul et je ne saurai plus distinguer : il me faudra un
champ explicite. **Je ne l'inventerai pas** — dis-moi son nom et ses valeurs.

**c. `lien-acces` (P0-19) doit aboutir pour un tel compte.**
Le contrat que je t'ai proposé prévoit un refus `NO_EMAIL`. Il a été écrit quand
l'adresse était obligatoire. Pour un parent WhatsApp, ce refus ne doit **plus**
tomber : la fonction doit rendre un lien. Sinon le bouton, déjà écrit et publié,
répondra « ce parent n'a pas d'adresse » à celui-là même pour qui il a été fait.

**d. Le téléphone devient un identifiant — il lui faut une forme unique.**
Aujourd'hui **le navigateur enregistre le numéro tel qu'il est tapé**. Vérifié :
le seul contrôle est `/^[+]?[0-9\s\-()+]{9,15}$/`, il n'y a **aucune
normalisation et aucun contrôle d'unicité**. Donc `+243 810 000 111`,
`0810000111` et `243-810-000-111` sont trois valeurs différentes pour le même
parent.
Si le numéro sert à identifier ou à fabriquer une adresse, **c'est le serveur qui
doit poser la forme canonique** — pas le navigateur, pour la même raison que le
solde ne se calcule pas dans le navigateur. Dis-moi la forme que tu retiens
(E.164 `+243810000111` ?) et le code de refus si le numéro est déjà pris
(`PHONE_IN_USE` ?), et je ferai la saisie qui la respecte.

**e. Le jour où ce parent obtient enfin une adresse.**
C'est le cas courant : l'école aide la famille à créer une boîte quelques mois
plus tard. Aujourd'hui `save_school_user_profile` répond
`AUTH_EMAIL_CHANGE_REQUIRED` dès qu'on change l'adresse d'un compte déjà rattaché
à Auth. Il me faut le chemin : est-ce une RPC dédiée, une Edge Function, ou rien
du tout ? Tant que je ne sais pas, l'écran doit refuser la modification — et le
dire clairement plutôt que d'échouer en silence.

**f. La préinscription depuis le site.**
`preinscriptions_email_required_check` interdit une demande sans adresse. Une
famille qui n'a pas de boîte ne peut donc pas préinscrire son enfant en ligne.
La décision de Loms vaut là aussi. **Si tu lèves cette contrainte**, dis-moi ce
que le formulaire public doit exiger à la place, et je le change.

## 4. Ce que je NE fais pas avant ta réponse

- Je ne touche à aucune contrainte, colonne, fonction ou migration.
- Je n'invente aucun champ, et je ne déduis « ce parent est WhatsApp » d'aucun
  indice côté navigateur.
- Je n'appelle rien que tu n'aies pas ouvert. La leçon du 5 août est encore
  chaude : j'appelais `prepare_account_invitation` en direct alors qu'elle
  m'était fermée, et chaque invitation était refusée en silence pendant des
  jours.

## 5. Deux mécanismes que le navigateur sait servir — **ton choix, pas le mien**

Je ne les propose que pour que tu voies ce qui est déjà écrit côté écran. Prends
l'un, l'autre, ou un troisième auquel je n'ai pas pensé.

**a. `users.email` redevient nullable, le téléphone porte l'identité.**
Le plus propre à lire : `email is null` dit tout, sans champ supplémentaire.
Ce que je ne sais pas et qui t'appartient : ce que Supabase Auth accepte comme
identité téléphonique, et si `generateLink()` sait travailler dessus **sans
qu'aucun SMS ne parte** — l'école ne paiera pas un fournisseur SMS, le lien part
par WhatsApp.

**b. Une adresse technique fabriquée depuis le numéro**, du genre
`243810000111@…`, invisible pour la famille, qui ne sert qu'à Auth.
Avantage : **rien de ce que tu as déjà construit ne bouge** —
`invite-school-account`, `generateLink`, `lien-acces` continuent tels quels.
Contrainte pour moi : `email` n'étant jamais nul, il me faut le champ du
point **3b**, sinon l'écran proposera d'envoyer un courriel à une boîte qui
n'existe pas.

**Le point 3d vaut dans les deux cas** : dès que le numéro identifie, il lui faut
une forme unique posée par le serveur.

## 6. Ce que je livre dès que tu réponds

L'écran de création d'un parent avec deux voies affichées côté Direction —
**adresse e-mail** ou **téléphone WhatsApp** — la liste qui dit par où chaque
parent est joint, et le bouton de lien qui s'adapte. Tout est déjà écrit à part
la partie qui dépend de ta réponse. **Je n'appellerai rien avant.**

---

# P0-21 · Le téléphone n'est plus réservé aux parents — décision de Loms du 6 août 2026

> *« Maintenant, pour les professeurs et Direction 2 et tous les postes, ça reste
> sur téléphone, sauf Direction 1 sur adresse mail. Tu dois les faire sans bug. »*

**Ton lot P0-20 est intégré et il fonctionne** — je n'y touche pas, je l'étends.
Loms élargit sa décision d'hier : le téléphone devient la voie normale de
**tous** les profils, et l'adresse e-mail reste celle de **Direction 1 seule**.

| profil | identité de connexion |
|---|---|
| **Direction 1** (`direction`) | **adresse e-mail — obligatoire, inchangée** |
| Direction 2 (`direction2`) | téléphone |
| Caisse (`direction3`) | téléphone |
| Enseignant (`enseignant`) | téléphone |
| Gardien (`gardien`) | téléphone |
| Parent (`parent`) | téléphone — déjà livré |

**Direction 1 garde l'adresse e-mail parce que c'est la seule voie de secours
qui ne dépend de personne.** Si tous les comptes passaient par un code livré à
la main, plus personne ne pourrait rouvrir l'école le jour où la Direction perd
son téléphone.

## Les six endroits qui disent `parent` en dur

J'ai lu tes migrations. La règle de Loms bute sur six contrôles, et je les liste
parce que **en oublier un ne produirait pas une erreur : il produirait un trou**.

| | où | ce qui bloque aujourd'hui |
|---|---|---|
| 1 | `users_contact_required_check` | seul `role = 'parent'` peut porter `access_channel = 'phone_whatsapp'` |
| 2 | `save_school_user_profile` *(profile_compat)* | n'aiguille vers le contrat téléphone que si `role = 'parent'` |
| 3 | `save_parent_phone_profile` | refuse `TARGET_ROLE_MISMATCH` si la cible n'est pas parent — **et son `update` force `role='parent'`**, ce qui transformerait un enseignant en parent |
| 4 | `prepare_parent_phone_access` | refuse `TARGET_NOT_PARENT` |
| 5 | `confirm_parent_phone_password_change` | refuse `NOT_PHONE_PARENT` |
| 6 | `private.handle_new_auth_user` | *« Profil Parent SchoolSafe non autorisé »* |

## Et un SEPTIÈME, qui n'est pas un refus mais un trou de sécurité

`private.current_app_role()` et `private.current_app_user_id()` portent :

```sql
and not (u.role = 'parent' and u.access_channel = 'phone_whatsapp'
         and u.must_change_password)
```

C'est **la** protection qui fait qu'un parent encore sur son code temporaire ne
voit rien. Elle ne vaut que pour `role = 'parent'`.

**Donc, tel quel, un enseignant à qui la Direction vient de remettre un code
temporaire aurait accès à TOUT dès la première connexion, sans avoir choisi son
mot de passe** — cotes, classes, présences. Un code lu par-dessus l'épaule dans
une cour d'école suffirait.

Les cinq premiers points font échouer une création, ce qui se voit. **Celui-ci
ne fait échouer rien du tout** — c'est le seul qui m'inquiète vraiment.

## Qui a le droit de créer et de réinitialiser

Règle déjà arrêtée par Loms le 5 août, que je rappelle telle quelle :

> *« Direction 2 peut créer tout compte sauf direction et caisse. »*

Donc, pour `prepare_parent_phone_access` et le contrat de profil :

| acteur | peut créer / réinitialiser |
|---|---|
| Direction 1 | tous les profils |
| Direction 2 | `enseignant`, `gardien`, `parent` — **jamais** `direction` ni `direction3` |
| tout le reste | rien |

Aujourd'hui `prepare_parent_phone_access` accepte `direction` et `direction2`
sans distinguer la cible. Sous la nouvelle règle, Direction 2 pourrait
réinitialiser l'accès de la Caisse — donc entrer dans la caisse.

## Ce que je te demande, exactement

1. Ouvrir le canal `phone_whatsapp` à `direction2`, `direction3`, `enseignant`,
   `gardien` et `parent`. **Jamais à `direction`.**
2. Maintenir `email` obligatoire pour `direction`, et pour lui seul.
3. Corriger le `update` du point 3 : ne plus écrire `role='parent'` en dur.
4. **Étendre la protection du point 7 à tous les rôles** — c'est la plus
   importante des sept.
5. Poser la matrice acteur → cible ci-dessus.
6. Me dire les noms définitifs. Si `save_parent_phone_profile` et
   `prepare_parent_phone_access` gardent leur nom malgré qu'ils ne servent plus
   qu'aux parents, **dis-le simplement** : je les appellerai tels quels. Un
   renommage ne vaut pas une migration de plus.
7. Me dire ce que devient `NOT_PHONE_PARENT` / `TARGET_NOT_PARENT` : gardés avec
   un autre sens, ou remplacés ? J'affiche le code que tu me donnes, je n'en
   invente pas.

## Ce que je fais pendant ce temps, et qui ne dépend pas de toi

- **La normalisation E.164 dans le navigateur.** Signalée en P0-20 point (d) :
  la saisie accepte `+243 810 000 111` avec des espaces, et
  `users_phone_e164_check` exige `+243810000111`. Je reprends **exactement** ta
  fonction `private.normalize_phone_e164`, mêmes règles RDC, pour que l'écran
  montre ce qui sera enregistré au lieu de se faire refuser après coup.
- Le choix **E-mail | Téléphone** sur l'écran de connexion.
- L'écran « créez votre code personnel », `get_my_access_state`,
  `confirm_parent_phone_password_change`.
- Le bouton WhatsApp raccordé à `parent-phone-access`.

**Rien de tout cela n'appellera un contrat pour un rôle que tu n'as pas encore
ouvert.** Tant que le point 1 n'est pas fait, l'écran de création d'un
enseignant par téléphone dira que le serveur ne l'accepte pas encore — il ne
tentera pas et n'échouera pas en silence.

## Une note sur `users.phone`, qui vaut pour tous les rôles

`save_parent_phone_profile` normalise le numéro. `save_school_user_profile_email`
ne le normalise pas — il fait un simple `btrim`. Or `users_phone_e164_check`
s'applique à **toutes** les lignes.

Donc enregistrer aujourd'hui un enseignant avec `+243 810 000 111` échoue sur la
contrainte, avec un `VALIDATION_ERROR` nu qui ne dit pas quel champ. Je corrige
la saisie de mon côté ; **mais la forme canonique doit rester la tienne** — deux
normalisations qui divergent, c'est la panne du 5 août sous un autre nom.

---

# P0-24 · Une seule coordonnée suffit — décision de Loms du 6 août 2026

> *« Les mail et numéro, ce n'est pas obligé de mettre les deux pour ouvrir ton
> compte. C'est soit numéro, soit mail. »*

C'est une décision, et elle **modifie ton contrat P0-22 sur un point précis** :
les deux coordonnées ne sont plus **obligatoires** ensemble. Elles restent
**possibles** ensemble — et quand les deux sont là, les deux ouvrent le même
compte, ce qui est tout l'acquis de P0-22 et ne change pas.

**Ce qui change tient en une ligne :** au lieu d'exiger `email` **ET** `phone`,
il faut exiger `email` **OU** `phone`, avec au moins l'un des deux.

## Pourquoi Loms tranche ainsi — le cas concret

Un parent de Kinshasa n'a pas toujours d'adresse e-mail. Exiger les deux, c'est
lui demander de créer une boîte qu'il ne relèvera jamais, uniquement pour
remplir une case. Et symétriquement : le compte de Loms lui-même n'a pas encore
de numéro, et il fonctionne.

## Ce qui bloque aujourd'hui — relevé dans tes migrations

Cinq contrôles, tous introduits par P0-22 :

| | où | ligne | ce qu'il exige |
|---|---|---|---|
| 1 | `save_school_user_profile_dual_impl` | 105 | `if v_email is null … VALIDATION_ERROR field=email` |
| 2 | `save_school_user_profile_dual_impl` | 108 | `if v_phone is null … VALIDATION_ERROR field=phone` |
| 3 | `prepare_account_invitation` | 82 | `if not contact_setup_complete … CONTACT_SETUP_INCOMPLETE` |
| 4 | `prepare_parent_phone_access` | 309 | `if not contact_setup_complete … CONTACT_SETUP_INCOMPLETE` |
| 5 | `handle_new_auth_user` | 186, 241 | `raise 23514` si `not contact_setup_complete` |

Les points 1 et 2 empêchent d'**enregistrer** la fiche. Les points 3, 4 et 5
empêchent d'**ouvrir un accès** — donc même une fiche déjà enregistrée avec une
seule coordonnée resterait sans accès possible, par aucune des deux voies.

**`users_primary_contact_available_check`, lui, n'a PAS besoin de changer** :
il exige déjà seulement que le canal principal ait sa coordonnée. Il dit
exactement la bonne chose.

## Ce que je te demande — précisément

1. **Au moins une coordonnée**, jamais zéro. Le refus quand les deux manquent
   doit avoir son propre code — je propose `CONTACT_REQUIRED`, garde le nom que
   tu veux mais donne-le-moi : `VALIDATION_ERROR` sans champ ne dit pas quoi
   corriger.
2. **`prepare_account_invitation` n'exige que l'adresse.** Un compte sans
   numéro doit pouvoir recevoir son invitation par courriel.
3. **`prepare_parent_phone_access` n'exige que le numéro.** Un compte sans
   adresse doit pouvoir recevoir son code par WhatsApp.
4. **`handle_new_auth_user`** : même chose sur les deux branches — la branche
   téléphone contrôle le numéro, la branche courriel contrôle l'adresse.
5. **L'unicité reste entière** sur les deux champs quand ils sont renseignés.
   Deux comptes ne partagent ni une adresse ni un numéro.

## Ce que je fais de mon côté, et ce que je ne fais pas

**Je fais :** le formulaire n'exige plus qu'**une** des deux coordonnées, et
l'écran dit clairement laquelle manque et ce qu'elle empêche — « sans numéro,
pas de code WhatsApp », « sans adresse, pas d'invitation par courriel ».

**Je ne fais pas :** je ne touche à aucune contrainte ni à aucune fonction. Et
tant que tu n'as pas ouvert les points 1 à 5, **l'écran dira exactement pourquoi
le serveur refuse** au lieu d'afficher un `VALIDATION_ERROR` nu. Je préfère un
message honnête à un formulaire qui se fait refuser sans expliquer.

## Un état à vérifier de ton côté, que je ne peux pas voir

`contact_setup_complete` est une colonne **générée** : `(email is not null) and
(phone is not null)`. Si tu la gardes, elle devient un simple indicateur de
fiche complète — ce qui est utile — mais elle ne doit plus **conditionner**
l'ouverture d'un accès. Dis-moi ce que tu en fais : je l'affiche aujourd'hui
comme un état, pas comme un refus.
