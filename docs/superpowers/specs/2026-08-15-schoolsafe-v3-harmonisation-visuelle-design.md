# SchoolSafe V3 — Harmonisation visuelle uniquement

Date : 2026-08-15
Branche de travail : `prototype-v3-ui`
Sauvegarde de référence : `backup-frontend-avant-v3-2026-08-15`
Base protégée : `main`

## Objectif

Créer une version V3 visuellement plus harmonieuse de SchoolSafe, en travaillant uniquement sur les couleurs et la cohérence graphique des écrans internes déjà existants.

## Règle absolue

Le fonctionnement existant ne doit pas être reconstruit ni modifié.

Doivent rester strictement inchangés :
- les fonctionnalités ;
- les textes et libellés ;
- les routes et destinations ;
- les rôles et leurs parcours ;
- les boutons et leurs actions ;
- les mouvements et animations existants ;
- les cubes animés ;
- les interactions ;
- les écrans de sécurité ;
- toute logique JavaScript ;
- les appels API ;
- Supabase ;
- le VPS ;
- le serveur ;
- les permissions ;
- l'authentification ;
- toute donnée ou logique métier.

## Zone totalement protégée

Les premiers écrans doivent rester visuellement et fonctionnellement identiques :
- écran d'ouverture / splash ;
- photographies et rotations de photos ;
- écran de connexion ;
- page où l'utilisateur saisit son code et son mot de passe ;
- logo, animations et effets présents sur ces écrans.

Aucun changement de couleur, disposition, photo, animation, texte ou comportement n'est autorisé sur cette zone.

## Zone V3 autorisée

Le travail commence seulement après la connexion, dans l'interface interne `.app`.

Modifications autorisées :
- harmoniser la palette des écrans internes ;
- uniformiser les couleurs de fond, cartes, bordures, états et accents ;
- rendre les couleurs par rôle plus cohérentes entre elles ;
- harmoniser la sidebar, la topbar, la bottom navigation et les cartes sans changer leur structure ;
- conserver les couleurs sémantiques des états (succès, attente, erreur, information) ;
- réduire les conflits visuels entre les différentes générations de styles déjà présentes, uniquement par des règles CSS ciblées.

## Méthode technique prévue

1. Ne travailler que sur `prototype-v3-ui`.
2. Ne jamais modifier `main` pendant la phase V3.
3. Ne jamais modifier la branche `backup-frontend-avant-v3-2026-08-15`.
4. Limiter la première passe à des règles CSS ciblées sur `.app` et ses descendants.
5. Ne pas toucher au DOM, aux textes, au JavaScript ni aux gestionnaires d'événements.
6. Ne pas supprimer les animations existantes, y compris le cube, les rebonds, glows, transitions et mouvements.
7. Ne pas modifier les sélecteurs `.splash-screen`, `.login-screen`, `.login-container`, `.login-bg`, les photos de connexion ou leurs scripts.
8. Faire des changements visuels réversibles et faciles à comparer avec la sauvegarde.

## Direction visuelle validée

La V3 doit reprendre l'idée validée issue des prototypes 1 et 2, mais uniquement sous forme de palette et d'harmonisation :
- bleu/navy SchoolSafe comme base commune ;
- accents de domaine/rôle cohérents ;
- couleurs sémantiques réservées aux statuts ;
- fonds et cartes plus homogènes ;
- contraste lisible sur ordinateur, tablette et téléphone ;
- aucun changement de structure ou de contenu.

## Critères d'acceptation

La V3 est conforme seulement si :
- l'écran de connexion est pixel-visuellement inchangé ;
- les photos sont inchangées ;
- le code/mot de passe se saisit exactement comme avant ;
- les cubes et animations bougent exactement comme avant ;
- les textes sont identiques ;
- les fonctionnalités donnent les mêmes résultats ;
- les rôles voient les mêmes menus et actions ;
- seules les couleurs/cohérences graphiques des écrans internes changent ;
- aucune modification backend, sécurité, serveur ou base de données n'existe dans le diff.

## Vérification avant validation

Avant toute fusion éventuelle, comparer `prototype-v3-ui` à `backup-frontend-avant-v3-2026-08-15` et confirmer :
- aucun changement JavaScript intentionnel ;
- aucun changement de texte ou de structure HTML intentionnel ;
- aucun changement dans `supabase/` ;
- aucun changement de configuration serveur ;
- aucun changement de workflow de sécurité ;
- modifications limitées à l'harmonisation visuelle frontend interne.
