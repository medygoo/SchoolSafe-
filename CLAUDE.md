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

### Consigne OBLIGATOIRE de Loms — le canal avant tout

1. **Brancher la communication est la PREMIÈRE chose à faire**, avant de coder,
   avant d'analyser, avant de livrer. On lit ce que l'autre a déposé sur GitHub,
   on y dépose ce qu'on a fait, on y pose ses questions. Toujours.
2. **Ce que ChatGPT a fait a été demandé par Loms.** On ne le conteste pas, on ne
   l'audite pas pour le remettre en cause, on ne demande pas pourquoi. **On
   continue à partir de là.** On ne signale qu'une chose : ce qui empêche
   concrètement d'avancer — un champ manquant, un identifiant qui ne correspond
   pas. Jamais un désaccord d'opinion.
3. **Réponses courtes et claires à Loms.** Ce qui est fait, ce qui bloque, ce
   qu'on attend. Le détail va dans `docs/`, pas dans la réponse.

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

**L'emblème de l'école n'entre PAS dans l'interface.** Erreur commise puis
corrigée : donner une valeur par défaut au logo de l'école l'a fait paraître
dans la barre latérale, l'écran de connexion et « À propos » dès le premier
lancement — l'application se mettait à porter l'école. Le logo de l'école est
le repli **des documents**. L'interface porte celui du logiciel, et n'affiche
l'emblème de l'école que si la Direction l'a elle-même téléversé.

Symétriquement : **les documents imprimés représentent l'école**, donc ils en
portent les couleurs — jamais celles de l'interface.

---

## L'école

**Complexe Scolaire Le Sage / The Wise School International**
Kabambare 4367, Quartier Bon Marché, Commune de Barumbu — Kinshasa, RDC

Trois variantes de l'adresse avaient coexisté, dont aucune n'était la bonne.
Celle-ci l'est.

L'année scolaire congolaise court de **septembre à août**.

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

### L'argent

Toujours un lecteur de montant dédié, **jamais `parseFloat`** :
`parseFloat('12,50')` vaut **12** — la virgule est le séparateur décimal ici.
Trente et une saisies d'argent étaient concernées.

Un lecteur correct accepte « 12,50 », « 1 200 », « 1.200,50 » et **refuse**
« 1O0 » (la lettre O). Refuser vaut mieux qu'interpréter.

Et une seule porte d'entrée pour l'argent : reçu, recette et écriture comptable
partent ensemble, ou rien ne part. Un encaissement qui contournait cette porte
n'apparaissait dans aucun total.

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
| `verif-coherence.mjs` | la chaîne de calcul, **exécutée** |
| `audit-writes.mjs` | les écritures dont l'échec est invisible |
| `audit-schema.mjs` | code ↔ SQL — **ne s'applique que s'il y a une base** |
| `audit-portee-parent.mjs` | de quelles données un rôle a-t-il réellement besoin |

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
