# SchoolSafe — mémoire de travail

Ce fichier n'est pas une documentation du code : c'est ce qu'une année de
corrections a appris, écrit pour ne pas être réappris. Chaque leçon porte la
panne qui l'a produite — sans elle, une règle n'est qu'une opinion.

Il vient d'une autre installation de SchoolSafe, pour **la même école**.

---

## Le cadre de travail — à lire avant tout

**Dépôt :** `medygoo/SchoolSafe-` · branche de production `main`
**Propriétaire et décideur :** Loms

| | Responsable |
|---|---|
| Architecture, Supabase, schéma, migrations, RLS, R2, contrats de données, revue technique | **ChatGPT** |
| Audit du code, interface, intégration frontend, tests, correction des bugs | **Claude** |
| Besoins, règles métier, autorisation de mise en production | **Loms** |

GitHub est le seul canal entre les deux agents : issues, branches, Pull
Requests, `docs/`. Rien ne passe d'une plateforme à l'autre automatiquement.

### Ordre de Loms — 10 août 2026 : on collabore, on ne se contredit pas

> *« Je ne vous ai pas mis ici, toi et ChatGPT, pour que vous vous
> contredisiez. Vous êtes là pour trouver des solutions, en associant vos
> idées, pour que l'application soit stable, puissante et fonctionnelle.
> Chacun a son point fort — je répartis le travail, mais ça n'empêche pas
> que vous vous donniez des idées. Vous n'êtes pas là pour freiner mon
> projet. Vous allez collaborer pour finir mon projet. »*

Ce qui a provoqué l'ordre : je rendais des **blocages**. J'ouvrais deux
documents de ChatGPT, je montrais qu'ils se contredisaient, et je m'arrêtais
là en attendant qu'il tranche. Techniquement juste, et **inutile à Loms** :
son projet n'avançait pas d'un jour.

La règle qui remplace :

> **On ne rend pas un blocage — on rend SA MOITIÉ DU TRAVAIL déjà faite,
> et la plus petite chose qui reste à l'autre.**

Éprouvé le jour même sur le Web Push. Version « blocage » : *« aucun appareil
ne peut être enregistré, il faut que tu changes ça »*. Version collaboration :
le service worker savait déjà recevoir, j'ai écrit l'abonnement, il appelle la
vraie fonction, et il ne reste à ChatGPT que **deux lignes** — accepter une
valeur de plus dans `p_provider`, et rendre la clé publique dans
`get_safe_settings`. Le jour où il les écrit, tout fonctionne sans toucher au
navigateur.

Et le corollaire, qui n'est pas une permission de mentir : **appeler le vrai
contrat et rapporter la vraie réponse** reste la règle. Un refus du serveur
s'affiche dans les mots de l'école, avec son code pour le dépannage. Ce qui
change, c'est qu'on ne s'arrête plus au refus : on a déjà posé tout ce qui
peut l'être autour.

### Consigne OBLIGATOIRE de Loms — le canal avant tout

1. **Brancher la communication est la PREMIÈRE chose à faire**, avant de coder,
   avant d'analyser, avant de livrer. On lit ce que l'autre a déposé sur GitHub,
   on y dépose ce qu'on a fait, on y pose ses questions. Toujours.
2. **Ce que ChatGPT a fait a été demandé par Loms.** On ne le conteste pas, on ne
   l'audite pas pour le remettre en cause, on ne demande pas pourquoi. **On
   continue à partir de là.** On ne signale qu'une chose : ce qui empêche
   concrètement d'avancer — un champ manquant, un identifiant qui ne correspond
   pas. Jamais un désaccord d'opinion.
3. **TOUT est déposé sur le canal, pas seulement ce qui relève de l'autre.**
   *Ordre de Loms, 11 août 2026 : « tu informes la totalité à ChatGPT, c'est
   un ordre que tu feras pour toujours. »*

   Ce qui l'a provoqué : j'avais rendu à Loms un état complet du module
   Scanner — trois défauts, deux angles morts — **et rien n'était sur
   GitHub.** Un seul des points concernait ChatGPT ; j'avais donc trié, et
   gardé le reste dans la conversation. C'est exactement ce qu'il ne faut pas
   faire : **l'autre agent doit avoir la MÊME vue que Loms**, sinon il
   travaille sur une moitié d'image et Loms devient le seul lien entre nous.

   Donc : un audit, un état, une trouvaille, un doute — ça part sur le canal
   **en entier**, en disant clairement ce qui est à lui, ce qui est à moi, et
   ce que je n'ai pas vérifié. Trier appartient au lecteur, pas à l'émetteur.

4. **Réponses courtes et claires à Loms.** Ce qui est fait, ce qui bloque, ce
   qu'on attend. Le détail va dans `docs/`, pas dans la réponse.

### Ordre de Loms — 5 août 2026, après une déduction présentée comme un fait

> *« Je te donne l'ordre de ne plus déduire. De ne dire que des choses dont tu
> es sûr. À chaque réponse, tu réponds aux questions et aux problèmes que tu
> n'arrives pas à traiter ou que tu ne comprends pas. Pas de long discours,
> pas d'explication sauf si je demande. Toi, tu ne conçois pas la base de
> données : quand ChatGPT fait une chose, tu obéis, parce que c'est moi qui
> lui ai demandé. S'il y a un problème, tu le signales — mais tu obéis. »*

Quatre règles, et elles priment :

1. **Ne rien affirmer sans l'avoir vérifié.** J'ai dit à Loms qu'aucun compte
   n'existait dans la base. Je ne l'avais pas regardée — je l'avais déduit
   d'une note de ChatGPT. `lomsmedy@gmail.com` existait. **Une déduction
   présentée comme un fait envoie Loms chercher au mauvais endroit.** Si on ne
   peut pas vérifier, on le DIT : *« je ne peux pas lire la base d'ici »*.
2. **Répondre à la question posée.** Loms avait demandé *pourquoi* la connexion
   échoue. J'ai livré un compte rendu de tout mon travail. Ce n'était pas la
   question.
3. **Nommer ce qu'on n'arrive pas à traiter.** À chaque réponse, et sans le
   noyer dans le reste.
4. **La base de données ne se conçoit pas ici.** Ce que ChatGPT fait a été
   demandé par Loms. On l'intègre, on s'y conforme, on signale ce qui bloque
   — on ne le remet pas en cause et on ne le contourne pas.

**La preuve du 5 août :** `prepare_account_invitation` est fermée au navigateur
(`revoke ... from authenticated`). Au lieu d'obéir à cette fermeture et de
passer par l'Edge Function que ChatGPT avait indiquée, je l'appelais quand même
en direct. Chaque invitation était refusée en silence. **Obéir au contrat aurait
évité la panne ; le contourner l'a créée.**

### La méthode de travail — fixée par Loms, 5 août 2026

On avance **fonctionnalité par fonctionnalité**, jamais en vrac. Pour chacune,
le même cycle, dans cet ordre :

1. **Je propose** une fonctionnalité et je dis pourquoi celle-là.
2. **Je décris ce qui EXISTE**, dans **tous les profils** — qui voit quoi, qui
   peut quoi, comment l'écran se présente et comment il réagit. Pas ce qu'on
   pourrait faire : ce qui est là.
3. **Je liste les problèmes que j'ai vérifiés**, et séparément **ce que je n'ai
   pas pu vérifier**. Les deux, toujours.
4. **Je pose les questions dont la réponse change le travail.** Courtes.
5. **Loms décide.**
6. **Je code la partie navigateur.**
7. **Ce qui touche la base part dans `coordination/DEMANDES_A_CHATGPT.md`.**
   Je n'y touche pas moi-même. *« Tu laisses les instructions à ChatGPT, il le
   fera. »*
8. Je fusionne, je publie, **et je vérifie que la publication a réussi.**

**Le point qui décide de tout, en étape 7 :** un contrôle serveur qui refuse
n'est pas un obstacle à contourner. Le 5 août, `prepare_account_invitation`
était fermée au navigateur ; je l'ai appelée quand même, et chaque invitation
a été refusée en silence pendant des jours. **Obéir au contrat aurait évité la
panne.**

### Les règles qui ne se discutent pas

1. Ne pas recommencer le projet à zéro ; conserver l'existant.
2. **Jamais de poussée directe sur `main`.** Branche dédiée + Pull Request en
   brouillon, fusionnée après validation.
3. **Ne jamais modifier seul** une table, colonne, vue, fonction, trigger,
   index, migration ou politique RLS. On le **signale** à ChatGPT.
4. Ne jamais désactiver RLS pour contourner une erreur.
5. Aucun secret dans le dépôt : `service_role`, mot de passe PostgreSQL,
   secret R2, token.
6. Aucune donnée réelle d'élève, parent ou paiement dans les tests, captures,
   journaux ou issues.
7. **Signaler AVANT de coder** tout impact sur Supabase, Auth, R2, le cache
   PWA, le service worker ou les permissions.
8. Le solde ne se calcule jamais uniquement dans le navigateur.
9. Documenter tests, risques, fichiers modifiés et procédure de retour arrière.
10. **Fusionner n'est pas publier.** Après chaque fusion dans `main` — la
    sienne ou celle de l'autre agent — on vérifie que la publication a réussi,
    et on le dit. Voir la leçon ci-dessous : elle a coûté une journée entière
    de corrections qui n'atteignaient personne.

### La publication est une étape, pas une conséquence

**4 août 2026.** Pendant des heures, chaque fusion dans `main` a été suivie d'un
échec de publication : le contrôle exigeait *exactement* 144 fichiers dans
`dist`, il y en avait 164 — des images, rien d'autre. L'écran de connexion
corrigé, les préinscriptions, le schéma de la base, les codes d'erreur : **tout
était dans `main` et rien n'atteignait l'école.** Loms a demandé pourquoi ses
corrections n'étaient pas en ligne. Elles l'étaient dans le dépôt, jamais chez
lui.

Trois choses à en retenir, et elles se répètent ailleurs :

1. **Une croix rouge que personne n'ouvre est un échec silencieux** — celui-là
   même que tous nos audits traquent. La chaîne de publication le commettait.
   Elle ouvre désormais une **issue** quand elle échoue, et la referme seule
   quand tout revient : l'échec vient à nous au lieu d'attendre.
2. **Un contrôle qui compte les fichiers un par un finira toujours par mentir.**
   Il exprimait un nombre au lieu d'exprimer son intention — *l'artefact n'est
   pas vide, et rien de privé n'en sort*. Un seuil et deux interdits disent la
   même chose sans se périmer.
3. **La responsabilité était écrite depuis le 3 août** — « Claude contrôle le
   déploiement GitHub Pages » — et elle n'a pas été exercée. Une règle qu'on
   lit et qu'on n'exécute pas ne protège de rien.

**Conséquence directe pour ce fichier :** les leçons de base de données qu'il
contient ne sont pas là pour qu'on y touche. Elles sont là pour **reconnaître
un symptôme et le décrire correctement à ChatGPT** — c'est la moitié du travail
de débogage, et c'est la moitié qu'on rate le plus souvent.

---

## Une application, une école — aucun tiers

**SchoolSafe est livré à une école : le Complexe Scolaire Le Sage.** Rien dans
l'application ni sur le site ne mentionne l'éditeur : ni son nom, ni son numéro,
ni un écran d'activation, ni une clé de licence, ni un lien « contactez votre
opérateur ». Ces éléments existaient et ont été retirés le 3 août 2026 — ils
appartenaient à un modèle multi-écoles qui n'est pas celui-ci.

Ce que l'utilisateur voit porte **deux noms seulement** : le logiciel et l'école.

---

## Deux noms à ne pas confondre

| | Nom | Où il paraît |
|---|---|---|
| Le **logiciel** | SchoolSafe | titre, écran de démarrage, icône du téléphone, manifest |
| L'**école** | Complexe Scolaire Le Sage | bulletins, reçus, convocations, en-têtes de documents |

C'est la distinction la plus souvent perdue, et elle se paie cher.

**Elle s'est payée le 4 août 2026 : VINGT documents écrivaient le nom du
logiciel.** Le bulletin portait `🛡️ SchoolSafe` en filet d'en-tête ; les listes
ENAFEP et EXETAT, « Document officiel généré par SchoolSafe v3.0 » ; l'archive
de clôture, « 🛡️ SchoolSafe — Document de clôture officiel ». Une administration
congolaise qui reçoit cela lit que **c'est le logiciel qui délivre**.

Trouvé en suivant une consigne de Loms sur un seul document — *« la charte même
au devoir »* — dont l'en-tête portait « SchoolSafe — Plateforme scolaire
numérique ». **Un exemple précis a désigné un défaut sur vingt.**

`audit-logo.mjs` tient désormais les trois côtés de la distinction, et refuse
dans les deux sens :

| | |
|---|---|
| l'emblème de l'école **est** sur les 38 documents | obligatoire |
| l'emblème de l'école **n'est pas** dans l'interface | jamais |
| le nom du logiciel **n'est pas** dans les documents | jamais |

Restent admis : `sc.name \|\| 'SchoolSafe'` — un repli, pas une signature — et
les noms de fichier, qui ne s'impriment pas.

**L'emblème de l'école n'entre PAS dans l'interface.** Erreur commise puis
corrigée : donner une valeur par défaut au logo de l'école l'a fait paraître
dans la barre latérale, l'écran de connexion et « À propos » dès le premier
lancement — l'application se mettait à porter l'école. Le logo de l'école est
le repli **des documents**. L'interface porte celui du logiciel, et n'affiche
l'emblème de l'école que si la Direction l'a elle-même téléversé.

**Cette règle a DEUX côtés, et on n'en retient qu'un.** Le 4 août 2026, en
corrigeant les dix documents qui n'avaient pas d'emblème, je leur ai appliqué
la règle de l'interface : aucun repli, donc **rien ne paraissait** tant que la
Direction n'avait pas téléversé. C'était l'erreur symétrique de celle notée
ci-dessus. Loms a tranché en une phrase : *« obligatoire, le logo sur tous les
documents »*.

Depuis, deux constantes, et la frontière est tout :

```
window.SCHOOL_LOGO      ce que la Direction a TÉLÉVERSÉ — null sinon.
                        Seule constante que l'INTERFACE peut lire.
window.SCHOOL_LOGO_DOC  l'emblème intégré. UNIQUEMENT les DOCUMENTS.
```

`audit-logo.mjs` refuse une lecture du second hors d'un document — éprouvé en
la lui glissant dans `buildUI`. **C'est l'outil qui tient la frontière, pas la
discipline** : la discipline avait déjà lâché une fois.

Symétriquement : **les documents imprimés représentent l'école**, donc ils en
portent les couleurs — jamais celles de l'interface.

**Confirmé par Loms le 4 août 2026 :** la charte couvre le site **et tout
document que l'application produit** — reçu, bulletin, certificat, convocation,
fiche de paie, carte d'élève. L'interface, elle, garde le bleu du logiciel.

Le passage a été fait ce jour-là : **520 couleurs sur 43 documents**, dont
**167 emplois du seul bleu du logiciel `#243a6b`**. Ce n'étaient pas 520
décisions mais trente et une, chacune répétée. Trois leçons en sont sorties :

1. **Le pied de page partagé avait bien échappé à tout**, comme annoncé plus
   haut — `_officialFooter` ne produit pas de PDF, donc aucun outil qui
   parcourt « les fonctions qui produisent un document » ne le voyait. Un
   assistant partagé se reprend **par son nom**, pas par balayage.
2. **Un écart de charte cachait un défaut de lisibilité** : `#a89c8b` portait
   ce pied de page en corps de 10 px, à **3,03:1**. Mesurer pour la charte a
   trouvé ce que personne ne cherchait.
3. **Le commentaire de `audit-charte.mjs` décrivait le vert de gris** — le
   troisième essai, abandonné — alors que son code appliquait le gris bleuté
   retenu. Un outil dont le commentaire contredit le code est un piège : le
   prochain lecteur corrigera le code pour lui obéir, et rejettera la charte.

Les cartes d'élève sortent d'un **studio à dix familles** que la Direction
choisit. Aucune n'a été retirée : une onzième, `L · Le Sage`, a été ajoutée
et **elle est le défaut**. Ce qui sort sans qu'on touche à rien porte l'école.

---

## L'école

**Complexe Scolaire Le Sage / The Wise School International**
Kabambare 4367, Quartier Bon Marché, Commune de Barumbu — Kinshasa, RDC

Trois variantes de l'adresse avaient coexisté, dont aucune n'était la bonne.
Celle-ci l'est.

L'année scolaire congolaise court de **septembre à août**.

### DEUX cycles, pas trois — maternelle et primaire

**Dit par Loms le 4 août 2026.** L'école s'arrête à la **sixième primaire** et
prépare l'**ENAFEP**. Il n'y a **ni secondaire, ni humanités, ni EXETAT**.

Le site les annonçait tous les trois, et le formulaire de préinscription
proposait six classes du secondaire : une famille pouvait demander une place
en 3ᵉ humanités dans une école qui n'a pas de secondaire. Retiré du site le
même jour.

**L'application, elle, les porte encore** — le cycle `secondaire`, l'option
`humanites`, l'écran EXETAT, le rapport SECOPE. Ce n'est pas une erreur à
effacer d'un trait : le cycle sert aussi aux horaires du portail et aux
gabarits de cartes. À reprendre écran par écran, en demandant à Loms ce qu'on
garde — une école peut ouvrir un secondaire l'an prochain.

### La palette : gris · blanc · or

**Le gris de l'école est un GRIS BLEUTÉ** — teinte 207°, saturation 14 % :
`#6b7d8b`. Donné par la Direction en montrant un mur peint. Ce n'est pas un
gris neutre, et un contrôle qui exigeait R = G = B rejetait la charte elle-même.

```
--ground-deep #657786   le mur — fond principal
--ground      #556777   boutons et pastilles
--ground-soft #8896a2   éclairci
--white #ffffff  --surface #f0f1f2  --surface-2 #dadee2
--gold  #c09018  --gold-light #e2b84f  --gold-deep #7a5a0d  --gold-pale #fae6b8
--ink   #1a2228  --muted #5e6c78  --line rgba(60,73,83,.13)
```

L'or vaut `#c09018`, relevé sur l'étoile de l'emblème. Il ne porte pas de texte
sur blanc (2,9:1) : `--gold-light` pour écrire sur fond sombre, `--gold-deep`
sur blanc. Sur le fond gris clair, aucun or ne se lit — d'où `--gold-pale`
(3,8:1) pour les GRANDS caractères seulement.

**Quatre essais avant la bonne couleur** : émeraude, gris neutre, vert de gris
(un pot de peinture montré), enfin le gris bleuté (un mur peint montré).
**Une couleur se montre, elle ne se devine pas.** Demander une image dès le
premier doute aurait épargné trois passes complètes.

**Vérifié une seconde fois le 4 août 2026**, sur une photographie du mur
envoyée par Loms, en échantillonnant les pixels au lieu de les regarder :

| zone | valeur | teinte · saturation · luminosité |
|---|---|---|
| le mur, au point le mieux éclairé | `#6e7984` | **210° · 9 % · 47 %** |
| le mur, en pénombre | `#5c6670` | 210° · 10 % · 40 % |
| la bande ocre du bas | `#9e855f` | 37° · 27 % · 46 % |

C'est le même gris que celui noté ici — 207°, 14 %, 46 %. **La charte tient.**
L'écart de saturation est celui d'un mur éclairé au tungstène, pas celui d'une
autre couleur. L'ocre photographié est terne parce qu'il est dans l'ombre : la
référence de l'or reste **l'étoile de l'emblème**, pas une boiserie.

Deux conséquences mesurées, valables partout où le gris sert de fond :

> **`--ground-deep` ne porte que du BLANC** (4,63:1). `--surface` y tombe à
> 4,09 et `--gold-light` à 2,47 — même en grands caractères.
> Sur ce fond, **l'or ne s'écrit pas : il se remplit.** Un aplat d'or à texte
> d'encre donne 5,56:1.
>
> Le petit texte en gris va sur **`--ground`** (`#556777`) : blanc 5,85:1,
> `--surface` 5,17:1, `--gold-pale` 4,75:1.

`tools/audit-contraste-site.mjs` mesure les 17 couples du site et sait dire
non : `--preuve` lui fait refuser l'or sur blanc (2,90:1).

### L'emblème porte déjà les deux noms

Le logo de l'école grave « COMPLEXE SCOLAIRE LE SAGE » en haut et « THE WISE
SCHOOL INTERNATIONAL » en bas, autour d'une étoile d'or. **Ne les redites pas à
côté** : la carte d'élève affichait le nom anglais deux fois, à deux
centimètres d'intervalle, parce que la ligne sous le nom retombait sur lui
faute de devise saisie.

### Ce qui ne prend PAS les couleurs de la charte

- **L'interface** garde le bleu du logiciel.
- **L'or du drapeau congolais** sur les cartes d'élève, sous « République
  Démocratique du Congo » — c'est le drapeau, pas un choix de charte.
- **Les couleurs par classe** : distinguer les classes est une fonction.
- **Les couleurs sémantiques** — vert d'un paiement, rouge d'une dette, orange
  d'une alerte. Elles disent un état, pas une identité.

---

## Les documents officiels congolais

Un document scolaire, en RDC, se lit de haut en bas comme une **chaîne de
responsabilité**. Une administration qui le reçoit la remonte pour savoir à qui
s'adresser.

```
              RÉPUBLIQUE DÉMOCRATIQUE DU CONGO
   MINISTÈRE DE L'ÉDUCATION NATIONALE ET NOUVELLE CITOYENNETÉ
     Province éducationnelle de …  ·  Sous-division de …

  [emblème]  COMPLEXE SCOLAIRE LE SAGE            N° 042/2025-2026
             The Wise School International         Kinshasa, le …
             Kabambare 4367, Quartier Bon Marché
             Code école : …   ·   Agrément DGEP : …
```

**Le ministère a changé de nom** : ce n'est plus l'EPST mais le Ministère de
l'Éducation Nationale et Nouvelle Citoyenneté. C'est pourquoi il doit être un
**réglage** et non une constante — il changera encore.

**Le SERNIE** — Service National d'Identification des Élèves — attribue à chaque
élève un numéro qui le suit de l'entrée à la sortie de son cursus, code les
écoles, et **authentifie les titres scolaires**. C'est ce numéro qu'une
administration vérifiera, pas un matricule interne.

### Un numéro d'ordre, pas une référence calculée

Une référence de la forme `CS-20260801-a3f9`, dérivée de l'identifiant interne,
ne s'ordonne pas, ne se vérifie pas, et deux tirages du même document portent le
même numéro. Un **registre de délivrance** se tient par numéro d'ordre
séquentiel, par année scolaire : une administration doit pouvoir demander
« montrez-moi le n° 42 ».

Un **duplicata se déclare** sur sa face et garde le numéro d'origine. Sans cela
deux documents identiques circulent sans qu'on puisse dire lequel fait foi.

### Où signe-t-on

Dans un document administratif francophone, l'autorité qui délivre signe à
**DROITE**, sous le lieu et la date ; le bénéficiaire acquitte à **GAUCHE**.

**Le visa imprimé de l'école n'efface jamais la ligne de celui qui accomplit
l'acte.** Sur un reçu, le caissier signe de sa main devant la famille qui paie,
à côté du visa. Une signature qui s'imprime toute seule ne signe plus rien —
et pré-imprimer celle de la Direction la donnerait à quiconque produit un reçu.

Trois colonnes, donc : **bénéficiaire · acteur · autorité**.

### Quel document se signe — et lequel ne se signe pas

Règle donnée par Loms le 4 août 2026, à partir d'un couple : *« le reçu doit
avoir la signature ; le cahier de préparation, pas de signature, juste le
logo »*.

> **Un document se signe pour DEUX raisons, et deux seulement.**
> **DÉLIVRANCE** — il engage l'école envers un tiers. **CERTIFICATION** — il
> reste dans l'école, mais quelqu'un répond de son exactitude.
> Tout le reste est un document de **travail** : emblème, pas de signature.

La deuxième raison n'était pas dans la première rédaction. **La règle a buté
sur le kit d'urgence médicale** : il ne quitte pas l'école, mais il porte des
groupes sanguins et il est signé. Ce n'est pas une délivrance, c'est quelqu'un
qui répond d'une donnée dont dépend une vie. *On n'a pas forcé le cas dans la
règle : c'est la règle qui était trop étroite.*

Le motif de fond : **une signature sans raison d'être dévalue toutes les
autres.** Si l'enseignant signe son cahier de préparation, celle du caissier au
bas d'un reçu ne veut plus rien dire de particulier.

`tools/audit-signature.mjs` tient le classement des 46 documents et refuse dans
les deux sens — la signature manquante **et** la signature de trop.

**Posées le 4 août 2026** dans `_officialFooter`, appelé par quinze documents.
La colonne du milieu porte l'**auteur enregistré** de l'acte quand il existe. Si l'autorité *est*
cette personne, elle ne signe pas deux fois : l'autorité redevient la Direction
Générale — et si l'école n'en déclare aucune, aucun nom ne s'imprime.

**Auteur enregistré, ou personne qui délivre — ce n'est pas la même chose.**
Le pied disait « Établi par » et nommait la personne CONNECTÉE. Un reçu
réimprimé trois mois plus tard par la Direction annonçait donc « Établi par la
Direction », alors que c'est la caissière qui avait encaissé devant la famille.
Deux titres désormais : **« Établi par »** quand l'auteur est enregistré — nom,
profil, date de l'acte, identiques à chaque réimpression — et **« Délivré
par »** sinon. Une réserve honnête vaut mieux qu'un nom présenté comme celui de
l'auteur alors qu'il ne l'est pas.

Et la conséquence du principe « avant de lire un champ, vérifier qu'une
écriture le renseigne » : six reçus ne pouvaient pas nommer leur auteur, parce
que `DB.payments` passait à `paid:true` par un `patch` qui ne portait ni qui ni
quand. Champ demandé à ChatGPT — écrit côté serveur, car un auteur que le
navigateur choisirait ne vaudrait rien.

> **SERVI, ET RESTÉ MUET PENDANT DES JOURS.** ChatGPT a livré P0-1 : un
> déclencheur inscrit `recorded_by`, `recorded_by_name`, `recorded_by_role`
> sur chaque écriture de `payments`, et les **fige** à la mise à jour pour
> qu'aucune réimpression ne réécrive l'auteur d'un acte passé. Le navigateur,
> lui, lisait toujours `by` — l'ancien champ. `_auteurDesLignes` rendait donc
> `null`, et **les dix-sept documents qui l'appellent retombaient sur
> « Délivré par »**. L'information était dans la base ; aucun papier ne la
> portait. Troisième fois que je trouve un lot servi que personne n'appelle :
> **avant de coder, chercher ce que l'autre a déjà livré** — et **relire cette
> note-ci avant de la redemander.**

Corrigé au passage : l'autorité du reçu de versement était **la caissière
elle-même**. La caissière n'est pas sa propre autorité.

Même famille, trouvée le même jour sur les **fiches de paie** : elles portaient
« Bénéficiaire — <nom> » et « Direction — <nom de l'ÉCOLE> ». La seconde case
nommait l'école, donc personne, et **aucune case ne revenait à celui qui avait
établi la paie** — sur un document où quelqu'un décide d'un montant versé à un
employé. Les deux fiches sont passées sur le pied commun, avec le bénéficiaire
nommé, l'auteur résolu depuis `sal.by`, et une autorité qui est une personne.

À retenir : **`salaries` enregistre son auteur, `payments` ne l'enregistre
pas.** La même question, deux réponses opposées selon la table — c'est le
symptôme à décrire à ChatGPT, pas à corriger soi-même.

**Et un piège trouvé en le faisant :** `dist/index.html` porte en dur une vraie
signature manuscrite (`window.SCHOOL_SIGNATURE`, ~40 Ko). Elle n'est pas un
exemple : c'est le **repli**. Une installation qui n'a rien téléversé imprime
celle-là, sur les bulletins, dans la case « Direction ». C'est exactement ce que
le paragraphe ci-dessus interdit, et c'est aussi une image de sceau dans un
dépôt. **Signalé à Loms, pas retiré** — on ne supprime pas seul la signature de
quelqu'un. Voir `docs/CHARTE_SITE.md` §8.3.

### Un assistant partagé échappe aux reprises

Le pied de page officiel n'appartient à aucun document : il est *appelé* par
quatorze d'entre eux. Il avait gardé l'ancien papier crème quand tous les
autres avaient été repris. **Ce qui est partagé se corrige à part.**

---

## Les leçons qui valent dans n'importe quel code

### `new Function(corps)` ne voit pas une page blanche

Une faute de portée est du JavaScript parfaitement valide : elle n'existe qu'à
l'exécution, et elle **interrompt le rendu de l'écran entier**. L'utilisateur ne
voit pas d'erreur — il voit une page vide, et en conclut que l'application ne
lui envoie rien.

| écran | faute | ce que voyait l'utilisateur |
|---|---|---|
| Devoirs du parent | un drapeau déclaré dans la boucle, lu par une fonction au-dessus | page blanche dès qu'une interro existait |
| Accueil du parent | un nom lu dix lignes avant son `const` | page blanche dès le **premier devoir publié** |
| Accueil Direction 2 | idem, sept lignes trop tôt | page blanche dès qu'une classe a élèves **et** matières |
| État financier | deux noms lus chez le renderer voisin | **aucun PDF ne sortait** |

C'était toute l'explication de « les parents ne reçoivent rien ». Le devoir
était là ; l'écran ne s'affichait plus. Et la faute ne se déclenchait qu'une
fois qu'il y avait quelque chose à montrer.

→ `tools/audit-portee.mjs`, éprouvé dans les deux sens.

**Une cinquième, commise le 11 août 2026, et elle ne se voit pas à la
relecture.** En écrivant un commentaire HTML *à l'intérieur d'un littéral de
gabarit*, j'ai cité un nom de classe entre accents graves :

```js
return `… <!-- l'action d'une `ww-toolbar` est un `.btn` -->  …`;
```

L'accent grave **ferme la chaîne**. Tout ce qui suit devient du code, et le
bloc `<script>` entier cesse de se parser : **l'application ne démarre plus
du tout**. Le navigateur l'a dit en une ligne, la relecture ne l'aurait
jamais vu — un commentaire ne se relit pas comme du code.

Deux réflexes : **jamais d'accent grave dans un gabarit**, et le contrôle
qui coûte trois secondes avant de livrer —

```bash
node -e "…new Function(bloc)…"   # chaque <script> se parse-t-il ?
```

`audit-portee` le prend aussi, parce qu'il *parse* le fichier : un audit qui
lit vraiment le code attrape des fautes qu'il ne cherchait pas.

**Les quatre étaient intactes dans ce dépôt-ci**, aux mêmes écrans, trouvées et
corrigées le 3 août 2026 (voir `docs/AUDIT_CLAUDE.md` §3). Elles ne se recopient
pas d'une installation à l'autre : elles se réécrivent. Lancer l'outil avant
chaque Pull Request est donc moins une précaution qu'une habitude.

### Une seule réponse par question

Quand deux écrans répondent à la même question, ils doivent **appeler le même
code** — pas le recopier. Mesuré : deux copies d'une formule de classement
avaient divergé sur trois points, et le même élève valait 79 sur un écran et 73
sur l'autre. Un élève diplômé l'an dernier trônait encore en tête de l'école.

Même famille : deux calculs de solde, deux définitions de « avoir payé », cinq
manières de dire si un enfant est sorti de l'école. À chaque fois, deux écrans
qui se contredisent devant la même famille.

**Le remède est un normaliseur** — une fonction qui répond, et que tout le monde
appelle. Quand deux générations de code emploient des noms différents, on
réconcilie **à la lecture** plutôt que de reprendre les écritures d'une
application en service.

**Dans ce dépôt-ci, la formule était recopiée NEUF fois** — trouvé le 5 août
2026 en réparant `verif-coherence`, qui réclamait un `_classer` inexistant ici.
Les neuf copies divergeaient sur six points, et chacun se voit par une famille :

| | |
|---|---|
| conduite absente | **0 %** sur cinq écrans, **75 %** sur trois autres — 51 au palmarès, 62 sur la fiche du même enfant |
| élève archivé | compté dans **tous** les classements de l'année en cours |
| ex æquo | présent dans **une** copie sur neuf |
| trimestre | le Top 10 lisait `currentTrimestre` à côté d'un palmarès qui écoutait l'écran |
| coefficients | le rapport de fin d'année les **ignorait** — coeff 3 pesait comme coeff 1 |
| `cid` absent | deux tableaux de bord filtrent le podium dessus : **« Top palmarès » était vide en permanence** |

Trois normaliseurs en sont sortis : `_classer` (9 appelants), `_totalSection`
(3), `_prepLire` (6). Et deux leçons qui valent au-delà :

1. **Le rang IMPRIMÉ doit venir du même code que le rang affiché.** Deux des
   neuf copies vivaient dans les bulletins PDF. Quand le papier contredit
   l'écran, c'est le papier qui reste dans la famille.
2. **Un normaliseur ne sert à rien tant que les écrans ne l'appellent pas.**
   Le faire passer l'audit prend dix minutes ; router les neuf appelants prend
   le reste. C'est la deuxième moitié qu'on abandonne.

`cahier_prep` a donné la même panne dans une autre pièce, et elle vaut d'être
retenue à part : **l'écran de navigation écrit `content/date_prevue/by/status`,
le studio du profil écrit `titre/date_lesson/teacher_id/statut`.** Les colonnes
des deux existent, donc rien n'est rejeté — mais chaque écran ne lisait que la
moitié de sa table. Une fiche remplie dans le studio n'arrivait jamais au suivi
de la Direction, et là où la date manquait, « Invalid Date » s'imprimait.
**Deux vocabulaires qui coexistent ne produisent aucune erreur : ils produisent
une absence, et une absence ne se remarque pas.**

### Un champ mort, et son symétrique

**Avant de lire un champ, vérifier qu'une écriture le renseigne.** Des champs
étaient lus par six écrans et écrits nulle part — la ligne ne s'affichait donc
jamais, et personne ne s'en apercevait puisqu'elle était conditionnelle.

**Avant d'en écrire un, vérifier qu'une lecture s'en sert — et qu'elle en
connaît toutes les valeurs.** Un statut `absent` était écrit par l'enseignant
qui fait l'appel ; aucun écran du parent ne connaissait cette valeur. L'enfant
absent depuis le matin s'affichait « pas encore arrivé » toute la journée,
n'était compté dans aucun total, et ne déclenchait aucune demande de
justification.

### Un état visuel se calcule du FOND, jamais de la destination

La barre d'onglets peignait un bouton inactif d'après le mode de l'onglet vers
lequel il **mène**. Sur un onglet clair, tout bouton menant à un onglet sombre
était donc blanc à 55 % — **sur fond clair**.

Mesuré : **1,07:1**. Le texte était là, mathématiquement illisible. Trois
onglets disparaissaient d'un coup.

Corollaire : **mesurer les contrastes, ne pas les estimer.** Un rapport se
calcule en quatre lignes ; l'œil se trompe, surtout sur les demi-transparences.

**Et mesurer contre le VRAI fond, pas contre le fond déclaré.** L'écran de
connexion a coûté cette leçon le 4 août 2026. Sa règle CSS annonce un dégradé
sombre : mesurés contre lui, les sept textes donnaient de 4,95 à 12,7:1, tous
au-dessus du seuil. Mais ce dégradé est **recouvert d'une photographie**, et le
voile qui l'assombrit ne descendait qu'à **5 % en haut de l'écran** — là où se
trouvent justement les champs. Sur un visage en plein soleil, « Adresse
e-mail » ne se lisait plus. Les chiffres étaient bons et l'écran illisible.

> **Quand un texte repose sur une image, on ne mesure pas contre une couleur :
> on compose les couches — photographie, voile, carte — et on prend le pire cas
> possible, une photographie entièrement BLANCHE.**

Ainsi mesuré, le pire cas donnait 3,70:1 pour le sous-titre et 4,07:1 pour le
nom du champ. La carte de connexion a donc reçu son propre fond (68 % en haut,
78 % en bas) : dix couples, quatre situations, **tous au-dessus du seuil même
sur une photographie blanche**. Une carte qui ne pose pas son fond dépend d'une
image que personne ne contrôle.

### Le secondaire ne pèse pas quatre fois le principal

Le même écran empilait **quatre boutons pleine largeur identiques** sous
l'action principale : 232 px de secondaire contre 54 px pour « Se connecter ».
Rien ne se distinguait — et « Première connexion », l'action de tout nouvel
enseignant en septembre, se noyait au milieu.

Trois défauts, tous de hiérarchie et non de style :

1. **Une forme unique pour cinq intentions** ne hiérarchise rien. Le remède
   n'est pas de colorer différemment, c'est de **changer de forme** : un bouton
   plein, des liens de texte, un pied de page.
2. **Un bouton qui apparaît selon le navigateur change la hauteur de la page.**
   « Installer l'application » n'existe pas sur iOS : la composition n'était
   jamais celle qu'on avait dessinée. Rangé dans une rangée à contenu variable,
   il ne déplace plus rien.
3. **Deux vocabulaires d'icônes** — trois émojis et deux dessins vectoriels
   côte à côte — donnent l'impression d'assemblé, jamais de conçu.

Résultat mesuré : le secondaire passe de **4,3× à 1,4×** l'action principale, et
la carte tient sans défiler sur un téléphone de 390 px.

**Trouvé au passage, et c'est la vraie leçon :** l'écran portait encore un
avertissement « ouvre l'application depuis le lien contenant `?school=…` » —
le modèle multi-écoles retiré le 3 août. Il était en `display:none` et **aucun
code ne le montrait jamais** : du texte mort qu'aucun audit ne cherche, parce
qu'un audit vérifie ce qui s'affiche, pas ce qui ne s'affiche plus.

### Un document s'imprime — il ne se photographie pas

Rastériser une page (html2canvas et compagnie) dépend du navigateur, de la
largeur de la fenêtre, du moment où les images arrivent, de la mémoire du
téléphone. Quand une seule de ces conditions manque, **on n'obtient pas une
erreur, on obtient du blanc**. C'est ce qui rend le défaut introuvable.

Trois pièges ont été corrigés un par un — et les PDF sortaient toujours vides.
Le défaut n'était pas dans les réglages, il était dans la méthode.

Le navigateur sait imprimer : vraies polices, texte sélectionnable, pagination
correcte, « Enregistrer au format PDF » offert partout, fichier dix fois plus
léger. Et il sait ce qu'une image ne saura jamais :

- l'en-tête d'un tableau **se répète en haut de chaque page**, et aucune ligne
  n'est coupée en deux ;
- un titre ne reste jamais seul en bas d'une page ;
- trois lignes minimum de part et d'autre d'une coupure ;
- **le bloc des signatures ne se coupe jamais** — une signature séparée de son
  intitulé ne signe plus rien.

Et **un PDF vide ne vient jamais du HTML** : vérifier d'abord que le contenu
existe (il faisait 127 Ko) avant de soupçonner la mise en page.

### Une carte a une largeur FIXE

Elle ne s'ajuste à rien. Un courriel de 36 caractères et un numéro international
côte à côte débordaient les 340 px du badge ; le corps étant un `flex:1` qui
pousse le pied, **le pied sortait de la carte**.

Le budget se **calcule**, il ne s'estime pas : 561 px réclamés pour 440
disponibles, soit 121 px hors cadre. Trois décisions dans cet ordre — regrouper
ce qui est une seule information, retirer le décor, resserrer d'un ou deux
pixels partout — puis une **garantie** : le bloc peut rétrécir, le corps découpe
ce qui dépasserait. Un pied de page coupé est un défaut ; une adresse abrégée
n'en est pas un.

Tout bloc d'une rangée doit pouvoir rétrécir (`min-width:0`) et toute valeur
s'abréger — **sauf le courriel**, qui abrégé ne sert plus à rien.

**La même leçon, par l'autre bout — 11 août 2026.** Loms : *« le bouton
WhatsApp est petit, difficile à utiliser ; qu'il soit de la même taille que
les autres. »* Mesuré : **34,7 × 17,5 px contre 36 px** pour ses voisins. La
cause n'était pas un réglage : **ce n'était pas un bouton.** C'était un lien
avec ses styles écrits à la main, donc il n'héritait d'aucune règle commune —
ni la hauteur, ni le minimum tactile que `.btn` pose à 44 px pour tout le
reste. *Un élément qui se peint lui-même échappe à toutes les reprises.*

Et en mesurant la rangée avant de l'agrandir, le vrai défaut est apparu :
**elle débordait déjà.** Cinq éléments réclamaient 443 px pour 356
disponibles. À 390 px, « Suppr. » commençait à 388 alors que la carte
s'arrête à 383 — **entièrement hors du cadre** — et « Ouvrir l'accès » se
cassait sur trois lignes.

> **Un petit bouton n'est pas toujours un choix de style : c'est souvent le
> symptôme d'une rangée qui ne tient pas.** On l'avait rapetissé pour le
> faire entrer, et il n'entrait toujours pas.

Deux choses à en retenir de plus :

1. **Quand le budget ne peut pas tenir, on passe à la ligne.** Un bouton
   coupé est un défaut ; une seconde ligne n'en est pas un. Écraser des
   boutons pour tenir sur une ligne, c'est choisir le pire des deux.
2. **Agrandir un texte illisible ne fait qu'agrandir l'illisible.** Le blanc
   sur le vert WhatsApp donne **1,98:1**. L'encre sur ce même vert donne
   **8,12:1**. Le vert reste — c'est lui qui dit « ça sort de l'application »
   — mais il ne porte plus de blanc.

### L'argent

Toujours un lecteur de montant dédié, **jamais `parseFloat`** :
`parseFloat('12,50')` vaut **12** — la virgule est le séparateur décimal ici.
Trente et une saisies d'argent étaient concernées.

Un lecteur correct accepte « 12,50 », « 1 200 », « 1.200,50 » et **refuse**
« 1O0 » (la lettre O). Refuser vaut mieux qu'interpréter.

Et une seule porte d'entrée pour l'argent : reçu, recette et écriture comptable
partent ensemble, ou rien ne part. Un encaissement qui contournait cette porte
n'apparaissait dans aucun total.

### Un repli qui ne peut pas réussir est un mensonge poli

**5 août 2026.** Loms : *« je tape le mail et le code pour me connecter, ça
marche pas »*. La cause n'était pas là où elle se plaignait.

`tryLogin` avait deux chemins. Client Supabase présent → adresse + mot de
passe. **Sinon → nom + code PIN**, comparé à `users.pin`, `pin_hashed`,
`pin_hashed_v2` — trois colonnes qui **n'existent pas**. PostgREST refuse une
lecture qui nomme une colonne inconnue : la requête échouait en entier, et la
comparaison rendait toujours faux.

Donc dès que le client d'authentification ne se créait pas — CDN filtré, réseau
qui bloque, appareil hors ligne — l'application basculait **en silence** sur ce
chemin et répondait « Nom ou code incorrect » à une adresse et un mot de passe
parfaitement justes. Rien ne disait qu'on ne parlait même pas au serveur.

> **Un repli vers un chemin qui ne peut plus aboutir est pire que pas de repli
> du tout** : il transforme une panne d'infrastructure en accusation contre
> l'utilisateur. Quand la seule porte n'est pas joignable, on le DIT.

Trois familles de défauts trouvées en tirant ce fil, et elles se répètent
partout ailleurs :

1. **Quatre pannes portaient le même message.** « Compte non autorisé ou
   désactivé » couvrait : aucun profil rattaché à cette identité · compte
   désactivé · rôle inconnu · lecture échouée. Celui qui le lit ne peut ni le
   corriger ni le décrire, et celui qui dépanne ne sait pas quoi chercher.
2. **Trois boutons ne faisaient rien.** « Mot de passe oublié » et « Première
   connexion » sortaient en silence quand le client était absent — `if (!x)
   return;`. On appuie, rien ne se passe, on croit l'application cassée. **Un
   `return` muet dans un gestionnaire de clic est toujours un défaut.**
3. **Une panne de réseau n'est pas un mot de passe refusé.** Les confondre
   envoie quelqu'un ressaisir vingt fois un mot de passe correct.

Et une règle de sécurité qui se perd facilement : **le message de récupération
doit être le MÊME que l'adresse existe ou non.** Sinon on découvre, une adresse
à la fois, qui a un compte dans cette école.

**Ce qui reste ouvert, et qui n'est pas de notre côté :** `save_school_user_profile`
exige d'être **déjà** Direction pour créer un compte, et la connexion cherche le
profil par `users.auth_user_id`. Tant qu'il n'existe pas une Direction active
avec son identité Auth rattachée, personne ne peut entrer — et aucune correction
du navigateur n'y changera rien. C'est P0-10 dans `DEMANDES_A_CHATGPT.md`.

### Une lecture qui ÉCHOUE n'est pas une lecture qui ne trouve RIEN

**5 août 2026**, la même journée, en tirant le fil suivant. Loms : *« quand tu
es connecté à ton compte, après un temps, l'application rejette ton mot de passe
quand tu essaies de te connecter, ça refuse. »*

`_get` rend `null` pour **tout** échec — jeton expiré, RLS qui refuse, serveur en
panne, réseau muet — et la connexion traitait ce `null` exactement comme un
tableau vide. Mesuré au navigateur, **mot de passe bon dans les cinq cas** :

| ce qui se passait vraiment | ce que l'écran répondait |
|---|---|
| aucun profil rattaché | « Mot de passe accepté, mais aucun profil n'est rattaché à cette adresse » |
| jeton expiré (401) | *le même, mot pour mot* |
| RLS refuse (403) | *le même* |
| serveur en panne (500) | *le même* |
| réseau muet | *le même* |

…et la personne était **déconnectée** dans la foulée, à chaque fois. Quatre fois
sur cinq c'était faux : le compte existait, le mot de passe était bon, seule la
lecture avait échoué.

Trois choses à retenir, et elles dépassent la connexion :

1. **Un rendu `null` qui confond « pas trouvé » et « je n'ai pas pu chercher »
   fabrique des accusations.** Le nom qu'on affiche ensuite désigne un coupable
   — ici l'utilisateur et son mot de passe — alors que la panne est ailleurs.
2. **L'information manquante était déjà là.** `_noteReadState` relève le statut
   HTTP depuis le contrat `ROLE_LOAD`, avec un commentaire qui dit exactement
   pourquoi : *« Seul le statut HTTP le dit. »* Il n'a jamais été lu ici. Une
   moitié du dépôt savait ce que l'autre ignorait.
3. **Une panne d'infrastructure ne doit pas déconnecter.** Déconnecter oblige à
   tout recommencer et transforme un hoquet de réseau en « ça refuse ». On ne
   sort que si l'identité est inutilisable : aucun profil, compte désactivé,
   rôle inconnu, jeton invalide.

Et le corollaire pour Kinshasa : **un seul aller-retour ne décide pas de l'accès
de quelqu'un à son école.** `_lireMonProfil` réessaie trois fois, 400 ms puis
800 ms — mais seulement sur les pannes passagères. Un 401, un 403 ou un 404
rendront la même chose une seconde plus tard : les réessayer ne fait qu'ajouter
de l'attente à un refus.

### Un compteur n'est pas un registre

**10 août 2026, P0-8.** Les cartes d'élèves tenaient sur trois champs plats
posés sur `students` : `card_printed` (une bascule), `card_print_date`,
`card_print_count`. Trois défauts, et chacun se voit par une famille :

| | |
|---|---|
| le « duplicata » | incrémentait le compteur et réimprimait **la même carte**. L'ancienne restait valable au portail : une carte perdue dans la rue ouvrait toujours l'école |
| « imprimé » | était une bascule qu'on pouvait remettre à zéro. La date s'effaçait avec elle, et **rien ne gardait qui avait imprimé** |
| le QR de la carte | valait `schoolsafe://student/<matricule>` — **non signé**. Le scanner refuse un QR non signé 30 jours après la pose du secret : toute carte imprimée aurait affiché « CARTE PÉRIMÉE » au bout d'un mois, et un matricule connu suffisait à fabriquer le même QR |

Trois leçons, et elles dépassent les cartes :

1. **Un compteur répond « combien », jamais « lequel ».** Dès qu'une pièce
   peut être remplacée, il faut une ligne par exemplaire : un numéro, un
   état, un auteur, une date, un motif. Sinon on ne peut ni invalider l'une
   sans l'autre, ni dire laquelle fait foi.
2. **Ce qui invalide doit invalider AVANT que le remplaçant existe.** Une
   seconde à deux cartes valables est une seconde de trop, et l'ordre des
   deux écritures est la seule chose qui le garantit.
3. **Deux QR, deux durées de vie, et la différence doit se lire dans le
   format.** Le quotidien porte une date et six segments ; le permanent
   porte un numéro de carte et cinq. Un contrôle qui ne sait pas les
   distinguer applique au permanent la règle du quotidien — et c'est
   exactement ce qui périmait les cartes.

Corollaire qui vaut pour tout identifiant imprimé : **le QR permanent ne
porte que le numéro.** Ni nom, ni matricule, ni famille. C'est le registre
qui dit à qui il appartient — donc une carte perdue cesse d'ouvrir le
portail **à la seconde où on la déclare**, sans qu'on ait à la récupérer.

`tools/recette-cartes.mjs` exécute les vraies fonctions sur 36 points, et
`--preuve` retire l'invalidation : **9 points tombent**. Une recette qui ne
sait dire que « oui » ne vérifie rien.

### Un backend servi que personne n'appelle n'existe pas

**10 août 2026, issue #64.** ChatGPT avait livré la sortie en deux étapes en
entier — quatre RPC, une table `student_exit_events` à trente-cinq colonnes,
des photos en pied, des références de pièce, des dates de validité. Le
navigateur n'en appelait **aucune** : `scanExit` lisait `DB.aps` en direct et
écrivait dans `scan_log`.

Le coût, profil par profil, et chacun se voit par une famille :

| | |
|---|---|
| enseignant | **le bouton « Préparer la sortie » n'existait nulle part** — le parent n'était jamais prévenu à l'avance |
| parent | prévenu **après** le départ, par une notification écrite dans le navigateur du gardien : hors ligne, elle ne partait pas |
| gardien | une seule photo de portrait. Ni photo en pied, ni pièce, ni validité — rien de ce qui permet de reconnaître quelqu'un à deux mètres |
| tous | **une accréditation EXPIRÉE passait pour valable**, parce que le filtre sur `valid_until` vit dans la RPC que personne n'appelait |
| tous | aucune séparation entre « la personne est là » et « je l'autorise » |

Trois leçons :

1. **Une donnée filtrée par le serveur ne se relit pas en local.** `DB.aps`
   contient tout ; `get_student_pickup_context` ne rend que ce qui est actif,
   approuvé et dans ses dates. Lire la table directement, c'est refaire le
   filtre — mal, et sans le savoir.
2. **Un geste qui constate et un geste qui engage ne sont pas le même geste.**
   `scan_student_exit_at_gate` dit qui s'est présenté ; `validate_student_exit`
   engage l'école. Les séparer donne au gardien le temps de comparer un visage
   à une photo **avant** que l'enfant soit parti.
3. **L'écran ne dit pas « envoyé » quand le serveur dit `queued`.** Annoncer
   un message qui n'est jamais parti, c'est un parent qui ne rappelle pas.

   **Et il faut lire la forme que le serveur rend VRAIMENT.** J'avais écrit
   `n.email` et `n.whatsapp` d'après le document de contrat. La fonction
   déployée rend `{channels:["app"|"push"], push_status, push_device_count}`
   et **supprime** les lignes e-mail et WhatsApp de la file. Deux canaux
   annoncés à partir de champs toujours absents : un champ mort lu par un
   écran, la faute même que nos audits cherchent — commise en lisant une
   documentation au lieu du code servi. **Un document dit l'intention ; seule
   la fonction dit la forme.**

Et une règle de méthode qui vaut pour tout lot reçu : **avant de coder,
chercher ce que l'autre agent a déjà servi.** Un `grep` des noms de RPC dans
le fichier aurait montré en dix secondes que quatre fonctions livrées
n'étaient appelées nulle part.

`tools/recette-sortie.mjs` rejoue le parcours sur 39 points avec un serveur
en carton qui répond comme les RPC, **profil par profil**. `--preuve` fait
refuser le serveur et vérifie que l'écran n'annonce pas une sortie.

### Effacer une notification, c'est effacer la preuve qu'on a prévenu

**10 août 2026, P0-30.** L'écran des notifications portait un bouton
**« 🗑️ Effacer tout »** qui appelait `pushSync('notifs','delete')`. Le contrat
de ChatGPT dit le contraire — *« une notification n'est jamais supprimée ;
archiver la masque tout en conservant l'historique »* — et la raison dépasse
la technique : **le jour où une famille dit « on ne m'a jamais prévenu »,
c'est cette ligne-là qu'on relit.**

Deux autres défauts du même écran, et chacun se voit par une famille :

| | |
|---|---|
| tout ce qui s'affichait | passait **« lu » d'office**. Une convocation lue en diagonale valait un accusé de réception — donc « prise de connaissance » ne voulait plus rien dire |
| l'état d'envoi extérieur | n'existait pas. Le parent ne savait pas si son téléphone allait sonner |

**Et le chemin du push ne pouvait plus aboutir.** Le navigateur s'abonnait au
Web Push puis écrivait **directement** dans `push_subscriptions` — table
passée en **refus total** par `p0_32a_explicit_device_registry_deny_policy`.
La seule fonction d'enregistrement servie, `register_push_device`, n'accepte
que `provider = 'fcm'`, alors que la décision canonique retire Firebase au
profit du Web Push depuis le VPS. **Aucun appareil ne pouvait donc être
enregistré, et l'application se croyait abonnée.**

Trois leçons :

1. **Un geste destructif se justifie par ce qu'il protège, pas par ce qu'il
   range.** « Effacer » libérait un écran encombré et détruisait une preuve.
   Archiver fait le premier sans le second.
2. **Marquer lu doit rester un geste.** Un état qui se pose tout seul ne
   témoigne de rien, et on ne peut plus distinguer « vu » de « reçu ».
3. **Quand une écriture directe devient impossible, elle ne devient pas
   silencieuse : elle devient un mensonge.** Il faut la retirer, pas la
   laisser échouer discrètement — et dire à l'écran ce qui est vrai.

`tools/recette-notifications.mjs` tient les 33 points, et `--preuve` vérifie
qu'un serveur muet fait dire « je n'ai pas pu regarder » plutôt que « vous
n'avez rien reçu ».

**Une faute commise en écrivant cette recette, et qui vaut d'être notée :**
ses contrôles « plus aucune écriture de ce type » cherchaient la chaîne dans
tout le fichier — **y compris dans les commentaires qui expliquent le
retrait**. La note qui documente la correction faisait échouer le contrôle
qui la vérifie. Un outil teste une condition, jamais une chaîne.

**Ce piège s'est refermé TROIS fois** — sur `recette-notifications`, sur son
contrôle du Web Push, puis sur `recette-auteur-encaissement`. À chaque fois
la même forme : *« ce fichier ne contient plus X »*, avec un commentaire qui
explique pourquoi X a été retiré. Le remède tient en une ligne, et il devrait
être le réflexe :

```js
const code = source.split('\n').map(l => l.replace(/^\s*\/\/.*$/, '')).join('\n');
```

Et sa variante plus profonde : **une condition « absence de X » se périme**.
Le contrôle « aucun `pushManager.subscribe` » était juste tant que
l'abonnement était un chemin mort ; il est devenu faux le jour où
l'abonnement est devenu légitime. Ce qu'il fallait vérifier n'était pas
l'absence, mais *passe-t-il par la RPC, et dit-il la vérité quand le serveur
refuse ?*

### La moitié qui saisit, et la moitié qui lit

**11 août 2026, issue #64.** J'avais livré le portail en deux étapes : il
affiche le portrait, la photo en pied, la pièce d'identité et la validité de
l'accréditation. **Il les affichait vides pour tout le monde** — parce
qu'aucun écran ne permettait de les SAISIR.

Quatre fonctions servies par ChatGPT n'étaient appelées par personne :

```
save_authorized_pickup_person        set_authorized_pickup_person_status
save_primary_parent_pickup_identity  set_student_primary_parent
```

L'écran écrivait directement dans `aps`. Donc : sans le plafond de trois tenu
par un verrou, sans la normalisation du numéro, sans l'audit — et **sans
jamais renseigner ce que le portail lit**.

Trois leçons :

1. **Livrer un écran qui LIT sans livrer celui qui ÉCRIT ne livre rien.** Le
   gardien voyait « Aucune photo en pied » et croyait à un dossier
   incomplet ; c'était l'application qui n'avait pas de porte d'entrée.
   Quand on branche une lecture, chercher tout de suite **qui écrit ce
   qu'elle lit.**
2. **Une photo n'est pas toujours une image.** Le serveur refuse
   `data:` et limite à 2048 caractères : ce sont des **adresses**. Une image
   collée serait refusée avec un code que personne ne relie à la photo. Elle
   monte donc dans le stockage AVANT l'appel, et si la montée échoue, **on
   n'appelle pas** — on le dit.
3. **Une personne autorisée ne se supprime pas, elle se suspend**, avec un
   motif. Même raison que pour les notifications : le jour où on demande
   « qui était autorisé en octobre ? », c'est cette ligne-là qu'on relit.

Et le compte qui décide du plafond n'est pas le nombre de lignes : c'est le
nombre d'**actives, approuvées et non expirées**. Une personne suspendue ne
prend la place de personne — le serveur le calcule ainsi, l'écran doit le
calculer pareil, sinon il refuse un ajout que le serveur aurait accepté.

`tools/recette-personnes-autorisees.mjs` tient 31 points ; `--preuve` retire
le garde-fou de la photo et vérifie que la recette voit passer l'image collée.

### Supprimer une ligne n'est pas retirer un accès

**11 août 2026, P0-13.** `deleteUser` faisait `pushSync('users','delete')` —
une suppression sèche. Trois conséquences, et la troisième est la pire :

1. **L'historique disparaissait avec la personne.** Reçus établis, salaires
   versés, lignes d'audit, notifications envoyées : tout la référence. Le jour
   où une administration demande « qui a encaissé en octobre ? », le nom
   n'existe plus.
2. **Rien ne protégeait le DERNIER compte de Direction.** Le supprimer
   fermait l'école à tout le monde, sans retour.
3. **L'accès n'était pas retiré.** Effacer la ligne applicative ne touche pas
   l'identité d'authentification : la personne « supprimée » pouvait encore
   se connecter. **L'écran disait « supprimé » et le serveur la laissait
   entrer.**

Le serveur servait pourtant le cycle entier — `suspend_school_account`,
`reactivate_school_account`, `prepare_school_account_removal`,
`confirm_school_account_removal` — et personne ne l'appelait. **Quatrième lot
servi trouvé muet.**

Trois leçons :

1. **Un retrait d'accès se fait en TROIS temps**, et l'ordre est la garantie :
   on prépare, une Edge Function retire l'identité, puis on **confirme** — et
   la confirmation REFUSE si l'identité est encore là. Sans cette troisième
   étape, on annonce une fermeture qui n'a pas eu lieu.
2. **Fermer et effacer ne sont pas le même geste.** Suspendre est réversible
   et garde tout ; retirer l'accès est définitif et garde tout aussi. Rien
   n'est jamais supprimé — c'est ce qui permet de répondre, dans dix ans, à
   « qui a fait cela ? ».
3. **L'état du COMPTE passe avant son canal d'accès.** La pastille affichait
   « code envoyé » sur un compte suspendu, ce qui envoyait la Direction
   renvoyer un code à quelqu'un qu'elle venait de fermer.

Et une leçon sur les recettes : **un scénario qu'on fabrique pour atteindre
une garde du serveur ne prouve rien sur le serveur** — seulement sur sa copie
en carton. Ce qu'une recette de frontend doit vérifier, c'est ce que l'écran
FAIT du refus : dit-il ce qui a été refusé, et quoi faire à la place ?

### Les gardes de rôle

Toute fonction exposée globalement qui écrit doit vérifier le rôle.
**Un contrôle dans le rendu n'est pas une sécurité** — cacher un bouton ne
protège rien. Une vingtaine de mutations en étaient dépourvues, dont trois sur
les présences et deux qui manipulaient de l'argent.

Corollaire pour les documents : un certificat **engage l'école**. Il se délivre,
il ne se télécharge pas. Réserver l'émission, et **la tracer** — l'école doit
pouvoir dire ce qu'elle a émis et pour qui.

### Les identifiants

Jamais `'x' + Date.now()`. Deux écritures de la même milliseconde partagent une
clé primaire ; une seule survit. C'est ce qui privait les autres directions de
leurs notifications dans toutes les boucles.

### Une valeur vide n'écrase pas un repli

Les valeurs par défaut s'appliquent **champ par champ**. Remplacer un objet en
bloc faisait qu'un enregistrement portant le seul nom effaçait l'adresse, le
téléphone et le courriel — et le document suivant partait sans indiquer où se
présenter.

### Ne rien afficher vaut mieux qu'afficher faux

Un numéro d'agrément inventé sur un document officiel serait pire que son
absence. Une ligne dont la valeur manque ne s'imprime pas.

Même principe pour un tableau d'honneur : sous un certain effectif, « les trois
premiers » **est** le classement complet — publier reviendrait à publier qui est
dernier. En deçà, la classe paraît avec ses chiffres et aucun nom.

### Un champ qui change de métier change de règles

**6 août 2026.** Le téléphone est devenu ce qui **identifie** un compte —
décision de Loms, livrée côté serveur par ChatGPT.

**L'état final de cette journée est P0-24 : un compte porte une adresse e-mail
OU un téléphone — au moins l'un des deux, jamais zéro — et quand les deux sont
là, les DEUX ouvrent le même compte.**

Trois règles l'ont précédée dans la même journée, toutes **remplacées** :
« e-mail ou téléphone » (P0-20), « téléphone pour tous sauf Direction 1 »
(P0-21), « e-mail ET téléphone obligatoires » (P0-22). Elles ne sont pas
rappelées ici pour être discutées : elles le sont pour qu'on **reconnaisse un
vieux code qui les suit encore**.

Ce que P0-22 a apporté et que P0-24 **garde** : les deux identifiants ouvrent
le même compte, et la connexion passe par le relais `school-login`. Seule
l'**obligation** d'avoir les deux est tombée — un parent de Kinshasa n'a pas
toujours d'adresse, et le compte de Direction 1 n'a pas de numéro.

**Et ce n'est pas symétrique**, c'est ce qui se perd le plus vite : le numéro
ouvre le code par WhatsApp, l'adresse ouvre l'invitation par courriel. Une
fiche sans numéro n'est pas « incomplète » — elle n'a simplement pas cette
voie-là. L'écran doit le dire ainsi, pas comme un reproche.

Tant qu'il ne servait qu'à appeler, `+243 810 000 111`, `0810000111` et
`243-810-000-111` étaient trois écritures du même numéro et personne n'en
souffrait. Devenu identifiant, **trois écritures deviennent trois comptes, ou un
compte introuvable.**

Deux leçons, et la seconde est la vraie :

1. **Quand un champ change de métier, tout ce qui l'écrit et tout ce qui le lit
   change de règles.** Ici : deux formulaires de saisie, l'écran de connexion,
   le bouton WhatsApp, et une contrainte `CHECK` qui refusait désormais ce que
   l'application envoyait depuis toujours — avec un `VALIDATION_ERROR` nu qui ne
   dit même pas quel champ.
2. **La forme canonique appartient au serveur, jamais au navigateur.** Même
   raison que pour le solde. Le navigateur en tient une transcription — pour
   MONTRER ce qui sera enregistré avant d'envoyer — et `audit-telephone.mjs`
   confronte les deux : il extrait les règles littérales du SQL de ChatGPT et
   vérifie qu'elles sont toutes dans le JS. Si le serveur change une règle,
   l'outil tombe. **Deux normalisations qui divergent ne produisent aucune
   erreur : elles produisent un compte introuvable.**

### Une règle peut changer quatre fois dans la journée — l'écran suit, il ne discute pas

Le 6 août, la règle d'accès a changé **quatre fois** : e-mail ou téléphone, puis
téléphone sauf Direction 1, puis les deux obligatoires, puis l'un des deux au
choix. Trois fois sur quatre, ChatGPT avait déjà déployé la base avant que je
lise sa livraison.

Deux réflexes en sont sortis, et ils valent au-delà de ce jour-là :

1. **Regarder ce que l'autre a déposé AVANT de coder**, pas après. J'ai livré
   une consigne à Loms — « active le fournisseur Phone » — qui était périmée
   une heure plus tard. Le canal n'était pas branché en premier.
2. **Quand l'écran est plus permissif que la base, c'est l'écran qui a tort.**
   `save_school_user_profile_dual_impl` refuse à Direction 2 de créer un autre
   Direction 2 ; notre liste d'écran le permettait encore. Une liste plus large
   que ce que le serveur accepte n'ouvre aucun droit : elle fabrique un refus
   que personne ne comprend.

Et une conséquence pour ce fichier : **une leçon périmée est plus dangereuse
qu'une leçon absente.** On ne l'efface pas — on écrit ce qui la remplace, juste
au-dessus, pour reconnaître un vieux code qui la suit encore.

3. **Quand c'est LOMS qui change la règle, le canal passe avant le code.** Sur
   P0-24, j'ai déposé la demande à ChatGPT — les cinq contrôles à ouvrir,
   relevés ligne par ligne dans ses fichiers — **avant** d'écrire une ligne
   d'écran. Puis j'ai libéré le formulaire tout en disant, sur le champ refusé,
   que **le serveur ne l'accepte pas ENCORE**. Ce n'est pas la même chose que
   « vous avez mal rempli », et c'est la différence entre une attente et une
   accusation.

### Un état qui n'existe plus continue de s'afficher

Trouvé le même jour, dans la liste du personnel : la pastille
**« PIN : •••••• »**. Les codes PIN avaient été retirés la veille — 125 lignes
qui comparaient la saisie à trois colonnes inexistantes. L'affichage, lui, était
resté.

Trois listes posaient la même question — *où en est l'accès de cette personne ?*
— et y répondaient chacune à sa façon : une adresse, un PIN fantôme, rien du
tout. `_pastilleAcces` et `_boutonAcces` les servent désormais toutes les trois.

**Une pastille qui ment sur un état envoie chercher au mauvais endroit** le jour
où quelqu'un n'arrive pas à entrer — et c'est ce jour-là qu'on la croit.

### Ce que le serveur refuse tant qu'un code temporaire n'est pas remplacé

Le contrat de ChatGPT fait rendre `NULL` à `current_app_role()` tant que la
personne n'a pas remplacé le code reçu par WhatsApp. La RLS ne laisse alors voir
**aucune ligne** — pas même son propre profil.

Donc l'état d'accès (`get_my_access_state`) se demande **AVANT** de lire `users`.
Lire d'abord aurait rendu un tableau vide, donc « aucun profil n'est rattaché à
cette adresse » : **une accusation portée contre quelqu'un qui a fait exactement
ce qu'il fallait.** C'est la leçon de la lecture qui échoue, appliquée d'avance.

Et son corollaire : **`updateUser({password})` qui réussit ne suffit pas.**
Le serveur doit CONSTATER le changement (`confirm_parent_phone_password_change`,
qui compare l'empreinte du hash Auth). Sans cet appel, `must_change_password`
reste vrai : la personne croit avoir terminé et ne voit toujours rien. Un écran
qui félicite pendant que le serveur bloque est la pire des réponses.

### Un refus du serveur dit où passer — il ne dit pas d'abandonner

**11 août 2026, issue #96.** Loms : sur un compte qui a déjà un accès ouvert,
« Modifier » ne pouvait pas corriger une faute de frappe dans un numéro. Le
serveur refusait, et il avait raison :

```sql
if v_exists and v_current.auth_user_id is not null then
  if v_current.phone is distinct from v_phone then … AUTH_PHONE_CHANGE_REQUIRED
```

Changer un numéro, c'est changer une **identité de connexion** — cela ne se
fait pas par la même porte qu'un changement d'initiales. La porte existait
depuis le matin même : l'Edge Function `school-contact-change`, qui met
`public.users`, `public.profiles` et l'identité Auth d'accord **sans toucher
au mot de passe**. C'est ce dernier point qui la sépare de « Réinitialiser
l'accès » : corriger un chiffre ne doit pas obliger quelqu'un à recevoir un
nouveau code et à tout recommencer. **Deux gestes, deux boutons.**

Et l'ordre des deux appels est la garantie, pas un détail : l'identité
d'abord, la fiche ensuite. Dans l'autre sens, `save_school_user_profile` voit
encore l'ancienne coordonnée et rend le même refus.

Trois défauts trouvés en tirant le fil, et chacun se voit par une famille :

1. **Le message renvoyait au mauvais bouton.** `AUTH_PHONE_CHANGE_REQUIRED`
   disait *« se change par le bouton d'accès, pas par cette fiche »*. Depuis
   la livraison, c'est exactement par cette fiche. Une leçon périmée est plus
   dangereuse qu'une leçon absente — un message aussi.
2. **La fiche locale était écrasée AVANT l'appel.** `Object.assign` en tête du
   chemin : un refus laissait l'écran afficher une valeur que la base n'a
   jamais portée. On ne change ce qu'on montre qu'après le succès.
3. **Direction 2 effaçait l'adresse qu'elle ne voyait pas.** Son `ROLE_LOAD`
   ne charge pas `users.email` : le champ s'affichait vide, et **partait
   vide**. Corriger un nom d'enseignant lui retirait son adresse, sans un mot.

Le remède du troisième vient du serveur lui-même, et il vaut partout :

```sql
v_email := case when p_user ? 'email' then … when v_exists then v_current.email end
```

> **Une clé ABSENTE garde la valeur du serveur ; une clé vide l'efface.**
> Quand l'écran ne voit pas un champ, il ne l'envoie pas — et il écrit qu'il
> est conservé, au lieu de laisser croire qu'il n'existe pas.

`tools/recette-contact.mjs` tient 64 points ; `--preuve` retire la route et
la recette **revoit la panne d'origine** — aucun numéro corrigé.

### Un refus lu comme un silence devient une entrée enregistrée

**11 août 2026, issue #94.** ChatGPT sépare le droit de **scanner physiquement**
de l'**accès QR de la caissière** : `private.can_physical_scan()` = Direction 1,
Direction 2, Enseignant, Gardien — la Caisse dehors. Trois listes du navigateur
étaient plus larges que lui, et **une liste plus large que le serveur n'ouvre
aucun droit : elle fabrique un refus que personne ne comprend.**

Elles étaient trois parce qu'elles étaient **recopiées**, et les trois copies
avaient divergé : l'écran admettait la Caisse, `processScanEntry` admettait
« tout le personnel sauf le parent », `_enregistrerPassage` admettait la Caisse.
Une seule liste désormais — `ROLES_SCAN_PHYSIQUE` — et trois appelants.

**Mais le vrai défaut n'était pas la liste, et il ne se voyait pas en la
lisant.** `_rpcData` rendait `null` pour **tout** échec. Son unique appelant
lisait donc un REFUS comme un SILENCE, retombait sur la file hors ligne,
écrivait le passage, inscrivait la présence — et l'écran annonçait l'entrée.
Mesuré en réinjectant le défaut dans le vrai code : sur un `42501`, l'écran
affichait **« À l'heure »**.

> **Poser un garde côté serveur sans regarder ce que le navigateur fait de son
> refus, c'est transformer une sécurité en mensonge.** Le refus était la
> fonctionnalité ; l'annoncer comme un succès la retournait entièrement.

Trois leçons :

1. **La leçon de « une lecture qui ÉCHOUE n'est pas une lecture qui ne trouve
   RIEN » vaut aussi pour les ÉCRITURES** — et elle y coûte plus cher : une
   lecture ratée affiche un vide, une écriture ratée invente un fait.
2. **Ce qui sépare un refus d'un silence doit être une PREUVE, pas une
   impression.** Ici le SQLSTATE : PostgreSQL le rend toujours sur cinq
   caractères, un réseau coupé n'en produit aucun. Sa présence prouve que le
   serveur a parlé. On ne devine pas la nature du refus — on constate seulement
   qu'il y en a eu un.
3. **Et il faut garder l'inverse avec la même force.** Un serveur MUET doit
   toujours passer par la file : un gardien devant un portail de Kinshasa ne
   peut pas attendre le réseau. Confondre les deux dans un sens fabrique un
   mensonge, dans l'autre bloque un portail. La recette tient les deux.

Trouvé au passage, et c'est la famille habituelle : le motif du refus était
écrit **deux fois**, et la copie du retard léger avait déjà perdu « élève
inconnu du serveur ». `_refusPassage` répond seul aux deux. Et le bouton
**`📷 Scanner`** de « Contrôle des frais » — seul chemin par lequel la Caisse
atteignait l'enregistrement — ne s'affiche plus que pour qui peut scanner :
**un bouton qui répond « Accès refusé » est un défaut, pas une protection.**

`tools/recette-scanner-physique.mjs` tient 45 points, profil par profil.
`--preuve` **réinjecte les deux défauts d'origine dans la source réelle** — la
Caisse dans la liste, et le refus qui retombe dans la file — et vérifie que la
recette les revoit **tous les deux nommément**, pas seulement en nombre.

**Ce qui reste au serveur :** le DRAFT `p0_scan_physical_role_separation` se
termine par un `ROLLBACK` volontaire. Le navigateur est prêt ; **la base ne
l'est pas encore**, et c'est Loms qui décide de la fusion.

### Un secret dans le navigateur est un secret publié

**11 août 2026, issue #102.** ChatGPT a livré le registre serveur des cartes —
`public.student_cards` et cinq RPC. Le navigateur, lui, continuait à faire trois
choses qu'il n'aurait jamais dû faire, et la troisième cassait tout :

| | |
|---|---|
| il **signait** le QR permanent | avec `DB.settings.qr_secret`, descendu sur l'appareil. Qui le lit fabrique une carte que le portail accepte |
| il **numérotait** les cartes | par un `length + 1` sur le registre local — deux Directions qui émettent en même temps produisent **deux pièces n° 42**, et un registre de délivrance qui se répète ne prouve plus rien |
| il **décidait** au portail | en lisant `DB.student_cards`. Or le **gardien n'a aucune lecture sur cette table** : son registre local est toujours vide, donc **toute carte valable lui répondait « CARTE INCONNUE »** |

Le troisième est le plus instructif : *le contrôle marchait parfaitement chez
tous ceux qui n'en avaient pas besoin, et échouait chez le seul qui s'en sert.*
Un droit de lecture restreint ne se voit pas depuis un compte Direction.

> **Quand le serveur prend une décision, le navigateur ne la double pas : il la
> DEMANDE.** Doubler, c'est fabriquer une seconde vérité — plus permissive quand
> elle a le secret, plus stricte quand elle n'a pas les données.

Corollaire écrit dans le code : **une carte ne s'émet pas hors ligne.** Le
numéro, la signature et l'invalidation de l'ancienne sont une seule transaction
serveur ; la couper en deux, c'est risquer deux cartes actives. Une déclaration
de perte gardée dans la file laisse la carte ouvrir le portail — c'est le seul
geste du registre qu'on ne peut pas différer. Hors ligne, on refuse et **on le
dit**.

### Un cache qui ment vit rarement sur l'appareil qui pourrait le corriger

**Même audit, point 5.** `_cacheAcces` gardait la décision du portail cinq
minutes. Le cas réel : enfant refusé pour frais → la famille régularise à la
Caisse → elle revient tout de suite → **le gardien relisait l'ancien refus**, et
l'enfant restait dehors alors qu'il avait payé.

Le réflexe — *« vider le cache après l'encaissement »* — ne marche pas, et c'est
ça qu'il faut retenir :

> **Le cache qui ment vit sur le téléphone du GARDIEN ; l'encaissement se fait
> sur celui de la CAISSE.** Aucun geste de la caissière n'atteint l'appareil du
> portail. Une invalidation locale ne répare que les gestes faits au même
> endroit.

Le remède est donc dans la nature de ce qu'on garde : **on ne met plus un refus
en cache du tout.** Un refus se redemande à chaque scan — un aller-retour de
plus pour l'enfant qui est déjà arrêté devant la grille, jamais pour la file qui
avance. Les décisions favorables, elles, se gardent.

### Deux écrans qui répondent à la même question, encore

**Même audit, point 6.** Le portail passe par `get_student_pickup_context` :
actif **ET** approuvé **ET** dans ses dates. L'écran de consultation du gardien,
celui de la Direction et celui du parent relisaient `DB.aps` avec le seul
`active !== false`. **Une accréditation expirée y paraissait autorisée** — dans
l'écran même où le gardien vient vérifier avant de laisser partir un enfant.

`_apsValides` répond seul, et son symétrique `_apsHorsJeu` montre les autres
**avec leur raison**. Les cacher aurait fait croire à une fiche vide, alors
qu'il y a une date à renouveler.

### Une promesse suivie d'un refus est pire qu'un bouton absent

**Même audit, point 7.** L'espace Parent annonçait « Vous pouvez ajouter jusqu'à
3 tutelles » et offrait « ➕ Ajouter ». `openTutelleForm` refusait ensuite le
parent, et le serveur aussi. Le parent croyait avoir fait le nécessaire — et le
jour où quelqu'un se présente au portail, la personne qu'il pensait avoir
enregistrée n'existe nulle part.

On dit la règle **avant**, et on donne le geste qui marche : passer au bureau
avec la personne et sa pièce.

`tools/recette-scanner-fermeture.mjs` tient 27 points sur ces quatre-là ;
`--preuve` réinjecte les **quatre** défauts d'origine et vérifie qu'ils sont
revus **nommément**. `tools/recette-cartes.mjs` est passée à 53 points et a
changé de camp : elle gardait un registre tenu dans le navigateur, elle garde
maintenant le fait qu'il n'en tient plus aucun.

**Et une faute de harnais qui vaut d'être notée :** un `const` d'un bloc extrait
restait enfermé dans la portée de son `new Function`, invisible au bloc suivant.
Le défaut ne se déclenchait **que** quand le cache était non vide — donc
uniquement en `--preuve`. Un harnais qui ne casse que dans un sens est un
harnais qu'on croit bon.

### La fraîcheur et l'attente sont deux problèmes, pas un curseur

**11 août 2026.** Loms : *« l'application prend du temps à l'ouverture ».*
Mesuré, et trois stratégies s'étaient déjà succédé au même endroit — chacune
corrigeant la précédente **en cassant autre chose** :

| | |
|---|---|
| **1. Stale-While-Revalidate** | le cache d'abord, mise à jour silencieuse. À chaque publication, l'école voyait **l'ancienne interface au premier chargement**. Loms disait que ses corrections n'étaient pas en ligne — c'était le téléphone qui lui resservait la veille |
| **2. Network-First** | la fraîcheur revient, et l'application reste **blanche** tant que le réseau n'a pas rendu 2,4 Mo |
| **3. Network-First borné à 4 s** | l'écran blanc est borné, mais **les 4 secondes s'écoulent en entier à chaque ouverture** sur un réseau de Kinshasa — pendant qu'une version utilisable dormait dans le cache |

Le tort commun aux trois : traiter la fraîcheur et l'attente comme **un seul
curseur**, alors que ce sont deux problèmes qui se règlent séparément.

> **L'attente se règle en servant le cache IMMÉDIATEMENT.** La fraîcheur ne se
> règle pas en faisant attendre quelqu'un : elle se règle en allant chercher la
> nouvelle version DERRIÈRE, et **en le disant** quand elle est là.

Le défaut du n° 1 n'était donc pas de servir le cache — c'était de **se taire**.
Une mise à jour silencieuse qui arrive au démarrage suivant est un échec
silencieux, celui-là même que tous nos audits traquent. L'écran propose
désormais « Nouvelle version — Recharger », et **ne recharge jamais tout seul** :
quelqu'un peut être en train de scanner au portail.

Trois autres causes mesurées le même jour :

1. **Six bibliothèques extérieures chargées sans `defer`.** L'analyse du
   document s'arrêtait à chaque balise, le temps d'un aller-retour CDN, **avant
   que la première ligne de SchoolSafe soit lue**. Toutes vérifiaient déjà leur
   propre présence (`typeof html2pdf`, `window.QRCode`…) : `defer` ne change
   rien à ce qui marche et retire l'attente.
2. **JSZip téléchargée à chaque démarrage — zéro appel dans tout le fichier.**
   La bonne question n'est pas « est-elle chargée ? » mais « quelqu'un
   l'appelle-t-il ? ».
3. **Un commentaire annonçait un splash « auto après 1.5s » qu'aucune minuterie
   n'a jamais fait.** Un commentaire qui décrit un comportement absent envoie
   chercher au mauvais endroit le jour où l'on cherche pourquoi c'est lent.

`tools/audit-demarrage.mjs` tient les 13 points et **déclare ce qu'il ne sait
pas voir** : le poids réel des CDN, et le temps d'ouverture sur un vrai
téléphone. Seule une mesure sur l'appareil de l'école tranchera.

### Un ministère est un réglage, jamais une constante

**Même jour, sur les documents.** Un document scolaire congolais se lit de haut
en bas comme une **chaîne de responsabilité** — l'administration qui le reçoit
la remonte pour savoir à qui s'adresser. Ce fichier la décrit depuis le début.

Mesuré : sur les **47 producteurs de documents, ZÉRO** ne portait « RÉPUBLIQUE »,
« Province éducationnelle », « Sous-division » ou le code SERNIE. Trois
seulement nommaient un ministère — **et c'était le mauvais**, écrit en dur :
`Ministère de l'EPSP`, `Ministère de l'ESU`. L'EPSP a été remplacé par le
Ministère de l'Éducation Nationale et Nouvelle Citoyenneté.

> **Une liste ENAFEP transmise au ministère en nommant un ministère disparu se
> fait refuser au guichet — et personne dans l'école ne peut savoir pourquoi.**

Ce fichier disait déjà *« il doit être un réglage et non une constante — il
changera encore »*. La leçon était écrite et n'avait pas été exécutée : **une
règle qu'on lit et qu'on n'applique pas ne protège de rien.**

Quatre réglages sont donc apparus — ministère, province éducationnelle,
sous-division, code école — et `_enteteOfficiel()` les porte, une fois, pour
tous. Deux conséquences à retenir :

1. **`sc.sub` était LU quinze fois et écrit nulle part** : le champ mort exact
   que nos audits cherchent. Il a maintenant sa porte d'entrée.
2. **Deux mentions du « Ministère de l'ESU » restaient dans du TEXTE D'ÉCRAN.**
   Je ne connais pas le nom qui le remplace : j'ai retiré le faux **sans le
   remplacer par un autre faux**. Ne rien afficher vaut mieux qu'afficher faux.

Et la faute symétrique, évitée volontairement : **on n'impose pas la chaîne
ministérielle aux 44 autres documents.** Un reçu de cantine ne s'adresse à
aucune administration. C'est un choix, et l'outil l'écrit dans sa sortie.

**Un assistant partagé échappe aux reprises — y compris à celles des audits.**
En déplaçant l'emblème DANS `_enteteOfficiel()`, `audit-logo` et
`audit-signature` ont déclaré « sans emblème » trois documents qui en portaient
un. Il a fallu leur apprendre le nom du nouvel assistant. Les deux savent
toujours dire non — vérifié par leur `--preuve`.

### Dix feuilles de style pour une seule caisse

**11 août 2026.** Loms : *« que tous les documents qui proviennent de cette
partie prennent le même design — harmoniser. »* La référence est le reçu dessiné
par ChatGPT : carte blanche arrondie, bandeau gris bleuté portant l'emblème,
badge de titre en capitales espacées, cartouche de montant, cachet vert.

Il y avait **dix feuilles écrites à la main**, une par document. Le journal, la
balance, le grand livre, le bilan, l'état financier et les deux fiches de paie
avaient chacun leur en-tête, leurs couleurs de tableau, leur taille de titre.

> **Deux papiers sortis de la même caisse le même jour ne se ressemblaient pas
> — et une famille qui reçoit deux documents d'aspect différent doute des deux.**

C'est la leçon des neuf copies du classement, appliquée au dessin : quand dix
endroits répondent à la même question, ils **appellent le même code**. Une
feuille recopiée diverge exactement comme une formule recopiée — sauf que la
divergence se voit sur le papier, chez la famille.

`_CSS_DOC` couvre l'**union des classes que ces documents employaient déjà** :
leur balisage n'a pas eu à être réécrit, seule leur feuille change. C'est ce qui
rend une reprise sûre sur dix documents d'un coup. `_COMPTA_CSS` en dérive au
lieu d'en écrire une autre, et n'ajoute que ce qui est propre au SYSCOHADA.

Deux détails qui ne se voient qu'à l'impression, et qui sont dans la feuille
commune : `thead{display:table-header-group}` — sans quoi une colonne de comptes
devient illisible dès la deuxième page — et la barre d'action qui **ne s'imprime
jamais**, parce qu'elle n'appartient pas au document.

### `accept="image/*"` ouvre un commentaire CSS

**Trouvé le même jour, et c'est un piège d'outil.** Nos audits retirent les
commentaires avant de chercher — sinon la note qui documente un retrait fait
échouer le contrôle qui le vérifie. Le nettoyeur retirait `/* … */` **où qu'il
se trouve**.

Or `accept="image/*"` est un attribut HTML parfaitement normal. Son `/*` ouvre
un faux commentaire que le premier `*/` venu referme. Mesuré : **351 Ko avalés
d'un coup**, dont la seule ligne qui emploie `jsQR` — et l'outil a déclaré
« bibliothèque téléchargée sans être appelée » sur une bibliothèque
parfaitement utilisée.

> **Un nettoyeur qui ne comprend pas le contexte n'omet pas : il INVENTE.**
> C'est la faute la plus coûteuse d'un outil, parce qu'elle envoie corriger du
> code qui n'a rien.

Le `/*` doit être **en début de ligne** — c'est ainsi que les vrais commentaires
s'écrivent ici. Le défaut dormait dans le nettoyeur depuis le début : il a fallu
qu'un `*/` apparaisse plus loin dans le fichier pour qu'il se réveille.

### Un contrôle qui ne couvre qu'un fichier ne protège que ce fichier

**12 août 2026.** ChatGPT a livré la messagerie V2 — `dist/messages-frontend-v2.js`,
445 lignes qui décident du routage Parent → Direction → enseignant → Direction →
Parent. Le contrat est bon et il est branché proprement, `defer`, juste avant le
vrai `</body>`.

**Mais nos vingt audits ne lisent que `dist/index.html`.** Ce fichier serait donc
arrivé chez l'école sans qu'aucun outil ne l'ait regardé — ni sa portée, ni ses
gardes de rôle, ni ses écritures. Le filet existait, le poisson est passé à côté.

Deux défauts trouvés en le lisant, et tous deux sont des leçons **déjà écrites
ici**, reproduites dans un fichier voisin :

1. **« Message envoyé » annoncé sans preuve.** `pushSync` met en file, il ne
   confirme rien. Hors ligne, le parent lisait *« Message envoyé à la Direction »*
   alors que rien n'était parti — et il attendait une réponse qui ne pouvait pas
   venir. Les quatre annonces disent maintenant ce qui est vrai, et **changent de
   ton** : un envoi différé n'est pas un succès.
2. **Le nouveau script était figé en cache pour toujours.** Le Cache-First
   générique du service worker ne réinterroge jamais le réseau : une correction
   n'aurait atteint personne tant que son `?v=` n'était pas changé à la main.
   C'est exactement la panne qu'on venait de réparer pour `index.html`, prête à
   se reproduire à côté. Tout script de production de l'école suit désormais la
   même règle — servi du cache tout de suite, revérifié derrière, et **on le dit**.

> **Quand on répare une classe de panne, il faut chercher où elle vit ailleurs.**
> Une règle écrite pour un fichier ne se propage pas toute seule au fichier
> d'à côté.

`audit-demarrage` vérifie désormais **tout `dist/*.js`** : il se parse, il se
charge sans bloquer, il n'est pas figé. Et il écrit dans sa sortie ce qu'il ne
sait toujours pas voir — **la logique de ces fichiers n'est lue par aucun outil.**

**Et une preuve qui s'est périmée en silence, le même jour.** En faisant suivre
la même règle aux scripts, le motif saboté par `--preuve` est apparu **deux
fois** dans le service worker. Le `replace` n'en corrompait qu'une, le contrôle
trouvait encore l'autre, et la preuve se déclarait tenue alors qu'elle ne gardait
plus rien. `replaceAll`. **Une preuve qui ne suit pas le code qu'elle garde se
périme sans rien dire** — c'est la troisième fois que ce dépôt le note.

### Un incident d'affichage ne doit jamais coûter ce que le serveur a déjà fait

**12 août 2026.** Loms : *« l'invitation avec code sur WhatsApp, ça ne
fonctionne pas ».*

Le parcours était juste, et le défaut n'était pas dans le parcours : il était
dans ce qui l'entoure. Au moment où la carte s'affiche, **le serveur a déjà
agi** — le code est posé comme mot de passe Auth, l'accès précédent est
invalidé, le délai d'une minute court, et **le code n'est rendu qu'une fois** :
il n'est enregistré nulle part, ni ici, ni là-bas.

Or toute la chaîne d'affichage était appelée **sans un seul `catch`** :
`_dessinerCarteAcces` (canvas 1120 × 1400, deux images, `toBlob`),
`createObjectURL`, puis la modale. Et `_envoyerLienWhatsApp` avait
`try { … } finally` — **sans `catch`**.

Un seul incident — canvas contaminé, mémoire courte sur un téléphone d'entrée
de gamme, `toBlob` qui lève — et :

| | |
|---|---|
| l'écran | ne montrait **rien** |
| la Direction | rappuyait → `TOO_SOON` |
| la personne | ne pouvait plus entrer avec son ancien accès, et n'avait pas le nouveau |

> **Ce qui est irréversible passe avant ce qui est décoratif.** La carte est un
> confort ; le code est la seule chose qui compte. Quand un geste a déjà changé
> l'état du serveur, plus rien de ce qui l'AFFICHE ne doit pouvoir le perdre.

Trois filets, du plus intérieur au plus extérieur : le dessin ne jette plus
jamais, l'affichage de la carte non plus, et si tout lâche un dernier recours
montre le code **en clair, sans dessiner ni charger la moindre image** — pour ne
pas échouer à son tour. Et le repli dit ce qu'il faut savoir : *« notez le code
avant de fermer : il ne sera plus jamais réaffiché »*.

**La leçon de méthode :** on cherche ce défaut en se demandant, à chaque
`await` qui suit une écriture serveur, *« si la ligne suivante jette, qu'est-ce
qui est déjà parti et ne reviendra pas ? »*

`tools/recette-acces-whatsapp.mjs` tient 18 points en cassant vraiment le
canvas ; `--preuve` retire les trois filets et **revoit le code disparaître**.

**Et deux outils qui ont fait leur travail sur moi, le même jour :** en
renommant `_dessinerCarteAcces` en `…Impl`, `audit-logo` a aussitôt déclaré
l'emblème « lu hors d'un document » — un renommage avait fait sortir un document
de sa liste. Et mon propre test a accusé le message d'emporter une donnée
d'enfant : il cherchait `note` dans tout l'écran, et lisait « **Note**z le
code ». **Un test qui se trompe de cible accuse du texte parfaitement sain** —
il visait l'écran, il devait viser le message.

### Quatre outils dans le tableau, zéro dans le filet

**12 août 2026.** Ce fichier présente ses outils dans un tableau, et ce tableau
disait vrai sur ce qu'ils font. Il ne disait rien sur **ce qui les lance**.

Quatre d'entre eux — `audit-mort`, `audit-writes`, `audit-schema`,
`audit-portee-parent` — n'étaient dans **aucune liste**. `npm run audit` ne les
a jamais exécutés une seule fois. Les fonctions exposées sans appelant, les
écritures dont l'échec est invisible, l'écart entre le code et le SQL, ce que le
parent lit sans qu'on le lui charge : quatre questions posées, jamais reposées.

C'est **exactement** la leçon du 4 août, commise ici même :

> **Une règle qu'on lit et qu'on n'exécute pas ne protège de rien.**

Et c'est la même famille que l'enchaînement `&&` qui arrêtait `npm run audit` au
troisième outil : **un filet troué ne se voit pas, il se mesure.** La bonne
question n'est jamais « l'outil existe-t-il ? » mais « **quand a-t-il tourné
pour la dernière fois ?** ».

Les vingt-trois sont passés à vingt-sept. Aucun des quatre ne bloque — ils
informent — mais ils informent désormais quelqu'un.

---

## Les outils

```bash
npm install          # acorn et acorn-walk, rien d'autre
npm run audit        # tout d'un coup
```

| | |
|---|---|
| `audit-portee.mjs` | un nom lu hors de sa portée, ou avant sa déclaration — **les pages blanches** |
| `audit-invariant.mjs` | toute table de données lue est-elle déclarée ? |
| `audit-gardes.mjs` | les mutations globales sans contrôle de rôle |
| `audit-mort.mjs` | les fonctions exposées sans appelant |
| `audit-logo.mjs` | l'emblème sur les documents · et son ABSENCE de l'interface |
| `audit-charte.mjs` | gris · blanc · or sur les documents (`--detail`) |
| `audit-contraste-site.mjs` | les 17 couples texte/fond du site, **mesurés** (`--preuve`) |
| `audit-contraste-connexion.mjs` | l'écran de connexion — texte sur **photographie**, pire cas (`--preuve`) |
| `audit-telephone.mjs` | le numéro écrit **exactement** comme le serveur l'écrira (`--preuve`) |
| `audit-signature.mjs` | quel document se signe, et lequel ne se signe pas (`--preuve`) |
| `audits.mjs` | **les lance tous**, même quand l'un échoue — `npm run audit` |
| `verif-coherence.mjs` | la chaîne de calcul, **exécutée** |
| `audit-writes.mjs` | les écritures dont l'échec est invisible |
| `audit-schema.mjs` | code ↔ SQL — lit `supabase/migrations`, et **dit ce qu'il ne peut pas vérifier** |
| `audit-portee-parent.mjs` | de quelles données un rôle a-t-il réellement besoin |
| `recette-contact.mjs` | corriger un téléphone ou une adresse, exécuté (`--preuve`) |
| `recette-scanner-physique.mjs` | scanner physique ≠ accès QR Caisse, et **un refus n'est pas un silence** (`--preuve`) |
| `recette-scanner-fermeture.mjs` | le cache d'accès, la vérité serveur des personnes autorisées, la promesse faite au parent (`--preuve`) |
| `audit-demarrage.mjs` | ce qui retarde l'ouverture — scripts bloquants, cache, **et ce qu'il ne sait pas voir** (`--preuve`) |
| `audit-entete.mjs` | la chaîne de responsabilité des documents · **un ministère est un réglage** · le dessin unique de Finance et RH (`--preuve`) |
| `recette-messages-v2.mjs` | le routage Parent → Direction → enseignant · **et l'honnêteté de l'envoi** |
| `recette-recu-v2.mjs` | le reçu de paiement V2, prêt à brancher |
| `recette-acces-whatsapp.mjs` | l'invitation par code WhatsApp — **le code survit à tout incident d'affichage** (`--preuve`) |

**Dans un nouveau dépôt, commencer par les lancer.** Leur sortie *est* la liste
des manques — au lieu d'en discuter.

Trois principes appris en les écrivant :

1. **Un outil doit être éprouvé dans les deux sens.** Il doit dire « incomplet »
   avant et « en place » après. Une vérification qui ne sait dire que oui ne
   vérifie rien.
2. **Il doit déclarer ce qu'il ne sait pas vérifier**, au lieu de se taire. Un
   audit avait un angle mort — une forme d'écriture courante qu'il ignorait en
   entier — et dix manques passaient sans un mot.
3. **La bonne question n'est pas « chaque accès porte-t-il sa garde ? » mais
   « la valeur peut-elle seulement être autre chose ? »** Un audit signalait 498
   accès « non gardés » ; aucun n'était un défaut, et poser 498 gardes n'aurait
   rien protégé. Il a été supprimé et remplacé par un outil qui vérifie les
   trois conditions dont l'invariant dépend vraiment.

   **La même faute s'est reproduite le 4 août 2026**, en plus petit : le
   contrôle inverse de `audit-logo` listait neuf « fuites » de l'emblème vers
   l'interface. Vérifiées une par une, **aucune n'était un défaut**. Réécrit
   autour de la seule condition qui compte — *toute affectation de
   `SCHOOL_LOGO` vient-elle des réglages, d'un téléversement, ou de `null` ?*
   Trois lignes au lieu de neuf reproches. Une leçon écrite ne se retient pas
   toute seule : il faut la relire quand on écrit un outil.

4. **Un audit qui se trompe de source n'en trouve pas moins — il en invente.**
   `audit-schema` cherchait six fichiers SQL nommés en dur : ceux de l'AUTRE
   installation, absents d'ici. Il comparait donc 306 écritures à un schéma
   **vide** et annonçait « 49 problèmes » — quarante-neuf tables parfaitement
   normales, déclarées introuvables. On aurait pu passer une journée à
   « réparer » le code contre un néant.

   Réparé le 4 août 2026 : il lit `supabase/migrations`, dans l'ordre
   chronologique. Et il a fallu lui apprendre la distinction qui décide de
   tout — **une table n'est vérifiable colonne par colonne que si le dépôt
   porte son `CREATE TABLE`.** Trois colonnes ajoutées par un `ALTER` à une
   table créée ailleurs ne disent rien des trente autres : les prendre pour
   le schéma complet ferait déclarer « absentes » toutes celles qu'on ne voit
   pas. La même faute, dans l'autre sens.

   D'où **trois verdicts et non deux** : des écarts trouvés · rien à comparer ·
   conforme. Aujourd'hui c'est le deuxième — 49 tables sur 49 hors de portée,
   parce que le schéma de fond vit dans le projet Supabase et n'a jamais été
   déposé ici. L'outil le dit en toutes lettres et **sort en échec** : un « ✓ »
   posé sur un angle mort serait le pire des mensonges.

5. **Un enchaînement `&&` d'audits est un filet troué.** `npm run audit`
   s'arrêtait au troisième outil, en panne depuis une reprise du harnais —
   **donc l'emblème, la charte, les signatures et les contrastes n'étaient plus
   vérifiés du tout**, sans que rien ne le dise. C'est la faute que ces outils
   cherchent, commise par les outils eux-mêmes : un échec silencieux.
   `tools/audits.mjs` les lance tous et dit lequel passe.

6. **Un « ✓ » posé sur ce qu'un outil ne peut pas voir est un mensonge, pas
   une omission.** `aucun-montant.mjs` annonçait *« aucun montant nulle
   part »* sur le site public. Il disait vrai sur ce qu'il regardait : il ne
   lit que du texte. Or `inscription.html` publiait les **quatre billets de
   vacances en image**, en pleine résolution et ouvrables au clic — minerval,
   trois tranches, cantine au mois, amortissement jouets, uniforme. La
   décision de Loms était contredite sur la page la plus visitée du site, et
   l'outil chargé de la tenir signait en bas.

   Trois choses en sortent, et elles valent pour tout outil :

   - **La frontière de ce qu'un outil regarde doit être écrite dans sa
     sortie**, à chaque passage, pas dans un commentaire que personne
     n'ouvre. Il annonce désormais les 127 images qu'il ne sait pas lire.
   - **Un fichier posé dans le dépôt est publié même si aucune page n'y
     renvoie** — GitHub Pages sert l'adresse. Retirer le lien ne retire
     rien ; il faut retirer le fichier.
   - **La preuve doit couvrir le nouveau trou, pas seulement l'ancien.**
     `--preuve` réinjecte le montant dans une page **et** un billet dans le
     dépôt. Une preuve qui ne suit pas l'outil qu'elle garde se périme en
     silence.

`verif-coherence` mérite un mot. Il charge les vraies fonctions du fichier dans
Node avec un navigateur en carton, leur donne un jeu d'essai dont on connaît la
réponse à la main, et **confronte les chemins de calcul entre eux**. Il est né
d'une phrase :

> « Imagine qu'un parent voie les cotes de devoirs de son enfant et les cotes
> des interros, et qu'à la fin son enfant ne réussisse pas. »

Tout le reste peut être juste : si les cotes affichées ne font pas la moyenne
affichée, la famille cesse d'y croire.

**Attention au harnais** : si le stub de `document.createElement` ne sait pas
échapper, la fonction d'échappement rend une chaîne vide et **tout texte échappé
disparaît du test**. Deux diagnostics faux sont venus de là. Le stub doit
implémenter `textContent` → `innerHTML`.

---

## Ce qui n'est PAS ici, et pourquoi

**L'identifiant du projet Supabase, les clés, les migrations SQL et les
politiques d'accès** de l'autre installation. Non par oubli : cette couche
appartient à ChatGPT, et un identifiant de projet recopié dans un dépôt est une
information qui n'y a rien à faire.

Ce qui est ici, en revanche, ce sont **les symptômes visibles depuis
l'interface** — voir `notes/la-base-vue-du-frontend.md`. Ils servent à
diagnostiquer, puis à décrire proprement le problème dans une issue.

**Le sel des mots de passe et la clé du cache chiffré** n'ont pas été repris.
Ils ne comptent que si les comptes et les données hors ligne existants doivent
continuer de fonctionner. Si c'est le cas, ce sont deux chaînes à reprendre à
l'identique : les changer rendrait **tout compte inaccessible et toute donnée
locale illisible**. À demander à Loms, pas à deviner.

---

## Travailler à deux agents sur un fichier unique

C'est le vrai risque, avant toute question de connaissances. Deux agents qui
écrivent dans le même gros fichier produisent des conflits qui ne se résolvent
pas à la main : on perd du travail sans s'en apercevoir.

La répartition officielle — base et sécurité à ChatGPT, interface et bugs à
Claude — limite déjà le recouvrement, parce que ces couches vivent dans des
régions différentes du code. Restent quatre règles :

1. **Une branche courte par tâche, fusionnée aussitôt.** Jamais deux tâches
   ouvertes en même temps sur le même fichier.
2. **On ne fusionne qu'après avoir lancé les audits.** C'est le filet — ils
   trouvent en quelques secondes une page blanche ou deux écrans qui se
   contredisent. Sans lui, le travail parallèle est une prise de risque.
3. **Un seul agent à la fois pousse.** L'autre rebase.
4. **Ne jamais inventer un champ.** Si le contrat API de ChatGPT ne fournit pas
   une donnée, on ne la déduit pas côté navigateur : on la demande. C'est la
   règle qui empêche les deux moitiés de diverger.

`notes/collaboration.md` détaille le format de compte rendu attendu après
chaque livraison. `notes/deja-resolu.md` liste ce que l'autre installation a
déjà tranché et qui peut être repris tel quel.

Et une règle qui vaut pour les deux agents : **après chaque correction, mettre
ce fichier à jour.** C'est ce qui empêche de réapprendre.
