# Ce qui est déjà tranché — et les pièges qui reviendront

L'autre installation a rencontré la plupart des sujets de la mission A1–A12. Ce
document dit **ce qui peut être repris tel quel** et surtout **ce qui a cassé**,
pour ne pas le recasser.

Rien ici n'est une décision : c'est de l'expérience. Le contrat API de ChatGPT
prime toujours.

---

## A1 · Séparer Devoirs et Interrogations dans l'espace Parent

**Déjà fait, et il y a un piège.** Les deux vivent dans la même table, séparés
par une catégorie (`devoir` · `interro` · `examen`). Trois sections distinctes,
trois compteurs.

⚠️ **Le piège qui a rendu la page blanche :** le rendu d'une interrogation
affichait la note quand la Direction autorise les corrections. Le drapeau
d'autorisation était déclaré **dans la boucle sur les enfants**, la fonction de
rendu **au-dessus** — donc hors de portée.

```
ReferenceError: canSeeCorr is not defined
```

Le rendu s'interrompait, **page blanche**, dès qu'une interrogation existait. Le
parent en concluait qu'il ne recevait rien. Le contrôle de syntaxe ne voit pas
cette faute : elle est du JavaScript valide.

→ Passer le drapeau **en paramètre**. Et lancer `tools/audit-portee.mjs`.

---

## A2 · La carte Frais scolaires à côté des deux autres

⚠️ **Le second piège de la page blanche, sur le tableau de bord du parent :** la
liste des classes des enfants était lue **dix lignes avant** son `const`. Zone
morte temporelle. Tant qu'aucun devoir n'existait, la fonction de filtrage ne
s'exécutait pas et rien ne paraissait ; **au premier devoir publié**, l'accueil
du parent devenait blanc.

C'est-à-dire : l'application cassait à l'instant précis où l'école avait quelque
chose à dire.

→ Déclarer avant le premier usage. `audit-portee.mjs` détecte aussi ce cas.

---

## A3 · La page Parent « Frais scolaires »

**Une page équivalente existe** (résumé, échéancier par type de frais, barre de
progression, historique des versements, bouton reçu par ligne). Réutilisable
comme maquette.

⚠️ **Trois défauts trouvés dedans, tous à éviter :**

1. **La cible du montant** venait d'un montant par défaut figé au moment de
   l'amorçage, pas du barème réellement en vigueur. La page annonçait à la
   famille un montant que la Caisse ne pratiquait pas.
2. **Un versement encaissé hors des types de frais actifs n'était listé nulle
   part**, alors que le total le comptait. La famille lisait « 300 versés » et
   n'en retrouvait que 200 en additionnant les lignes. *Un reçu qu'on ne
   retrouve pas est un reçu qu'on croit perdu.* → prévoir un bloc « Autres
   versements ».
3. **Le solde était recalculé côté navigateur** avec une formule différente de
   celle de la Caisse. Deux écrans, deux réponses, devant la même famille.
   → Avec le nouveau contrat, le serveur répond ; l'interface affiche.

---

## A4 · Le sélecteur multi-enfants

**Existe.** Un enfant sélectionné, mémorisé, avec vérification que l'enfant
appartient bien au parent connecté à chaque rendu — le menu ne propose que ses
enfants, mais il est reconstruit à chaque fois : on revérifie le lien plutôt que
de faire confiance au DOM.

⚠️ Le filtre parent-enfant doit être **identique partout**. Vingt écrans le
posaient ; il suffit d'un seul qui l'oublie.

---

## A5 · L'écran Caisse de contrôle par QR ou matricule

**Existe pour l'entrée/sortie**, à adapter au contrôle financier.

⚠️ **Le défaut le plus grave rencontré, et il concerne directement ce module :**
un passage **REFUSÉ** au portail porte quand même le type « entrée » dans le
journal. Six chemins le comptaient comme une arrivée. Conséquences mesurées :

- la validation des présences enregistrait l'enfant **présent pour l'année** et
  ne créait pas sa ligne d'absence ;
- la Direction n'était pas alertée ;
- la famille n'était pas prévenue ;
- et l'espace parent annonçait « Présent » à qui venait d'être **renvoyé du
  portail**.

L'enfant avait été renvoyé à la maison, et l'application affirmait le contraire
à tout le monde.

→ **Un refus n'est pas un passage.** Une fonction unique répond à « qui est
entré », et elle exclut les refus. À rejouer tel quel pour le contrôle des
frais : un contrôle refusé n'est pas un contrôle réussi.

---

## A6 · L'écran Gardien minimal

**Existe.** Photo, identité, classe, instruction.

⚠️ Le Gardien doit voir **la photo de l'accompagnant** pour la confronter à qui
se présente — c'est la seule photo qui doive circuler. Les autres restent sur
l'appareil de leur propriétaire.

⚠️ Et un piège d'échappement : un nom entre guillemets dans un attribut
`onclick` cassait le bouton d'accompagnant, qui **n'a jamais fonctionné**. Les
noms contiennent des apostrophes (`N'Goma`) — la fonction d'échappement HTML
courante n'échappe pas les guillemets.

---

## A7 · Masquer le scanner financier à Direction 2 et Enseignant

⚠️ **Un contrôle dans le rendu n'est PAS une sécurité.** Masquer un bouton ne
protège rien : la fonction reste appelable. Toute fonction exposée globalement
qui écrit ou lit une donnée sensible doit **vérifier le rôle elle-même**.

Un audit a trouvé une vingtaine de mutations sans garde, dont trois sur les
présences et deux qui manipulaient de l'argent.

→ `tools/audit-gardes.mjs` les liste.

---

## A8 · Les six états visuels

**Le système existe** pour les scans (résultat coloré plein écran).

⚠️ **Un état visuel se calcule à partir de ce qui est AFFICHÉ, jamais de ce vers
quoi on pourrait aller.** La barre d'onglets peignait un bouton d'après le mode
de l'onglet vers lequel il *mène* : sur fond clair, trois onglets étaient écrits
en blanc à 55 %. Contraste mesuré **1,07:1** — le texte était là,
mathématiquement illisible.

⚠️ Et le corollaire pour les six couleurs : **une couleur ne doit jamais être la
seule porteuse d'un état.** Chaque état porte aussi un mot. Un orange et un
rouge se confondent au soleil, sur un téléphone bon marché, à travers une vitre
de guérite.

---

## A9 · Erreurs réseau et états hors ligne

**Existe** : file d'attente persistante, opérations mises de côté après échecs
répétés, indicateur d'en-tête.

⚠️ Trois choses qu'il faut à une cadence pour tenir à 250 familles :

1. **Du désaccord.** 250 téléphones ouverts à la sortie des classes repartent
   ensemble à la seconde près, et un intervalle **fixe** conserve indéfiniment
   cet alignement : 250 requêtes dans la même seconde, rien pendant 59. Un écart
   aléatoire de ±25 % les disperse dès le deuxième cycle.
2. **Du recul.** Sans lui, une panne de dix minutes envoie 2 500 requêtes contre
   un serveur déjà en difficulté. Doubler à chaque échec ; remettre à zéro au
   premier succès ; l'ignorer au retour à l'écran, là quelqu'un attend vraiment.
3. **Du silence quand rien ne change.** Reconstruire la page à chaque réception
   fait sauter la position de lecture et referme les menus, toutes les minutes,
   pour rien la plupart du temps. **C'est cela que l'utilisateur appelle
   « instable ».** Une empreinte des données — une somme de longueurs, aucune
   ligne parcourue — suffit à dire si la réception a rapporté quelque chose.

⚠️ Et la règle de sûreté du hors ligne, déjà écrite dans le dossier
d'exécution : **le cache ne convertit jamais un « en retard » en « bloqué ».**
Un blocage vient d'une décision serveur enregistrée et auditée.

---

## A10 · Tests d'interface

⚠️ **Le contrôle de syntaxe ne voit pas une page blanche.** Une faute de portée
est du JavaScript valide ; elle n'existe qu'à l'exécution et interrompt le rendu
de l'écran entier. L'utilisateur ne voit pas d'erreur — il voit une page vide.

Quatre pannes de ce type ont été trouvées, dont **trois n'apparaissaient que
lorsqu'il y avait enfin des données à afficher**. C'est-à-dire : jamais pendant
les essais, toujours en production.

→ `tools/audit-portee.mjs` avant chaque Pull Request.

⚠️ **Les fonctions se testent sans navigateur.** On charge le fichier dans Node
avec un stub de DOM, on donne un jeu d'essai dont on connaît la réponse à la
main, et on confronte les chemins de calcul. C'est ce qui a montré que deux
écrans classaient le même élève 79 et 73.

**Attention au harnais** : si le stub de `createElement` ne sait pas échapper,
la fonction d'échappement rend une chaîne vide et **tout texte échappé disparaît
du test**. Deux diagnostics faux sont venus de là.

---

## A11 · Découper le monolithe

⚠️ **Le fichier unique est ce qui rend le travail à deux agents dangereux.** Le
découpage est donc utile — mais c'est aussi le changement le plus risqué du lot,
parce qu'il touche tout.

Méthode qui a fonctionné pour délimiter des zones sans se tromper : **ne pas se
fier au comptage d'accolades**. Il ment sur les gabarits multilignes — 587 lignes
annoncées pour une fonction qui en fait 130. Prendre deux signaux sûrs et leur
union : un marqueur reconnaissable dans le contenu, et l'intervalle entre la
déclaration d'une fonction et **son propre** appel de sortie.

Et découper **par couche**, pas par écran : les écrans se touchent partout.

---

## A12 · Branches et Pull Requests

Rien à reprendre, sinon : **lancer les audits avant d'ouvrir la PR**, et coller
leur sortie dans la description. C'est une preuve, pas une formalité.

---

## Trois défauts transverses qui reviendront

### Le document vide

Rastériser une page en image pour produire un PDF échoue en silence : selon le
navigateur, la largeur de la fenêtre, le moment où les images arrivent, on
n'obtient pas une erreur mais **du blanc**. Trois réglages ont été corrigés l'un
après l'autre sans rien changer.

**Un document s'imprime, il ne se photographie pas.** Le navigateur rend de
vraies polices, du texte sélectionnable, répète l'en-tête d'un tableau à chaque
page, ne coupe pas une ligne en deux, et propose « Enregistrer au format PDF »
partout. Le fichier pèse dix fois moins.

Et : **un PDF vide ne vient jamais du HTML.** Vérifier d'abord que le contenu
existe avant de soupçonner la mise en page.

### Le champ mort, et son symétrique

**Avant de lire un champ, vérifier qu'une écriture le renseigne.** Des champs
étaient lus par six écrans et écrits nulle part.

**Avant d'en écrire un, vérifier qu'une lecture s'en sert — et qu'elle en
connaît toutes les valeurs.** Un statut d'absence était écrit par l'enseignant ;
aucun écran du parent ne connaissait cette valeur. L'enfant absent depuis le
matin s'affichait « pas encore arrivé » toute la journée.

### L'état de lecture d'un message collectif

Un message adressé à une classe est **une seule ligne**. Le marquer lu y
inscrivait « lu » pour **toutes** les familles : la première qui l'ouvrait le
faisait disparaître de chez les autres.

L'état de lecture d'un envoi collectif appartient au **lecteur**, pas au message.
