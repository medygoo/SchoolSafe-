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
écriture le renseigne » : **six reçus ne peuvent pas nommer leur auteur**, parce
que `DB.payments` passe à `paid:true` par un `patch` qui ne porte ni qui ni
quand. Champ demandé à ChatGPT — écrit côté serveur, car un auteur que le
navigateur choisirait ne vaudrait rien.

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
| `audit-contraste-site.mjs` | les 17 couples texte/fond du site, **mesurés** (`--preuve`) |
| `audit-contraste-connexion.mjs` | l'écran de connexion — texte sur **photographie**, pire cas (`--preuve`) |
| `audit-signature.mjs` | quel document se signe, et lequel ne se signe pas (`--preuve`) |
| `audits.mjs` | **les lance tous**, même quand l'un échoue — `npm run audit` |
| `verif-coherence.mjs` | la chaîne de calcul, **exécutée** |
| `audit-writes.mjs` | les écritures dont l'échec est invisible |
| `audit-schema.mjs` | code ↔ SQL — lit `supabase/migrations`, et **dit ce qu'il ne peut pas vérifier** |
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
