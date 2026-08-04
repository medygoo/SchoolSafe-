# Le site aux couleurs de l'école — 4 août 2026

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
