# La préinscription, la tutelle et les trois personnes autorisées

**Analyse demandée par Loms le 4 août 2026. Aucun code écrit.**

Son idée : la fiche d'identification sert à enregistrer **le tuteur principal
et les trois personnes qu'il désigne**. Direction 1 reçoit les préinscriptions,
les valide, et à la validation l'enfant, son parent et sa tutelle entrent d'un
coup dans l'application.

---

## 1. Ce que je pense d'abord — l'idée n'invente rien, elle raccorde

**Tout ce qu'elle décrit existe déjà dans l'application.** Ce n'est pas une
fonction à construire : c'est une porte d'entrée qui manque à une fonction
construite.

La table `aps` — les personnes autorisées — porte déjà :

```
id · sid · name · relation · photo · phone · active
approval_status · valid_until
```

Et le portail s'en sert déjà :

- le Gardien choisit l'accompagnant à la sortie (`_escorteChoix`) ;
- trois cas sont prévus : `parent`, `autorisee`, `seul` ;
- **le serveur refuse** un accompagnant non autorisé — `invalid_escort` ;
- `get_scanner_aps` alimente l'écran du Gardien ;
- l'espace parent a déjà un écran « Personnes autorisées » (`R.authorized`),
  et il **relance déjà** les familles qui n'en ont déclaré aucune.

**Le trou est en amont, pas en aval.** Aujourd'hui, la liste ne se remplit que
si un parent y pense, après coup, depuis son téléphone. Résultat prévisible :
elle reste vide, et le Gardien n'a rien à vérifier.

> **L'idée de Loms met le remplissage là où il ne peut pas être oublié :
> au moment de l'inscription, quand la famille est devant vous.**

C'est le bon endroit, et c'est pour cela que je pense que l'idée est juste.

---

## 2. Le seul point où je ne suis pas d'accord — la photo

Loms écrit : *« si le fichier d'identification était rempli avec photo, il
passe directement dans l'application »*.

**Je déconseille de faire téléverser les photos depuis le site public.**

Trois raisons, dans l'ordre d'importance :

1. **Ce sont des photos d'enfants et de pièces d'adultes.** Un formulaire
   public accepte l'envoi de **n'importe qui**, sans compte, sans vérification.
   Rien ne dit que celui qui téléverse la photo d'un enfant est son parent.
   C'est la donnée la plus sensible du système, déposée par la porte la moins
   contrôlée.
2. **Un stockage ouvert se remplit.** Une écriture publique sans frein, c'est
   des milliers de fichiers en une nuit — et la facture avec.
3. **Une photo de WhatsApp ne sert pas au portail.** Floue, mal cadrée, prise
   de loin : le Gardien doit reconnaître un visage en trois secondes, sous le
   soleil, sur un téléphone. Ce n'est pas la même photo.

### Ce que je propose à la place

**La préinscription porte les noms, les liens de parenté et les téléphones.
Pas les photos.**

Les photos se prennent **à l'école, au moment de la validation** — c'est-à-dire
au moment où la famille est déjà là pour payer. Ça ne coûte pas une minute de
plus, et ça donne :

- une photo **utilisable** au portail, prise dans les mêmes conditions ;
- une identité **vérifiée** : la personne est devant vous ;
- **aucune photo d'enfant sur un point d'entrée public** ;
- un site qui reste **léger**, ce que Loms demande par ailleurs.

Si vous voulez malgré tout des photos avant la venue, la forme honnête est :
**après la validation**, la Direction envoie un lien à usage unique. La porte
n'est plus publique — elle est ouverte à une famille précise, pour une durée
précise.

---

## 3. Le point de sécurité qui décide de tout

`approval_status` existe déjà dans la table. Ce n'est pas un hasard : ChatGPT a
prévu qu'une personne autorisée doit être **approuvée**.

> **Une personne déclarée depuis le site entre en `pending`. Jamais en
> `approved`.**
>
> Le parent ne doit **pas** pouvoir approuver sa propre liste. Sinon n'importe
> qui se déclare « oncle » et repart avec un enfant.

C'est le cœur de l'affaire, et c'est aussi ce qui donne son sens à la
validation par Direction 1 : elle n'est pas une formalité administrative, c'est
**l'acte qui autorise trois adultes à prendre un enfant**.

Et c'est pour cela que **le papier signé compte plus que le formulaire en
ligne** : désigner trois personnes qui peuvent emmener son enfant est une
délégation. La fiche imprimée porte déjà les trois colonnes de signature —
parent, secrétariat, Direction. **C'est elle qui fait foi**, le formulaire ne
fait que la préparer.

---

## 4. Ce que la validation doit faire, en une seule action

Direction 1 ouvre une demande, vérifie, et clique **une fois**. L'application
crée alors, ensemble :

```
   l'élève            nom, sexe, naissance, classe, adresse
   le parent          compte parent, téléphone — relié à l'élève
   le tuteur          si différent du parent
   les 3 autorisées   en attente d'approbation, avec leur lien de parenté
   le matricule       attribué ICI, jamais à la préinscription
   les obligations    minerval, tranches, cantine
```

Deux précisions qui comptent :

**Le matricule s'attribue à la validation.** Une préinscription n'est pas un
élève. Numéroter une demande qui sera peut-être refusée, c'est trouer la
numérotation de l'école.

**Un refus se garde.** La demande refusée reste, avec son motif et sa date. Une
famille qui revient trois semaines plus tard ne doit pas repartir de zéro, et
l'école doit pouvoir dire ce qu'elle a refusé.

---

## 5. Ce qui va faire mal en septembre, et qu'il faut prévoir maintenant

**Les doublons.** À 350 élèves, la rentrée produira :

- le même enfant préinscrit deux fois, par le père puis par la mère ;
- un enfant **déjà élève** dont la famille refait une inscription en ligne au
  lieu d'une réinscription ;
- deux enfants d'une même famille inscrits séparément, créant **deux comptes
  parents** pour un seul foyer — et le sélecteur multi-enfants ne les réunit
  plus.

Avant de créer, l'écran de validation doit dire : *« un élève portant ce nom et
cette date de naissance existe déjà »* et *« ce numéro de téléphone est déjà
celui d'un parent »*. Sans cela, on découvre le problème en novembre, quand les
bulletins sortent en double.

**Les fratries.** Sur le jeu d'essai, **62 élèves partagent un parent**. Si la
préinscription crée un parent par enfant, on casse ce qui marche aujourd'hui.

---

## 6. Combien de personnes autorisées — trois, ou plus ?

Loms dit trois. **La table n'impose aucune limite** : c'est donc une question de
formulaire, pas de modèle.

Mon avis : **trois sur la fiche imprimée**, parce qu'une fiche doit tenir sur
une page et que trois couvre la quasi-totalité des familles. Et **pas de
plafond dans l'application**, parce que la Direction doit pouvoir en ajouter une
quatrième en cours d'année sans qu'on lui dise non.

`valid_until` existe déjà : une autorisation peut être **temporaire**. C'est
exactement ce qu'il faut pour la tante qui vient trois semaines pendant que la
mère est en voyage.

---

## 7. Ce que ça demande, et à qui

### ChatGPT — la couche serveur

Il a déjà livré `site_content` et le contrat d'écriture publique du site. Il
reste :

1. **une table de demandes de préinscription** — écriture publique **sans
   lecture publique**, avec un frein contre le remplissage automatique ;
2. **une RPC de validation** qui fait les six créations **dans une seule
   transaction**. Si elle échoue à mi-chemin, on ne veut pas d'un élève sans
   parent, ni d'un parent sans élève ;
3. **la garantie que `approval_status` ne peut pas être écrit à `approved`
   depuis le site** — c'est la garantie qui protège les enfants ;
4. un **contrôle de doublon** côté serveur : nom + date de naissance, et
   téléphone du parent.

### Claude — l'interface

- l'écran **« Demandes de préinscription »** pour Direction 1, avec la
  notification à l'arrivée — le mécanisme existe déjà (`_notifDirection`) ;
- la fiche affichée en entier, les doublons signalés **avant** le bouton ;
- **accepter** en une action, **refuser** avec motif ;
- la prise de photo à la validation, qui alimente `aps` et la photo de l'élève ;
- la préinscription enrichie des trois personnes autorisées — noms, liens,
  téléphones.

### Loms — trois décisions

1. **Les photos : à l'école ou en ligne ?** Mon avis est écrit au §2. C'est
   votre décision, pas la mienne.
2. **Qui valide ?** Direction 1 seule, ou le secrétariat prépare et la
   Direction approuve ? La deuxième est plus réaliste à la rentrée.
3. **Une préinscription non validée expire-t-elle ?** Une demande de septembre
   encore ouverte en janvier n'a plus de sens.

---

## 8. En une phrase

> **L'idée est juste, et elle coûte moins cher qu'elle n'en a l'air — parce que
> le portail sait déjà vérifier un accompagnant. Ce qui manquait, c'est le
> moment où la famille le déclare.**
>
> Le seul point que je changerais : **les photos se prennent à l'école, pas sur
> le site.** Le reste, je le construis tel que vous le décrivez.
