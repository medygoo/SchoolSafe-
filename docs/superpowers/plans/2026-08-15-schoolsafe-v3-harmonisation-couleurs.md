# SchoolSafe V3 Harmonisation Couleurs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harmoniser uniquement les couleurs des écrans internes SchoolSafe après connexion, sans modifier les fonctions, textes, mouvements, cubes, animations, structure, connexion, photos, sécurité ou backend.

**Architecture:** Ne pas réécrire `dist/index.html`. La V3 est une prévisualisation isolée : `prototypes/03-v3-harmonisation.html` charge l’application existante `../dist/index.html` telle quelle dans un iframe de même origine, puis ajoute uniquement `prototypes/03-v3-harmonisation.css`. La feuille CSS est strictement scoped à `.app` et à ses descendants, donc les écrans avant connexion restent hors de la portée V3.

**Tech Stack:** HTML/CSS statique, JavaScript minimal uniquement dans le wrapper de prévisualisation, audits Node.js, branches GitHub.

## Global Constraints

- Travailler uniquement sur `prototype-v3-ui`.
- Ne jamais modifier `main`.
- Ne jamais modifier `backup-frontend-avant-v3-2026-08-15`.
- `dist/index.html` doit garder exactement le même blob SHA que la sauvegarde.
- Les écrans splash, photos de connexion, login, code et mot de passe restent visuellement et fonctionnellement identiques.
- Ne modifier aucun texte ou libellé de l’application.
- Ne modifier aucun JavaScript de l’application, gestionnaire d’événement existant, route, rôle, permission, API, Supabase, VPS, serveur ou donnée.
- Conserver toutes les animations et tous les mouvements existants, y compris le cube 3D, les rebonds, glows et transitions.
- Ne pas modifier la géométrie des composants : tailles, espacements, positionnement, rayons, structure et disposition restent inchangés pendant cette première passe.
- Les changements de production sont interdits ; la V3 reste une branche de travail.

---

### Task 1: Garde-fous automatisés

**Files:**
- Create: `tools/audit-v3-theme.mjs`

- [x] **Step 1: Écrire le test avant la palette**

Le test doit échouer si les fichiers V3 n’existent pas.

- [x] **Step 2: Vérifier l’échec attendu**

Résultat observé avant création des fichiers :

```text
FAIL: la feuille CSS V3 doit exister
FAIL: le wrapper de prévisualisation V3 doit exister
```

- [x] **Step 3: Ajouter les contrôles de portée**

Le test vérifie :
- présence de `.app {` ;
- présence de `.dark .app {` ;
- accents de rôle scoped à `.app` ;
- absence de sélecteurs de la zone de connexion ;
- absence de propriétés de géométrie et de mouvement dans la feuille V3 ;
- wrapper chargeant exactement `../dist/index.html` ;
- injection de la seule feuille `03-v3-harmonisation.css`.

### Task 2: Palette V3 isolée

**Files:**
- Create: `prototypes/03-v3-harmonisation.css`
- Create: `prototypes/03-v3-harmonisation.html`
- Keep unchanged: `dist/index.html`

- [x] **Step 1: Créer la palette scoped**

La palette redéfinit uniquement les couleurs internes : bleu/navy SchoolSafe, accents de rôle, surfaces, bordures, textes et couleurs sémantiques.

- [x] **Step 2: Harmoniser les surfaces existantes sans changer leur forme**

Sont recolorés uniquement : sidebar, topbar, bottom-nav, cartes, sections, formulaires, boutons, badges, héros et notifications.

- [x] **Step 3: Préserver les mouvements**

Aucune règle V3 ne contient `transform`, `animation` ou `transition`.

- [x] **Step 4: Préserver la géométrie**

Aucune règle V3 ne contient `width`, `height`, `padding`, `margin`, `display`, `position`, `grid-template`, `flex` ou `border-radius`.

- [x] **Step 5: Créer le wrapper de prévisualisation**

Le wrapper charge `dist/index.html` sans le modifier et ajoute la feuille V3 après le chargement.

### Task 3: Vérification des invariants

**Files:**
- Compare: `dist/index.html` sur sauvegarde et V3.
- Test: `tools/audit-v3-theme.mjs`.

- [x] **Step 1: Vérifier le test après implémentation**

Résultat frais :

```text
PASS: garde-fous V3 respectés
PASS: aucun sélecteur protégé dans la CSS V3
PASS: aucune propriété de mouvement ou géométrie dans la CSS V3
```

- [x] **Step 2: Vérifier le blob du vrai frontend**

`dist/index.html` doit avoir le même SHA sur la sauvegarde et sur `prototype-v3-ui` :

```text
51b8caec43215df5e1143a889b75de6d66516215
```

- [x] **Step 3: Vérifier les branches protégées**

`main` et `backup-frontend-avant-v3-2026-08-15` restent sur :

```text
efcebb5b11855e70304d1fb7db72c78448b68f85
```

- [x] **Step 4: Ne pas fusionner ni déployer**

La branche V3 reste séparée jusqu’à validation visuelle explicite de l’utilisateur.
