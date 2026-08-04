# Demande à ChatGPT — les images des activités parascolaires

**Demandée par Loms le 4 août 2026.** Il veut des **images réalistes d'enfants
africains noirs** pour illustrer les activités parascolaires sur le site.

**La répartition qu'il a fixée :** ChatGPT génère les images, Claude fait
l'assemblage et l'intégration. Ce document est la commande — elle est écrite
pour être suivie sans avoir à revenir poser de questions.

---

## 0. Une réserve, dite une fois, puis on avance

Ces images ne sont pas des photographies de l'école : ce sont des images
fabriquées. Sur le site d'une **vraie** école, une famille qui les regarde peut
croire qu'elle voit les élèves de l'établissement.

**Deux précautions suffisent, et elles sont intégrées à la commande :**

1. **aucun visage identifiable ne doit ressembler à une personne réelle** — pas
   de portrait au premier plan qu'on pourrait prendre pour un élève nommé ;
2. **la page les présentera comme des illustrations**, pas comme la galerie.
   Le site garde par ailleurs **21 vraies photographies** de l'école : c'est là
   que vivent les vrais élèves, et c'est la galerie qui fait foi.

Loms a tranché, la commande suit. Ce paragraphe est là pour que personne n'ait
à se le redemander dans six mois.

---

## 1. Ce qui est déjà en place — les images ont leur emplacement prêt

La page `inscription.html` du site porte déjà une section **« Les activités
parascolaires »** avec huit cartes. Chacune affiche aujourd'hui **un dessin
vectoriel** que j'ai tracé (10 Ko pour les huit).

> **Les photographies remplaceront les dessins sans changer une ligne de mise
> en page.** Le cadre est déjà au format carré, la CSS `.act-photo` existe.
> Dès que les fichiers arrivent, je les branche.

Les dessins restent le **repli** : si une image manque, la carte n'est jamais
vide.

---

## 2. Les huit images demandées

Un fichier par activité. **Format carré 1:1.**

| # | fichier | scène |
|---|---|---|
| 1 | `act-bilingue.jpg` | deux enfants (7-9 ans) penchés sur un livre ouvert, en classe claire |
| 2 | `act-informatique.jpg` | un enfant (8-10 ans) devant un écran d'ordinateur, mains sur le clavier |
| 3 | `act-danse.jpg` | trois enfants (6-9 ans) en mouvement de danse, bras levés, salle claire |
| 4 | `act-musique.jpg` | un enfant (7-9 ans) jouant un tambour/djembé, un autre chantant à côté |
| 5 | `act-poterie.jpg` | un enfant (8-10 ans), mains dans l'argile, poterie en cours sur un tour |
| 6 | `act-taekwondo.jpg` | deux enfants (8-11 ans) en position de garde, tatami |
| 7 | `act-ateliers.jpg` | trois enfants (6-9 ans) peignant/bricolant autour d'une table |
| 8 | `act-cantine.jpg` | quatre enfants (6-10 ans) attablés, plateaux-repas, réfectoire clair |

---

## 3. La tenue — c'est le point le plus important

**Tous les enfants portent l'uniforme de l'école, et il n'y en a qu'un :**

```
   HAUT      chemise ou polo BLANC
   BAS       jupe (filles) ou short/pantalon GRIS BLEUTÉ
   GRIS      #556777  —  teinte 207-210°, saturation 14 %
             ce n'est PAS un gris neutre : il tire vers le bleu
```

**L'insigne de l'école est sur chaque tenue :** un **écusson rond doré**
(`#c09018`) portant une **étoile à cinq branches**, cousu sur la **poitrine à
gauche**, taille d'un badge (≈ 5 cm).

Pour les activités où la tenue change :

- **taekwondo** — dobok **blanc**, ceinture **dorée** (`#c09018`), écusson doré
  à étoile sur la poitrine gauche ;
- **poterie et ateliers** — tablier **gris bleuté** par-dessus l'uniforme,
  écusson visible.

**L'emblème complet de l'école** (le cercle noir avec « COMPLEXE SCOLAIRE LE
SAGE » et « THE WISE SCHOOL INTERNATIONAL » autour d'une étoile d'or) est
**trop fin pour être lisible sur un vêtement** à cette taille. Ne cherche pas à
écrire le texte : **l'écusson doré à l'étoile suffit**, et c'est lui qui se
reconnaît de loin. Le vrai emblème est ailleurs sur le site.

---

## 4. Les enfants

- **enfants africains noirs**, peaux et coiffures variées, garçons et filles ;
- **âges 6 à 11 ans** selon l'activité ;
- expressions naturelles : concentrés, souriants, en action — **pas de pose
  figée face à l'objectif** ;
- **aucun visage en gros plan** : plan moyen ou plan large, l'enfant est dans
  une scène, il n'est pas un portrait ;
- **pas de nom, pas de badge nominatif lisible.**

---

## 5. Le décor et la lumière

- salle de classe ou salle d'activité **claire et simple**, murs clairs ;
- lumière **naturelle et douce**, pas de contre-jour, pas de flash dur ;
- décor **peu chargé** — le sujet est l'enfant et son activité ;
- **contexte kinois crédible** : rien d'ostensiblement européen ou américain
  (pas de radiateur, pas de neige à la fenêtre, pas de mobilier scandinave) ;
- **aucun texte visible** dans l'image — ni au tableau, ni sur une affiche, ni
  sur un cahier. Le texte généré est presque toujours faux, et un mot mal
  orthographié au mur d'une école se voit tout de suite.

---

## 6. Le poids — Loms y tient, et il a raison

> *« pour bien publier le site, il faut me donner des contenus qui ne pèsent
> pas, pour que ça ne ralentisse pas la publication. »*

Le site est déposé **par FTP**, à Kinshasa, sur une connexion qui a déjà
lâché une fois en plein transfert. Chaque mégaoctet compte deux fois : au dépôt,
puis à chaque visite d'un parent sur son téléphone.

**Le budget est ferme :**

| | |
|---|---|
| dimensions | **1000 × 1000 px**, pas plus |
| format | **JPEG** |
| poids par image | **≤ 120 Ko** |
| poids des huit | **≤ 1 Mo au total** |

Ne rends pas des images de 2000 px « au cas où » : je devrais les
redimensionner, et une image réduite après coup est moins nette qu'une image
rendue à la bonne taille. **1000 px est exactement ce qu'il faut** — la carte
les affiche à 260 px, donc presque 4× pour les écrans à haute densité.

Si ton outil ne sait sortir qu'en PNG ou en très grand, **dis-le-moi** : je
convertis et je compresse ici, c'est deux minutes. Mais préviens, ne le laisse
pas passer en silence.

---

## 7. Comment me les remettre

Dépose-les dans une **branche** ou une **Pull Request** vers
`medygoo/the-wise-school`, dans le dossier `assets/activites/`, avec exactement
les noms du §2 :

```
assets/activites/act-bilingue.jpg
assets/activites/act-informatique.jpg
assets/activites/act-danse.jpg
assets/activites/act-musique.jpg
assets/activites/act-poterie.jpg
assets/activites/act-taekwondo.jpg
assets/activites/act-ateliers.jpg
assets/activites/act-cantine.jpg
```

**Les noms comptent** : je branche les cartes dessus sans les renommer. Une
image nommée autrement ne s'affichera pas et personne ne le verra tout de
suite — la carte gardera son dessin.

**Si une seule image te satisfait mal, ne l'envoie pas.** Sept photographies et
un dessin, c'est cohérent ; huit dont une ratée, non. Le dessin reste, il est à
la charte, et il ne trahit rien.

---

## 8. Ce que je fais dès qu'elles arrivent

1. je vérifie le poids et les dimensions, je recompresse si besoin ;
2. je branche les huit cartes sur les photographies, **les dessins restant en
   repli** — si une image ne charge pas, la carte n'est jamais vide ;
3. je vérifie les contrastes du texte qui les accompagne ;
4. je regarde la page sur un écran de téléphone avant de la déclarer bonne ;
5. je prépare l'archive FTP et je la remets à Loms.

**Rien n'attend ces images pour être publié.** La page est complète
aujourd'hui, avec les dessins. Les photographies l'améliorent — elles ne la
débloquent pas.

---

## 9. Ce que cette demande ne te demande PAS

- pas de retouche du logo de l'école, pas de nouveau logo ;
- pas de photographie de bâtiment, de portail ou de façade — celles-là doivent
  être **vraies**, et l'école en a déjà ;
- pas de visage d'adulte au premier plan : un enseignant peut être présent, de
  dos ou de trois quarts, jamais en portrait.
