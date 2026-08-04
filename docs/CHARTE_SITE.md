# La charte de l'école — le site ET les documents · 4 août 2026

> **Décision de Loms, 4 août 2026 :** la charte couvre **le site de l'école et
> tout document que l'application produit** — reçu, bulletin, certificat,
> convocation, fiche de paie, carte d'élève.
>
> L'**interface** de l'application garde le bleu du logiciel. Ce n'est pas une
> exception mais la même règle vue de l'autre côté : **l'interface porte le
> logiciel, le document porte l'école.** Un parent qui ouvre l'application
> ouvre SchoolSafe ; une administration qui reçoit un certificat reçoit Le Sage.

Ce document décrit d'abord le site (§1 à §6), puis les documents (§7).

---


Le site déposé sur `cslesage.com` portait **la première des quatre tentatives
de couleur** : crème, brun et laiton, avec une variable CSS littéralement
nommée `--emerald` qui contenait du brun foncé. Il porte maintenant la charte
retenue : **gris bleuté · blanc · or**.

---

## 1. La couleur a été relevée, pas devinée

Loms a envoyé une photographie du mur de l'école. Les pixels ont été
échantillonnés, pas regardés — l'œil se trompe sur un gris coloré, et c'est
exactement l'erreur qui a coûté trois passes complètes l'an dernier.

| zone de la photographie | valeur | teinte · saturation · luminosité |
|---|---|---|
| le mur, au point le mieux éclairé | `#6e7984` | **210° · 9 % · 47 %** |
| le mur, en pénombre | `#5c6670` | 210° · 10 % · 40 % |
| la bande ocre du bas | `#9e855f` | 37° · 27 % · 46 % |

La charte notée dans `CLAUDE.md` — `#657786`, **207° · 14 % · 46 %** — est le
même gris. L'écart de saturation est celui d'un mur éclairé au tungstène.
**La charte tient, elle n'a pas été modifiée.**

L'ocre photographié est terne parce qu'il est dans l'ombre. La référence de
l'or reste **l'étoile de l'emblème** : `#c09018`.

---

## 2. La palette du site

```css
/* le gris de l'école */
--ground-deep #657786   le mur — grands aplats
--ground      #556777   bandeaux, boutons, pastilles
--ground-soft #8896a2   texte secondaire sur fond sombre
/* les fonds clairs */
--white #ffffff   --surface #f0f1f2   --surface-2 #dadee2
/* l'or de l'emblème */
--gold #c09018   --gold-light #e2b84f   --gold-deep #7a5a0d   --gold-pale #fae6b8
/* l'encre */
--ink #1a2228   --muted #5e6c78   --line rgba(60,73,83,.13)
```

**Les variables ont été renommées.** Une variable appelée `--emerald` qui
contient du gris est un mensonge qui se recopie : c'est la même famille de
défaut que deux écrans qui répondent différemment à la même question.

---

## 3. Les contrastes sont mesurés

`node tools/audit-contraste-site.mjs` — 17 couples texte/fond réellement
employés, confrontés au seuil WCAG AA (4,5:1 texte courant · 3:1 grands
caractères et repères). **Aucun sous le seuil.**

Deux résultats qui commandent la mise en page :

> **Le mur (`--ground-deep`) ne porte que du BLANC** — 4,63:1. `--surface` y
> tombe à 4,09 et `--gold-light` à 2,47, même en grands caractères.
> Sur ce fond, **l'or ne s'écrit pas : il se remplit.** La pastille survolée
> passe en aplat d'or à texte d'encre — 5,56:1.
>
> Le petit texte sur gris va sur **`--ground`** `#556777` : blanc 5,85:1,
> `--surface` 5,17:1, `--gold-pale` 4,75:1.

L'outil est éprouvé dans les deux sens. `--preuve` lui fait refuser le cas
connu : **l'or sur blanc, 2,90:1** — celui que l'œil croit lisible.

Il déclare aussi ce qu'il ne sait pas vérifier : les textes posés sur une
photographie, les demi-transparences, et la palette « côté enfant ».

---

## 4. Ce qui ne prend PAS la charte

- **La palette « côté enfant »** — corail, ciel, soleil, menthe, raisin.
  Distinguer les âges est une fonction, pas une identité.
- **L'application SchoolSafe** garde le bleu du logiciel. L'interface porte le
  **logiciel** ; les documents imprimés portent l'**école**. C'est la
  distinction la plus souvent perdue, et elle se paie cher.

---

## 5. Ce qui a changé, fichier par fichier

Dépôt **`medygoo/the-wise-school`**, commit `e832ab3`.

| fichier | ce qui change |
|---|---|
| `assets/site.css` | la palette entière : variables renommées, ~70 littéraux remplacés, demi-transparences comprises |
| `index.html` | `theme-color`, le style en ligne du bouton du bandeau, le fond de la vague qui doit suivre le bandeau au-dessus d'elle |
| `ecole.html` `galerie.html` `contact.html` | `theme-color` |
| `programmes.html` | `theme-color` + 5 styles en ligne posés sur le bandeau gris |

Les mêmes fichiers sont tenus à jour dans `dist/` du dépôt de l'application.

---

## 6. Le dépôt par FTP

Le site déjà en ligne n'a **pas** besoin d'être remonté en entier. Six
fichiers seulement ont changé — les 21 photographies, le logo, `robots.txt` et
`sitemap.xml` sont inchangés.

```
assets/site.css        ← à déposer dans le dossier assets/
index.html
ecole.html
programmes.html
galerie.html
contact.html
```

Ils écrasent les anciens. Après le dépôt, **forcer le rechargement** du
navigateur (Ctrl+Maj+R, ou vider le cache sur téléphone) : sans cela l'ancien
`site.css` reste en mémoire et les couleurs paraissent inchangées.

---

# 7. Les documents produits par l'application

`node tools/audit-charte.mjs` disait, avant ce lot :

```
✗ 505 couleur(s) hors charte sur 43 documents
```

Il dit maintenant :

```
✓ Les 43 documents de l'école ne portent que du gris, du blanc et de l'or
```

## 7.1 Ce qui a été remplacé

**520 couleurs, sur 332 lignes, dans 46 plages de documents.** Ce n'étaient
pas 505 décisions : trente et une couleurs distinctes revenaient partout.

| ancienne | où | nouvelle | mesure sur blanc |
|---|---|---|---|
| `#243a6b` ×167 | **le bleu du logiciel** — titres, en-têtes de tableaux, filets | `#556777` | 5,85:1 |
| `#205fae` `#2f7bd6` | bleus d'accent | `#657786` | 4,63:1 |
| `#1d4ed8` `#3b5998` `#1e3a6e` `#1446aa` | bleus divers | `#556777` | 5,85:1 |
| `#93c5fd` `#c7d7f5` `#c7d2fe` `#d0eaf5` `#dbe7fb` | bleus pâles de fond | `#dadee2` | — |
| `#0f7ea8` `#0a5b7a` | turquoise de la liste EXETAT | `#556777` · `#1a2228` | |
| `#9b6fd4` `#8255c4` `#6f44ab` | violets du TENAFEP et des préparations | `#657786` · `#556777` · `#1a2228` | |
| `#6f6557` ×119 | texte secondaire brun | `#5e6c78` | 5,40:1 |
| `#a89c8b` ×20 | petit texte du pied de page | `#5e6c78` | **3,03 → 5,40:1** |
| `#2a2622` `#241f1a` `#44403c` | encre brune | `#1a2228` | 16,1:1 |
| `#efe3d3` `#ddd0bf` | bandes crème | `#dadee2` | |
| `#fff5ea` `#f6ede0` `#fff8f0` `#fdf4e7` | papier crème | `#f0f1f2` | |

`#a89c8b` mérite d'être relevé à part : il portait le pied de page officiel en
**corps de 10 pixels**, à **3,03:1**. Ce n'était pas seulement un écart de
charte, c'était une ligne difficile à lire sur un document imprimé. Elle est
maintenant à 5,40:1.

## 7.2 L'assistant partagé — le défaut annoncé était bien là

`CLAUDE.md` prévenait : *« Le pied de page officiel n'appartient à aucun
document : il est appelé par quatorze d'entre eux. Il avait gardé l'ancien
papier crème quand tous les autres avaient été repris. »*

**C'était vrai ici aussi.** `_officialFooter` ne produit pas de PDF, donc aucun
outil qui parcourt « les fonctions qui produisent un document » ne le voyait.
Il a été repris explicitement, avec `ssBuildBadge` et `ssBuildCarte`.

Deux corrections y ont été faites au passage :

- le filet de séparation passe à l'**or de l'emblème** — la troisième couleur
  de la charte, employée comme filet et non comme texte ;
- `page-break-inside:avoid` sur le bloc des signatures. *« Une signature
  séparée de son intitulé ne signe plus rien. »* Rien ne le garantissait.

## 7.3 Les cartes d'élève — rien n'a été retiré

Les cartes sortent d'un **studio à dix familles** que la Direction choisit
(Arc-en-ciel, Prestige Or, Jungle Safari…). Supprimer ce choix aurait dépassé
la demande.

**Une onzième famille a été ajoutée — `L · Le Sage — charte de l'école` — et
c'est elle le défaut.** Ce qui sort de l'application sans qu'on touche à rien
porte donc l'école. Les dix autres restent disponibles.

```
--ss-navy  #1a2228   --ss-navy2 #556777    en-tête : encre → mur, texte blanc
--ss-gold  #c09018   --ss-gold2 #e2b84f    l'étoile de l'emblème
--ss-cc    #556777   --ss-cc-soft #dadee2  --ss-cc-dark #1a2228
```

Quatre variantes d'accent, toutes dans la charte : *Le mur · Mur clair ·
Or de l'emblème · Encre*.

## 7.4 Ce qui reste hors charte, et pourquoi

- **Les couleurs sémantiques** — vert d'un paiement, rouge d'une dette, orange
  d'une alerte, et le rose de `status==='sick'`. Elles disent un **état**, pas
  une identité. Vérifié à la source avant de le décider : `#9d174d` est bien
  écrit sous `a.status==='sick'`. Il a été ajouté à la liste des couleurs
  sémantiques de l'outil plutôt que remplacé.
- **Les couleurs par classe** — distinguer les classes est une fonction.
- **L'interface** — elle porte le logiciel.

## 7.5 Une correction dans l'outil lui-même

`tools/audit-charte.mjs` portait un commentaire qui décrivait le gris de
l'école comme un **vert de gris, teinte 136°, `#a9b4ac`** — le *troisième* des
quatre essais, abandonné. Son code, lui, a toujours mis en œuvre le gris
bleuté retenu.

Un outil dont le commentaire dit autre chose que le code est un piège à
retardement : le prochain qui le lira corrigera le code pour le faire
correspondre au commentaire, et rejettera la charte. Le commentaire a été mis
en accord avec le code.

## 7.6 Ce qui n'a PAS été fait, et devrait l'être

Le pied de page officiel compte **deux colonnes** : *Signature & cachet* et
*Lu et approuvé*. `CLAUDE.md` en demande **trois** :

> **bénéficiaire · acteur · autorité.** Sur un reçu, le caissier signe de sa
> main devant la famille qui paie, à côté du visa. Une signature qui s'imprime
> toute seule ne signe plus rien.

Aujourd'hui la ligne de **celui qui accomplit l'acte** manque. Ce n'est pas un
défaut de couleur — c'est une règle métier, elle touche quatorze documents, et
elle appartient à Loms. **Signalée, pas décidée.**
