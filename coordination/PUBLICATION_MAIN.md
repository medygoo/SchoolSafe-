# Règle obligatoire — intégration et publication finale sur `main`

**Décision de Loms / PRODELI — 3 août 2026**

Ce document est la règle de travail commune entre Loms, Claude et ChatGPT pour
`medygoo/SchoolSafe-`. En cas de contradiction avec une ancienne note, **ce
document prévaut**. Loms reste le propriétaire, le décideur métier et la seule
personne qui autorise la mise en production.

---

## 1. Responsable unique de la publication finale

**Claude est l'unique responsable de l'intégration finale, de la fusion des
travaux validés vers `main` et de la publication de la version finale.**

Claude :

- traite les bugs de l'application et du site dans son périmètre ;
- intègre les corrections frontend et les contrats techniques fournis ;
- récupère les Pull Requests et livraisons validées de ChatGPT ;
- résout les conflits d'intégration sans supprimer un travail validé ;
- exécute les tests finaux ;
- demande l'autorisation de Loms avant la mise en production ;
- fusionne les Pull Requests validées dans `main` ;
- contrôle le déploiement GitHub Pages et le fonctionnement final ;
- documente la version publiée et la procédure de retour arrière.

**ChatGPT ne fusionne pas et ne publie pas la version finale sur `main`.**
ChatGPT prépare, vérifie et remet ses travaux à Claude par branche et Pull
Request.

---

## 2. Répartition des responsabilités

| Domaine | Responsable principal |
|---|---|
| Besoins, règles métier, validation et autorisation de production | **Loms** |
| Bugs, interface, UX, responsive, PWA, site, domaine, intégration finale | **Claude** |
| Supabase, schéma, migrations, RLS, Auth, R2, sécurité, contrats API | **ChatGPT** |
| Fusion finale, publication de `main`, contrôle du déploiement | **Claude** |

Quand un bug touche plusieurs domaines :

1. Claude décrit le symptôme et l'impact dans GitHub.
2. ChatGPT fournit le contrat ou la correction backend nécessaire sur une
   branche dédiée.
3. Claude intègre le résultat, exécute les tests complets et prépare la
   publication finale.
4. Loms autorise la mise en production.
5. Claude fusionne et publie `main`.
6. **Claude vérifie que la publication a RÉUSSI, et le dit.**

---

## 2 bis. Fusionner n'est pas publier — la leçon du 4 août 2026

**Ce qui s'est passé.** Pendant plusieurs heures, chaque fusion dans `main` a
été suivie d'un échec de publication. Le contrôle avant publication exigeait
*exactement* 144 fichiers dans `dist` ; il y en avait 164 — des images, rien
d'autre.

```
17h30  ✗  P0-2, le visa de la Direction
17h27  ✗  P0-3, les codes d'erreur des paiements
17h22  ✗  P0-7, le schéma de la base
16h41  ✗  l'écran de connexion corrigé
16h09  ✗  les préinscriptions
15h54  ✗  …et toutes les précédentes
```

**Tout était dans `main`, et rien n'atteignait l'école.** Loms a demandé
pourquoi ses corrections n'étaient pas en ligne : elles l'étaient dans le
dépôt, jamais chez lui.

**Trois conclusions, et elles sont pour Claude.**

1. **« Contrôler le déploiement » est une étape, pas une intention.** Elle est
   au §1 depuis le 3 août. Elle n'a pas été faite après chaque fusion, et c'est
   le seul manquement qui explique tout le reste.
2. **Une croix rouge que personne n'ouvre est un échec silencieux.** C'est
   exactement ce que nos audits traquent partout ailleurs. La chaîne de
   publication le commettait elle-même. Un échec de publication **ouvre
   désormais une issue** dans le canal que les deux agents lisent avant chaque
   intervention, et cette issue se referme seule au retour à la normale.
3. **Un contrôle qui compte les fichiers un par un finit toujours par mentir.**
   Il exprimait un nombre au lieu d'exprimer une intention : *l'artefact n'est
   pas vide, et il ne contient rien qui doive rester privé.* C'est ce qu'il
   vérifie maintenant.

**Et un point de fait, sans reproche :** les branches `agent/schema-reference-p07`,
`agent/payment-error-codes-p03` et `agent/settings-signature-rls-p02` sont
entrées dans `main` sans passer par l'intégration de Claude. Leur contenu est
bon — il est déjà exploité, et il a permis de trouver 25 écarts entre le code et
la base le jour même. Ce n'est donc pas le travail qui est en cause : c'est que
**personne n'a regardé si la publication avait suivi**, et c'est précisément la
raison pour laquelle le §1 confie cette étape à une seule personne.

---

## 3. Canal de communication obligatoire

GitHub est le canal partagé obligatoire : branches, Pull Requests, commentaires,
`coordination/` et `docs/`.

Avant toute nouvelle intervention, chacun doit :

1. lire les dernières branches et Pull Requests de l'autre ;
2. lire les consignes présentes dans `coordination/` ;
3. continuer à partir du travail existant ;
4. déposer son résultat et ses questions dans GitHub.

**Tout travail déjà réalisé par Claude ou ChatGPT est considéré comme demandé
par Loms.** Il ne doit pas être annulé, recommencé ou remplacé sans une décision
expresse de Loms. On signale uniquement les incompatibilités concrètes qui
empêchent l'intégration ou compromettent la sécurité.

---

## 4. Travail sur les branches

- Aucun travail ordinaire ne commence directement sur `main`.
- Chaque tâche utilise une branche dédiée et une Pull Request.
- Les Pull Requests restent en brouillon pendant le développement et les tests.
- ChatGPT remet ses travaux à Claude avec un compte rendu complet.
- Claude est le seul intégrateur final vers `main`.
- Une poussée directe sur `main` n'est permise qu'en urgence et avec une
  autorisation explicite de Loms ; elle doit être documentée immédiatement.

Nommage recommandé :

```text
claude/...        bugs, frontend, site, intégration
backend/...       Supabase et contrats
security/...      RLS, Auth, scanner, permissions
fix/...           correction isolée
release/...       préparation de la publication finale par Claude
```

---

## 5. Compte rendu obligatoire de chaque livraison

Chaque Pull Request doit préciser :

```text
TÂCHE :
BRANCHE :
PULL REQUEST :
COMMITS :
RESPONSABLE :

1. Résultat livré
2. Fichiers et services modifiés
3. Impact Supabase / RLS / Auth / R2 / PWA / domaine
4. Tests exécutés et résultats
5. Risques ou limites
6. Procédure de retour arrière
7. Travail attendu de Claude pour l'intégration finale
8. Décision attendue de Loms
```

Aucun résultat n'est présenté comme « terminé » tant que Claude n'a pas vérifié
l'intégration complète et que Loms n'a pas autorisé la publication.

---

## 6. Règles de sécurité qui restent obligatoires

- Ne jamais désactiver RLS pour contourner une erreur.
- Ne jamais mettre de secret dans GitHub.
- Ne jamais utiliser de données réelles d'élèves, parents ou paiements dans les
  tests publics.
- Ne jamais calculer le solde financier uniquement dans le navigateur.
- Ne jamais modifier une table, une fonction, une migration ou une politique RLS
  sans documentation et coordination.
- Respecter strictement les droits par rôle, notamment : aucune information
  financière pour Direction 2 et aucun montant pour le Gardien.
- Toute modification du service worker, du cache PWA, de Supabase Auth, de R2 ou
  du domaine doit être annoncée avant l'intégration finale.

---

## 7. Procédure de publication finale par Claude

Avant la fusion vers `main`, Claude vérifie :

1. toutes les Pull Requests nécessaires sont à jour avec la base retenue ;
2. les conflits sont résolus sans perdre un travail validé ;
3. les tests frontend, backend, rôles, scanner, Auth, R2 et PWA sont réussis ;
4. aucun secret ou fichier de test ne part en production ;
5. la procédure de retour arrière est disponible ;
6. Loms a donné son autorisation explicite.

Après l'autorisation :

1. Claude fusionne les Pull Requests validées ;
2. Claude publie la version finale sur `main` ;
3. Claude contrôle le déploiement ;
4. Claude vérifie le site, l'application, la connexion, le scanner et les rôles ;
5. Claude écrit le compte rendu final dans GitHub ;
6. en cas d'échec, Claude applique le retour arrière documenté et informe Loms.

---

## 8. Autorité finale

- Loms décide du besoin et autorise la production.
- ChatGPT garantit les contrats backend et la sécurité dans son périmètre.
- Claude garantit l'intégration, traite les bugs applicatifs et publie la version
  finale sur `main`.
- En cas de divergence, la décision écrite de Loms prévaut immédiatement.
