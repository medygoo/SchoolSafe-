# SchoolSafe V3 Harmonisation Couleurs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harmoniser uniquement les couleurs des écrans internes SchoolSafe après connexion, sans modifier les fonctions, textes, mouvements, cubes, animations, structure, connexion, photos, sécurité ou backend.

**Architecture:** Ajouter une couche CSS V3 strictement scoped à `.app` et à ses descendants. Les variables de palette seront redéfinies au niveau de `.app` afin que l'écran splash et l'écran login, qui sont hors `.app`, conservent leur rendu actuel. Les accents par rôle seront redéfinis avec des sélecteurs `body[data-role] .app`, sans changer les routes, menus, DOM ou JavaScript.

**Tech Stack:** HTML/CSS existant dans `dist/index.html`, audits Node.js existants du dépôt, GitHub branches.

## Global Constraints

- Travailler uniquement sur `prototype-v3-ui`.
- Ne jamais modifier `main`.
- Ne jamais modifier `backup-frontend-avant-v3-2026-08-15`.
- Les écrans splash, photos de connexion, login, code et mot de passe restent visuellement et fonctionnellement identiques.
- Ne modifier aucun texte ou libellé.
- Ne modifier aucun JavaScript, gestionnaire d'événement, route, rôle, permission, API, Supabase, VPS, serveur ou donnée.
- Conserver toutes les animations et tous les mouvements existants, y compris le cube 3D, les rebonds, glows et transitions.
- Ne pas modifier la géométrie des composants : tailles, espacements, positionnement, rayons, structure et disposition restent inchangés pendant cette première passe.
- Les changements de production sont interdits ; la V3 reste une branche de travail.

---

### Task 1: Ajouter la palette V3 interne scoped

**Files:**
- Modify: `dist/index.html` — uniquement la feuille CSS interne, sans changement DOM/JS.

**Interfaces:**
- Consumes: variables CSS existantes (`--primary`, `--bg`, `--bg-card`, `--border`, `--text`, `--success`, `--warning`, `--error`, `--info`, `--role-accent`).
- Produces: palette V3 héritée uniquement par `.app` et ses descendants.

- [ ] **Step 1: Capturer les invariants avant modification**

Vérifier sur `backup-frontend-avant-v3-2026-08-15` et `prototype-v3-ui` que `dist/index.html` est identique avant la passe visuelle, hors documents de spécification/plan.

- [ ] **Step 2: Ajouter les variables de palette scoped**

Ajouter avant la fin de la feuille CSS, sans toucher aux sélecteurs de login :

```css
/* SCHOOLSAFE V3 — harmonisation couleurs interne uniquement */
.app {
  --primary:#315fce;
  --primary-dark:#244aa6;
  --primary-light:#e9effc;
  --bg:#f4f6fb;
  --bg-card:#ffffff;
  --bg-card-2:#f8faff;
  --bg-secondary:#f6f8fc;
  --border:#dfe5f1;
  --border-light:#e9edf5;
  --text:#17213a;
  --text-secondary:#5e687d;
  --text-muted:#929caf;
  --navy:#101d42;
  --navy-light:#1d3268;
  --gold:#d6a43a;
  --gold-light:#f4e3b7;
  --success:#178a62;
  --success-bg:#e2f5ed;
  --success-border:#a7dfca;
  --warning:#b87518;
  --warning-bg:#fbedd7;
  --warning-border:#efcc8b;
  --error:#cf4055;
  --error-bg:#fbe7ea;
  --error-border:#efb2bc;
  --info:#315fce;
  --info-bg:#e9effc;
  --info-border:#afc1ed;
}

body[data-role="direction"] .app  { --role-accent:#315fce; --role-accent-light:#e9effc; }
body[data-role="direction2"] .app { --role-accent:#5b68c9; --role-accent-light:#eeeffc; }
body[data-role="direction3"] .app { --role-accent:#178a62; --role-accent-light:#e2f5ed; }
body[data-role="enseignant"] .app { --role-accent:#258b79; --role-accent-light:#e2f3f0; }
body[data-role="gardien"] .app    { --role-accent:#d8753d; --role-accent-light:#faece3; }
body[data-role="parent"] .app     { --role-accent:#8058b8; --role-accent-light:#f0eafa; }
```

- [ ] **Step 3: Harmoniser uniquement les surfaces internes**

Utiliser des règles scoped `.app ...` pour aligner la sidebar, la topbar, la bottom-nav, les cartes et les sections sur la palette héritée. Aucun `transform`, `animation`, `transition`, `width`, `height`, `padding`, `margin`, `display`, `position`, `grid`, `flex` ou `border-radius` nouveau/modifié dans cette passe.

- [ ] **Step 4: Vérifier que la zone protégée n'est pas ciblée**

Rechercher dans les nouvelles règles toute occurrence de :

```text
.splash-screen
.login-screen
.login-container
.login-bg
LH_IMG
login-kid
_GUARDIAN_VIDEOS
```

Résultat attendu : aucune nouvelle règle V3 ne cible ces éléments.

- [ ] **Step 5: Commit**

```bash
git add dist/index.html
git commit -m "style: harmoniser palette interne SchoolSafe V3"
```

### Task 2: Vérifier les invariants fonctionnels et visuels protégés

**Files:**
- Read/compare: `dist/index.html`
- Test: outils `tools/audits.mjs`, `tools/audit-charte.mjs`, `tools/audit-contraste-site.mjs` si applicables au fichier.

**Interfaces:**
- Consumes: résultat de Task 1.
- Produces: preuve que la passe V3 est limitée à la couleur de l'interface interne.

- [ ] **Step 1: Comparer la branche V3 à la sauvegarde**

Comparer `backup-frontend-avant-v3-2026-08-15...prototype-v3-ui` et confirmer que les seuls changements applicatifs sont dans la CSS de `dist/index.html`.

- [ ] **Step 2: Contrôler les marqueurs protégés**

Comparer les blocs splash/login, la liste `_LH_PHOTOS`, `_DBG_PHOTOS`, le cube et `window.NAV` entre la sauvegarde et V3. Résultat attendu : identiques.

- [ ] **Step 3: Exécuter les audits disponibles**

```bash
npm run audit
npm run audit:charte
npm run audit:contraste
```

Résultat attendu : aucun nouvel échec imputable à la couche V3.

- [ ] **Step 4: Vérifier le diff final**

Le diff ne doit contenir aucun fichier sous `supabase/`, aucun workflow, aucune configuration serveur et aucun JavaScript fonctionnel modifié.

- [ ] **Step 5: Commit des éventuels ajustements CSS de contraste uniquement**

```bash
git add dist/index.html
git commit -m "style: ajuster contrastes palette SchoolSafe V3"
```

### Task 3: Préparer la revue visuelle sans fusion

**Files:**
- No production file creation required.

**Interfaces:**
- Consumes: branche V3 auditée.
- Produces: branche prête à être prévisualisée/comparée, sans fusion dans `main`.

- [ ] **Step 1: Confirmer que `main` et la sauvegarde n'ont pas bougé**

Comparer leurs têtes avec l'état enregistré avant V3.

- [ ] **Step 2: Présenter le résultat pour validation visuelle**

Montrer la branche `prototype-v3-ui` comme seule candidate. Ne pas fusionner, ne pas déployer et ne pas toucher à `main` avant validation explicite de l'utilisateur.
