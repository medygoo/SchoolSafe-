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

---

# 8. L'emblème et les signatures · 4 août 2026

Demande de Loms : **« ajouter le logo de l'école et la signature »**.

## 8.1 L'emblème — les dix derniers documents

```
audit-logo.mjs  avant  →  ✗ 10 documents sur 38 sans emblème
audit-logo.mjs  après  →  ✓ les 38 documents officiels portent l'emblème
```

Il manquait sur : le **reçu de paiement**, le rapport mensuel, le palmarès
annuel, les listes **ENAFEP** et **EXETAT**, la fiche de santé, le kit
d'urgence médicale, les **deux fiches de paie** et le rapport **SECOPE**.

Ce n'est pas cosmétique. *« Un document qui engage l'école porte son emblème ;
sans lui, un bulletin ou une fiche de paie n'est qu'une feuille imprimée, et
une administration peut la refuser. »* Le reçu de paiement et les listes
d'examen d'État sont précisément ceux qu'une administration examine.

Un assistant unique le pose : `window._logoDoc(px)`.

> **Sans repli.** Si la Direction n'a pas téléversé l'emblème, **rien ne
> paraît**. Lui donner une valeur par défaut le ferait porter par une école
> qui ne l'a pas choisi — c'est l'erreur déjà commise, et corrigée, du côté de
> l'interface.

L'emblème est cerclé de l'**or de l'emblème**, `#c09018`.

`tools/audit-logo.mjs` a été mis à jour pour connaître ce nouvel assistant.

## 8.2 Les signatures — la colonne qui manquait

Le pied de page officiel, appelé par **quinze documents**, comptait deux
colonnes. Il en compte trois, dans l'ordre administratif francophone :

```
   Lu et approuvé          Établi par              Visa & cachet
   ─────────────────       ─────────────────       ─────────────────
   Bénéficiaire            l'agent connecté        l'autorité
   / Destinataire          nom + rôle              nom + rôle
```

La colonne du milieu manquait, et ce n'est pas une décoration :

> Sur un reçu, **le caissier signe de sa main devant la famille qui paie**,
> à côté du visa. Sans cette ligne, un document ne dit pas qui l'a établi, et
> le visa de la Direction couvre un acte auquel elle n'a pas assisté.

Elle se remplit toute seule avec la personne connectée — nom et rôle officiel
(`_roleOfficiel`), pas le libellé de la barre de navigation.

**Si l'autorité est la personne connectée**, elle ne signe pas deux fois :
l'autorité redevient la Direction Générale de l'école. Et si l'école n'en
déclare aucune, **aucun nom ne s'imprime** — ne rien afficher vaut mieux
qu'afficher faux.

**Aucune signature ne s'imprime toute seule dans ce pied de page.** Les trois
lignes sont vierges. Une signature pré-imprimée ne signe plus rien.

Vérifié en **exécutant la vraie fonction** du fichier dans Node, pas une
copie — les deux cas rendent ce qu'ils doivent rendre.

## 8.3 ⚠️ Une décision qui appartient à Loms

`dist/index.html` contient, en dur, **une vraie signature manuscrite** :

```js
window.SCHOOL_SIGNATURE = 'data:image/png;base64,…'   // ~40 Ko
```

Elle n'a pas été touchée. Mais il faut savoir ce qu'elle fait :

- elle est le **repli** — `DB.settings.school.signature` ne fait que la
  remplacer. Une installation qui n'a rien téléversé imprime **celle-ci** ;
- elle s'imprime aujourd'hui sur les **bulletins** et sur d'autres documents,
  dans la case « Direction » ;
- elle est **dans le dépôt**, donc lisible par quiconque y a accès.

`CLAUDE.md` dit deux choses qui s'appliquent :

> *« Une signature qui s'imprime toute seule ne signe plus rien — et
> pré-imprimer celle de la Direction la donnerait à quiconque produit un
> reçu. »*
>
> *« Aucun secret dans le dépôt. »* Une signature manuscrite scannée fonctionne
> comme un sceau.

**Trois voies possibles, c'est à Loms de trancher :**

| | ce qu'on fait | conséquence |
|---|---|---|
| **A** *(recommandé)* | `SCHOOL_SIGNATURE = null` par défaut ; la Direction téléverse son visa dans les réglages | rien ne s'imprime tant que la Direction ne l'a pas voulu ; l'image sort du dépôt |
| **B** | on la garde telle quelle | tout document produit par n'importe qui porte ce visa |
| **C** | on la retire complètement | les cases « Direction » restent vierges, à signer à la main |

**Une ligne de code sépare A de B.** Tant que Loms n'a pas répondu, rien ne
change : je ne retire pas seul la signature de quelqu'un.

---

# 9. Quel document se signe · 4 août 2026

Demande de Loms : *« savoir quel document mérite la signature ou pas — comme
le reçu doit avoir la signature, le cahier de préparation pas de signature,
juste le logo. »*

## 9.1 La règle

```
┌────────────────────────────────────────────────────────────────────┐
│  Un document se signe pour DEUX raisons, et deux seulement :       │
│                                                                    │
│    · DÉLIVRANCE   — il engage l'école envers un tiers : une        │
│                     famille, un employé, une administration.       │
│    · CERTIFICATION — il reste dans l'école, mais quelqu'un         │
│                     répond de son exactitude.                      │
│                                                                    │
│  Tout le reste est un document de TRAVAIL : emblème, pas de        │
│  signature.                                                        │
└────────────────────────────────────────────────────────────────────┘
```

Pourquoi la deuxième raison existe : **la règle a buté sur un cas.** Le *kit
d'urgence médicale* ne quitte pas l'école — il est affiché à l'infirmerie —
mais il porte des groupes sanguins et des allergies, et il est signé par la
Direction et l'infirmier(ère). Ce n'est pas une délivrance, c'est quelqu'un
qui répond d'une donnée dont dépend une vie.

**On n'a pas forcé le cas dans la règle : c'est la règle qui était trop
étroite.**

Et le motif de fond, qui vaut d'être dit : **une signature qui n'a pas de
raison d'être dévalue toutes les autres.** Si l'enseignant signe son cahier de
préparation, la signature du caissier au bas d'un reçu ne veut plus rien dire
de particulier.

## 9.2 Le classement des 46 documents

| | documents |
|---|---|
| **Se signent** (31) | les 7 reçus · attestation · 3 certificats · convocation · communiqué · fiche d'inscription · lettre de sanction · bulletins · PV de délibération · listes ENAFEP et EXETAT · rapport SECOPE · 2 fiches de paie · fiche santé · kit d'urgence · devoir · rapport aux familles · les 5 états comptables SYSCOHADA |
| **Ne se signent pas** (6) | **cahier de préparation** · rapport mensuel · palmarès annuel · relevé de présences · état financier de suivi · archive de fin d'année |
| **Ne sont pas des documents** (8) | CSV, JSON, image de carte, et les 4 impressions de cartes — la carte porte déjà l'emblème |

## 9.3 Ce qui a changé dans le code

- **Le cahier de préparation** portait `_officialFooter` — trois colonnes de
  signature — sur un document que l'enseignant écrit pour lui-même. Il porte
  maintenant une simple mention : *« Préparé par … — Document de travail
  pédagogique, ne fait pas foi de délivrance »*, sous un filet d'or.
- **`_pdfSignatureBlock`** — le bloc de signature SYSCOHADA des cinq états
  comptables — **était encore au bleu du logiciel**. C'est le *deuxième*
  assistant partagé qui échappe à un balayage par plages, après
  `_officialFooter`. Passé à la charte, filet d'or, et protégé contre une
  coupure de page.
- **Neuf emblèmes en ligne** ont été unifiés sur `_logoDoc` : même taille
  demandée, même cercle d'or. Ils divergeaient en 64 px et 56 px avec une
  bordure grise.

## 9.4 Deux outils, et un filet qui était troué

**`tools/audit-signature.mjs`** — la règle cesse d'être une opinion. Il
connaît les 46 documents, ce que chacun doit porter, et il refuse **dans les
deux sens** : `--preuve` lui présente un cahier de préparation qui se signe et
un reçu qui ne se signe pas ; il refuse les deux.

**`tools/audits.mjs`** — et voici ce qui était le plus grave de ce lot :

> `npm run audit` enchaînait les outils avec `&&`. Le troisième,
> `verif-coherence`, est en panne. **Donc les audits de l'emblème, de la
> charte, des signatures et des contrastes ne tournaient plus du tout** — sans
> que rien ne le dise.

Le filet était troué à l'endroit exact où on croyait l'avoir tendu. C'est la
même faute que celles que ces outils cherchent : un échec silencieux.
Maintenant chaque outil tourne, et le tableau final dit lequel passe.

## 9.5 Un audit qui posait la mauvaise question

Le contrôle inverse de `audit-logo.mjs` — *« l'emblème de l'école ne doit pas
paraître dans l'interface »* — listait **neuf fuites**. Vérifiées une par une :
**aucune n'était un défaut.** La ligne au-dessus affectait la valeur depuis
les réglages, ou la lecture servait à construire une carte, qui *est* un
document. Poser neuf gardes n'aurait rien protégé.

`CLAUDE.md` avait déjà appris exactement cela :

> *« La bonne question n'est pas "chaque accès porte-t-il sa garde ?" mais
> "la valeur peut-elle seulement être autre chose ?" »*

Le contrôle a été réécrit autour de la seule condition dont l'invariant
dépend : **toute affectation de `SCHOOL_LOGO` vient-elle des réglages, d'un
téléversement, ou de `null` ?** Si oui, le global ne peut pas contenir
d'emblème intégré, et le lire est sans risque n'importe où.

Trois lignes au lieu de neuf reproches — et il attrape la vraie faute.
Éprouvé : on lui a glissé `window.SCHOOL_LOGO = 'data:image/png;base64,…'`,
il l'a refusé ; le fichier a été restauré.

---

# 10. Qui a établi ce document · 4 août 2026

Demande de Loms : *« la signature doit être, mais bien définir quel profil et
le nom de la personne qui a créé ce reçu ; et dans le document financier et
reçu doit avoir la signature. »*

## 10.1 Une case de signature vide ne désigne personne

`_officialFooter` remplissait la colonne du milieu avec **la personne
connectée**. Ce n'est pas la même chose que l'auteur de l'acte.

> Un reçu réimprimé trois mois plus tard par la Direction disait
> **« Établi par la Direction »** — alors que c'est la caissière qui a
> encaissé devant la famille.

Le pied accepte maintenant un troisième argument, `{nom, role, le}` : l'auteur
**enregistré au moment où l'acte a eu lieu**.

| ce que le document porte | quand |
|---|---|
| **Établi par** — nom · profil · date de l'acte | l'auteur est enregistré. Une réimpression six mois plus tard donne **toujours le même nom** |
| **Délivré par** — nom · profil | aucun auteur enregistré. C'est vrai, et ça ne prétend pas être l'auteur de l'acte |

Vérifié en exécutant la vraie fonction, dans les deux cas.

## 10.2 Ce qui est raccordé

- **`printVersementRecu`** et **`viewReceipt`** portent désormais leur auteur
  enregistré — `v.by_name` / `r.by`, avec la date du versement.
- L'**autorité** de ces deux reçus était la caissière elle-même. Corrigé :
  l'autorité est la Direction. *La caissière n'est pas sa propre autorité.*
- Le **bloc SYSCOHADA** des états comptables disait « Etabli par le
  Responsable Comptable » avec une ligne vide — **aucun nom**. Il porte
  maintenant le nom et le profil de celui qui établit, et celui de la
  Direction qui approuve.
- L'**état financier** passe de « document de travail » à document signé, avec
  le même bloc que les cinq autres états — *une seule réponse par question*.

## 10.3 ⚠️ Un champ à demander — six reçus ne peuvent pas nommer leur auteur

`DB.payments` **n'enregistre pas qui a encaissé**. Les lignes sont créées
vides à l'inscription de l'élève, puis passées à `paid:true` par un `patch`
qui ne porte ni auteur ni horodatage.

```
pushSync('payments','patch',{paid:true},'sid=eq.'+sid+'&t=eq.'+t)
                            ↑ ni qui, ni quand
```

`CLAUDE.md` : *« Avant de lire un champ, vérifier qu'une écriture le
renseigne. »* Aucune écriture ne renseigne l'auteur — donc aucune lecture ne
le peut. Les six reçus concernés portent honnêtement « Délivré par ».

**Ce n'est pas un défaut du frontend : c'est un champ à demander à ChatGPT.**
On ne pose pas une garde là où la valeur ne peut pas exister. Demandé sur la
PR : que la ligne de paiement porte `paid_by`, `paid_by_name` et `paid_at`,
écrits côté serveur — un auteur que le navigateur pourrait choisir ne vaudrait
rien.

Les **états comptables** ne sont pas concernés : un état est *établi au moment
où on le tire*, donc celui qui le génère en est bien l'auteur, et il est nommé.

## 10.4 La signature pré-imprimée reste

Loms a tranché : *« la signature doit être »*. `window.SCHOOL_SIGNATURE` n'est
pas retirée. La réserve du §8.3 tient et n'est pas répétée ici : elle est
enregistrée, la décision est prise, on continue.

Ce que ce lot y ajoute, et qui répond à la préoccupation d'origine : **le visa
pré-imprimé ne peut plus couvrir seul un acte**, puisque la colonne du milieu
nomme celui qui l'a établi, avec son profil et la date.

---

# 11. Les fiches de paie · 4 août 2026

Demande de Loms : *« les fiches de paie doivent avoir la charte de couleur et
la signature. »*

## 11.1 La couleur

Les deux fiches passaient l'audit de charte — mais parce que l'outil accepte
les **gris neutres**, qu'il ne peut pas distinguer d'un choix délibéré. Elles
portaient encore la grisaille par défaut d'un cadre HTML :

| ancienne | nouvelle |
|---|---|
| `#374151` | `#1a2228` — l'encre |
| `#6b7280` | `#5e6c78` — le gris de texte |
| `#9ca3af` | `#8896a2` — le gris éclairci |
| `#e5e7eb` | `#dadee2` — les filets |
| `#f0f4ff` `#eaf3fc` | `#f0f1f2` — le fond clair |

Un gris de texte ne dit aucun état : il dit seulement « secondaire ». Il n'est
donc pas sémantique, et il prend la charte.

Restent hors charte, et c'est voulu : le **vert du versé**, le **rouge des
retenues**, l'**ambre de l'attente**. Elles disent un état.

## 11.2 La signature — elle ne nommait personne

Les deux fiches portaient **deux cases** :

```
Bénéficiaire — Josué Tshimanga        Direction — Complexe Scolaire Le Sage
```

La seconde nomme **l'école**, donc personne. Et **aucune case pour celui qui a
établi la paie** — sur un document où quelqu'un décide d'un montant versé à un
employé, c'est la case qui compte le plus.

Les deux fiches passent maintenant sur le **pied officiel commun** — *une seule
réponse par question* — avec trois signataires nommés :

```
   Lu et approuvé            Établi par              Visa & cachet
   Josué Tshimanga           Espérance Kabongo       Mme Grâce Mbuyi
   Enseignant(e)·Bénéficiaire  Caisse · 31/08/2026     Direction Générale
```

- **le bénéficiaire est nommé, avec son profil** — c'est lui qui acquitte ;
  laisser la case vide reviendrait à faire signer n'importe qui ;
- **l'auteur est enregistré**, résolu depuis `sal.by`, avec la date de
  versement. `salaries` écrit bien `by: S.user.id` — la donnée existait, elle
  n'était simplement pas lue ;
- **l'autorité est une personne** de la Direction, plus le nom de l'école.

Le pied officiel accepte pour cela un quatrième paramètre, `beneficiaire`.

## 11.3 Ce que ce lot confirme

`salaries` enregistre son auteur ; `payments` ne l'enregistre pas. **La même
question, deux réponses opposées selon la table.** C'est exactement la demande
P0-1 adressée à ChatGPT dans `coordination/DEMANDES_A_CHATGPT.md` : la fiche de
paie sait dire qui a versé, le reçu de frais ne le sait pas.
