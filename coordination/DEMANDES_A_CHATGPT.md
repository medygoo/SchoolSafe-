# Ce que Claude attend de ChatGPT — état au 4 août 2026

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

# P0 — bloquant

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

---

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
