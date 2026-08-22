# Prototypes de direction visuelle — pour ChatGPT

Déposé par Claude à la demande de Loms, 15 août 2026, pour que **ChatGPT puisse
consulter et comprendre les deux propositions**.

> **Ces fichiers ne font pas partie de l'application.** Ils sont volontairement
> hors de `dist/` : le contrôle de publication compte les fichiers de `dist`, et
> les deux workflows ne se déclenchent que sur `main`. Rien ici ne peut atteindre
> l'école. `dist/index.html` n'a **pas** été modifié — aucun octet.

---

## Comment les lire

Ce sont deux fichiers HTML autonomes : tout est dedans, aucune dépendance
extérieure, aucune police téléchargée, aucune image. Ils s'ouvrent dans un
navigateur. GitHub n'affiche pas le HTML rendu — pour le **lire**, la source
suffit ; pour le **voir**, il faut ouvrir le fichier localement.

| fichier | ce que c'est |
|---|---|
| `01-registre.html` | un **document** : le système de design complet, puis cinq écrans dessinés en statique |
| `02-mosaique.html` | une **application manipulable** : six profils, menus réels, navigation, formulaires, tout fonctionne en JavaScript pur |
| `03-copilote.html` | une **application manipulable** : les 53 destinations de Direction 1 et les 44 de Direction 2, regroupées par domaine ; un panneau de copilote latéral ; les quatre autres rôles gardent leur liste plate, sans domaines inventés |

Dans `02-mosaique.html`, les endroits utiles à la lecture du code :

- `const NAV = {…}` — les menus réels des six rôles, repris de `dist/index.html`
- `.app-root[data-t="light"] / [data-t="dark"]` — **tous les jetons de couleur**
- `const V = {}` — une fonction par écran (`V.dashboard`, `V.students`, `V.caisse`,
  `V.scanner`, `V.messages`, `V.attendance`, `V.enfants`, `V.systeme`)
- `function mark()` — le bouclier et ses modules QR, redessinés en SVG d'après le logo

Dans `03-copilote.html`, les endroits utiles à la lecture du code :

- `const NAV = {…}` — **extrait de `window.NAV` dans `dist/index.html`**, pas
  retapé à la main : un script Python a parcouru le vrai fichier et en a sorti
  les 76 destinations et leurs 6 rôles (`direction`, `direction2`, `direction3`
  pour la Caisse, `enseignant`, `parent`, `gardien`) le 22 août 2026. Si l'app
  change ses menus, cette liste se périme — elle ne se corrige pas à l'œil,
  elle se réextrait.
- `const GROUPES = […]` — le regroupement des 53 destinations de Direction 1
  (et par filtrage, des 44 de Direction 2) en 11 domaines. C'est un choix
  éditorial, pas une donnée de l'application : ChatGPT ou Loms peuvent le
  redécouper autrement sans toucher à `NAV`.
- **Pourquoi Caisse, Enseignant, Parent et Gardien n'ont pas de domaines** :
  15, 21, 19 et 10 destinations tiennent dans une seule liste. Leur inventer
  des groupes aurait habillé un vide, pas simplifié quelque chose de réel —
  la même leçon que `CLAUDE.md` répète pour les données inventées.
- le panneau **Copilote**, à droite : une proposition d'assistant qui
  renvoie vers un écran réel plutôt que de répondre à la place de
  l'application. Il ne répond à rien ici — chaque échange est scripté, et
  le dit explicitement dans son propre texte.

---

## Ce qui sépare les deux propositions

Elles ne diffèrent pas par la palette. Elles répondent différemment à **une seule
question : que veut dire une couleur ?**

| | réponse | conséquence |
|---|---|---|
| **n° 1 · Registre** | la couleur dit un **ÉTAT** | vert payé · ambre en attente · rouge impayé. Le reste est encre sur papier. Le tableau est le composant principal. |
| **n° 2 · Mosaïque** | la couleur dit un **DOMAINE** | bleu personnes · or finances · vert portail · violet pédagogie · orange communication · rouge urgence. |

La règle qui empêche la n° 2 de devenir bruyante, et qui est le cœur de la
proposition :

> **La couleur de domaine vit dans le décor — menu, bandeau, tuiles, icônes —
> et JAMAIS dans une donnée.** Dans un tableau, on ne voit donc que les
> couleurs d'état.

---

## Contrastes — mesurés, pas estimés

Calculés sur la formule WCAG, pas jugés à l'œil.

**Palette du n° 2, tirée du logo :**

| couple | rapport | verdict |
|---|---|---|
| `#1E4FCB` bleu, blanc dessus | **6,92:1** | AA |
| `#F5B21B` or, **texte** sur blanc | **1,86:1** | ❌ interdit |
| `#F5B21B` or, **encre `#0C1220` dessus** | **10,16:1** | AA |
| `#0A7A44` vert sur blanc | 5,41:1 | AA |
| `#6B32C9` violet sur blanc | 7,18:1 | AA |
| `#A85405` orange sur blanc | 5,34:1 | AA |
| `#C41A15` rouge sur blanc | 5,99:1 | AA |
| rail `#12358F`, blanc dessus | 10,87:1 | AA |
| rail `#12358F`, `#A9BCEB` dessus | 5,74:1 | AA |

> **L'or ne s'écrit pas, il se remplit.** C'est exactement la leçon déjà notée
> dans `CLAUDE.md` pour l'or de l'école (`#c09018`, 2,9:1 sur blanc), retrouvée
> ici sur l'or du logiciel. Deux ors différents, la même contrainte.

**Palette du n° 1 :** encre `#0F1729` 17,87:1 · ardoise `#5A6478` 5,95:1 ·
tertiaire `#626C82` 5,27:1 · bleu `#2B57D4` 6,15:1 · les trois états ≥ 4,5:1
sur leur pastille.

---

## Ce que les deux propositions respectent, sans exception

Ce sont des règles de `CLAUDE.md`, pas des choix esthétiques :

1. **L'interface porte la charte du LOGICIEL, les documents celle de l'ÉCOLE.**
   Dans `02-mosaique.html`, l'écran Caisse montre les deux côte à côte :
   l'aperçu du reçu est dessiné en gris bleuté `#6b7d8b` et or `#c09018` — la
   charte de l'école — au milieu d'une interface bleue. C'est délibéré et c'est
   démontrable à l'écran.
2. **L'emblème de l'école n'apparaît nulle part dans l'interface.** Seul le
   bouclier SchoolSafe est utilisé.
3. **Aucune donnée réelle.** Élèves, tuteurs, numéros et montants sont inventés.
4. **Aucun bouton muet.** Ce qui n'est pas dessiné le dit par un message, au
   lieu de ne rien faire — la faute notée dans `CLAUDE.md` (« un `return` muet
   dans un gestionnaire de clic est toujours un défaut »).
5. **Un refus n'est pas un silence.** Dans le n° 2, le bouton réseau de la barre
   du haut coupe la connexion : les messages passent alors de « envoyé » à
   « mis en file d'attente ».

---

## Vérifications passées

Exécuté dans Chromium (Playwright), sur le fichier tel qu'il est ici :

- les **six profils** s'affichent — Direction 1 (53 destinations), Direction 2,
  Caisse, Enseignant, Gardien, Parent ;
- `Ctrl K`, recherche d'élève, sélection multiple, tiroir de fiche,
  encaissement, quatre résultats de scan, bascule hors ligne : tous actifs ;
- **aucune erreur JavaScript** ;
- **aucun débordement horizontal** en 1358 px, 933 px et 427 px.

---

## Ce sur quoi l'avis de ChatGPT est utile

Rien ici ne touche à la base, mais deux points la frôlent :

1. **Le cycle secondaire.** L'application porte encore `secondaire`, `humanites`,
   l'écran EXETAT et le rapport SECOPE, alors que l'école s'arrête à la 6e
   primaire et prépare l'ENAFEP. Je n'ai rien retiré et je ne propose rien —
   c'est une décision de Loms, avec des conséquences de schéma.
2. **Les couleurs par classe** sont aujourd'hui calculées dans le navigateur
   (`clsColor()`). Si la Direction doit pouvoir choisir la couleur d'une classe,
   c'est une colonne sur `classes`, pas un calcul local. Question ouverte, pas
   une demande.

**Rien n'est demandé côté serveur pour ces prototypes.** Ils sont entièrement
frontend et ne dépendent d'aucune RPC.

---

## État du dépôt

- branche : `claude/schoolsafe-design-proposal-elh6xu`
- `main` : **non touchée**
- `dist/` : **non touché** — la publication GitHub Pages est intacte
- aucune Pull Request ouverte : Loms ne l'a pas demandée
