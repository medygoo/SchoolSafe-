# SchoolSafe — audit global chirurgical de l’application

**Date de contrôle : 4 août 2026**  
**Projet Supabase actif :** `lcnronymkccgyltttqry`  
**Branche Claude :** `claude/new-session-guwhgl`  
**Branche backend :** `agent/payment-control-backend-v1`  
**Responsabilité publication :** Claude après recette et autorisation de Loms

## 1. Verdict exécutif

SchoolSafe n’est plus une maquette vide : le monolithe contient les écrans des six rôles, les fonctions métier principales, les contrats Supabase, le stockage privé R2, les paiements partiels, le scanner, les documents et l’authentification par invitation.

Cependant, la version n’est pas encore prête à être considérée comme une production scolaire sûre. Les principaux blocages sont désormais l’intégration des deux branches, la recette multi-rôles avec de vraies données d’essai, la visibilité des erreurs d’écriture, le durcissement des annuaires scanner, la finition du parcours d’invitation, la contrepassation côté interface, la sécurité PWA/CDN et l’absence de tests dans le workflow de publication.

Estimation raisonnée de maturité :

| Domaine | Maturité estimée |
|---|---:|
| Contrats backend et stockage | 84 % |
| Intégration fonctionnelle frontend | 73 % |
| Sécurité et confidentialité opérationnelles | 58 % |
| Tests, recette et capacité de publication | 40 % |
| Préparation globale à la production | environ 62 % |

Ces pourcentages ne sont pas des mesures automatisées. Ils représentent l’avancement observé et le poids des risques restant avant une rentrée réelle.

## 2. État des branches et risque de fusion

Les deux PR sont ouvertes, fusionnables et encore en brouillon :

- PR Claude : 21 commits, 34 fichiers changés ;
- PR backend : 72 commits, 42 fichiers changés.

Les deux branches sont en retard d’un commit sur `main`. Le commit déjà présent sur `main` fiabilise les profils, les comptes Auth et les élèves. Les branches doivent être rebasées avant toute fusion afin de ne pas perdre ce durcissement.

Ordre recommandé :

1. sauvegarde de l’état des deux branches ;
2. rebase de Claude sur le `main` actuel ;
3. intégration contrôlée des migrations, fonctions et contrats backend ;
4. résolution des conflits sans écraser les correctifs Auth ;
5. recette complète ;
6. publication par Claude seulement après autorisation de Loms.

## 3. État réel des données et de la base

Contrôle direct de la base active :

- 61 tables publiques ;
- RLS activée sur les 61 tables ;
- 1 utilisateur Auth relié à 1 profil applicatif ;
- 1 classe ;
- 0 élève ;
- 0 enseignant ;
- 0 parent ;
- 0 fichier R2 référencé dans `school_files` ;
- 0 obligation financière ;
- 0 transaction de paiement ;
- 0 invitation en attente ;
- 0 ligne identifiée comme donnée de test résiduelle.

Conséquence : l’absence de données parasites est positive, mais l’application n’est pas encore validée sur son usage réel. Une base presque vide ne déclenche pas les défauts qui apparaissent seulement lorsqu’il existe des classes, des enfants, des cotes, des paiements, des documents ou plusieurs parents.

## 4. Ce qui est terminé ou suffisamment solide

### 4.1 Pages blanches connues

Claude a corrigé les quatre erreurs de portée qui rendaient blancs :

- l’accueil Parent ;
- les devoirs du Parent ;
- l’accueil Direction 2 ;
- l’export d’état financier.

### 4.2 Chargement par rôle

Le chargement unique des 47 tables pour tous les rôles a été remplacé par une matrice de sources par rôle et des états de lecture explicites. C’est une amélioration majeure pour la confidentialité et les performances.

### 4.3 Scanner et confidentialité financière

Le Gardien reçoit un message générique d’orientation, sans montant, devise ou trimestre. Direction 2 ne doit plus recevoir de notification financière. Les refus sont enregistrés comme incidents et non comme arrivées normales.

### 4.4 Paiements serveur

Le backend gère :

- obligations financières ;
- versements partiels ;
- allocations ;
- reçus ;
- résumé Parent ;
- détail Caisse ;
- statut minimal au portail ;
- dérogations ;
- contrepassation auditée.

Le défaut qui empêchait la Caisse de lire l’année scolaire a été corrigé. Un test temporaire a confirmé un paiement de 40 USD sur 100 USD, puis sa contrepassation, avec retour du solde à 100 USD et conservation du reçu en statut `reversed`.

### 4.5 Stockage R2

Les fonctions de production actives sont :

- `r2-upload` v4 ;
- `r2-files` v5 ;
- `r2-archives` v1 ;
- `invite-school-account`.

Les fonctions R2 de production utilisent un JWT, les URLs de lecture sont temporaires, les images sont contrôlées et compressées, et les archives sont limitées à Direction 1.

### 4.6 Persistance des profils

Les contrats existent pour :

- `save_student_profile` ;
- `save_school_user_profile` ;
- `invite-school-account`.

Ils empêchent le navigateur de fournir `auth_user_id`, un mot de passe, une clé serveur ou une photo base64.

### 4.7 Documents

Claude a intégré une première famille de documents officiels : bulletins, palmarès, reçus, attestations et certificats. Les documents administratifs et les pièces R2 ont également un contrat backend.

## 5. Blocages P0 avant production

### P0-1 — Rebase et intégration des branches

Aucune publication ne doit être faite avant rebase et fusion contrôlée. Les deux branches divergent de `main`.

**Responsable principal : Claude.**  
**Contrôle : ChatGPT.**

### P0-2 — Parcours d’invitation de compte incomplet côté interface

Le serveur d’invitation est prêt, mais il faut tester dans le navigateur :

1. création de la fiche ;
2. réponse `requires_invitation` ;
3. appel de l’Edge Function ;
4. réception du courriel ;
5. choix du mot de passe ;
6. redirection correcte ;
7. liaison `auth.users` ↔ `profiles` ↔ `users` ;
8. connexion avec le rôle attendu ;
9. invitation expirée, doublon, erreur et renvoi.

**Responsable : Claude pour l’interface ; ChatGPT pour le contrat, la redirection et les contrôles Supabase.**

### P0-3 — Contrepassation non raccordée côté Caisse

Claude doit remplacer toute modification directe de `payment_transactions` par :

```text
reverse_payment_transaction(p_transaction_id, p_reason)
```

Après succès, l’interface doit recharger le résumé serveur, garder le reçu visible en `reversed` et ne jamais recalculer le solde localement.

**Responsable : Claude.**

### P0-4 — Sources Parent incompatibles avec les RLS

Le Parent peut lire les matières de la classe de son enfant, mais ne peut actuellement pas lire :

- `timetables` ;
- `cahier_texte` ;
- l’annuaire des enseignants dans `users`.

La solution immédiate sûre est de masquer les modules non raccordés et de ne pas afficher un faux nom d’enseignant. Un futur contrat backend ciblé pourra être ajouté après définition précise du besoin.

**Responsable immédiat : Claude.**  
**Contrat futur : ChatGPT.**

### P0-5 — Annuaire scanner trop large

`private.can_scan()` autorise Direction 1, Direction 2, Caisse, Enseignant et Gardien. `get_scanner_students()` renvoie notamment le nom et le téléphone du tuteur principal ; `get_scanner_aps()` renvoie les téléphones des personnes autorisées.

Le droit de scanner ne doit pas automatiquement donner le droit de télécharger l’annuaire complet. Il faut séparer :

- la résolution minimale d’un QR ;
- le statut d’accès ;
- l’annuaire de secours du Gardien ;
- les données de contact, accessibles uniquement aux rôles réellement autorisés.

**Responsable : ChatGPT.**

### P0-6 — Écritures encore insuffisamment confirmées

Le plan de Claude avait identifié 215 écritures dont l’échec était invisible. Les profils Élève et Utilisateur sont mieux sécurisés, mais toutes les autres mutations ne sont pas encore démontrées comme corrigées.

Chaque bouton doit :

1. attendre la réponse serveur ;
2. afficher le message réel ;
3. garder le formulaire ouvert en cas d’échec ;
4. distinguer « mis en file hors ligne » de « enregistré » ;
5. interdire les confirmations optimistes mensongères.

**Responsable : Claude.**

### P0-7 — Pas de jeu de recette réaliste

Il faut un environnement de recette avec au minimum :

- les six rôles ;
- plusieurs classes ;
- enseignants affectés à une ou plusieurs classes ;
- parents avec un ou plusieurs enfants ;
- élèves sans parent, avec parent et avec personne autorisée ;
- notes, devoirs, présences, incidents ;
- frais payés, partiels, impayés et contrepassés ;
- documents et images ;
- archives actives et vides.

Puis un second test de charge avec environ 350 élèves.

**Responsabilité conjointe.**

### P0-8 — Le workflow GitHub Pages ne lance pas les audits

Le workflow actuel vérifie seulement :

- exactement 144 fichiers dans `dist` ;
- présence de `auth.html` ;
- absence de quelques fichiers interdits ;
- déploiement GitHub Pages.

Il ne lance pas :

- `npm ci` ;
- `npm run audit` ;
- les tests par rôle ;
- un test de connexion Supabase ;
- un test du site public ;
- un test PWA.

Une régression peut donc être publiée si le nombre de fichiers reste correct.

**Responsable : Claude, avec critères de sécurité validés par ChatGPT.**

### P0-9 — Sécurité frontend/PWA à prouver

L’audit initial avait signalé :

- absence de CSP ;
- scripts CDN sans `integrity` ;
- scripts externes mis en cache par le service worker ;
- échappement incomplet des guillemets et apostrophes ;
- handlers inline ;
- mutations sans contrôle de rôle.

Ces éléments ne sont pas démontrés comme tous corrigés dans la dernière branche. Ils doivent être revérifiés sur le fichier final, puis bloquer la publication si nécessaire.

**Responsable : Claude.**

### P0-10 — Nettoyage des fonctions de diagnostic

La base expose 19 Edge Functions actives, dont 4 fonctions de production et 15 fonctions de test ou diagnostic. Les fonctions inspectées répondent `410 Disabled` et exigent un JWT, mais elles doivent être retirées avant production pour réduire la surface d’attaque et éviter les erreurs opérationnelles.

**Responsable : ChatGPT.**

### P0-11 — Protection des mots de passe compromis

Le conseiller sécurité Supabase confirme que la protection contre les mots de passe compromis est désactivée.

**Responsable : ChatGPT, avec éventuelle action dans le tableau de bord Supabase.**

### P0-12 — Domaine, URL de retour et CORS finaux

Avant publication, vérifier ensemble :

- domaine public final ;
- URL de l’application ;
- `PUBLIC_APP_URL` ;
- URL de redirection d’invitation ;
- CORS R2 et invitation ;
- SSL ;
- redirections `www` / sans `www` ;
- bouton du site vers l’application.

**Responsable : ChatGPT pour le domaine et l’infrastructure ; Claude pour les liens et le frontend.**

## 6. Travaux P1 importants

### Backend / ChatGPT

1. Auditer manuellement les RPC `SECURITY DEFINER` signalées par Supabase ; ne pas révoquer aveuglément les fonctions légitimes.
2. Restreindre les annuaires scanner et personnes autorisées.
3. Ajouter les index manquants sur les clés étrangères financières : agents ayant accordé/révoqué une exception, agents de paiement, agents de contrepassation, type de frais, etc.
4. Optimiser les politiques RLS qui réévaluent les fonctions Auth ligne par ligne.
5. Consolider les politiques permissives redondantes sans casser les droits métier.
6. Concevoir l’inventaire annuel exportable, la réconciliation R2 ↔ `school_files` et la clôture annuelle.
7. Mettre en place la copie secondaire Backblaze B2.
8. Définir la durée de validité hors ligne d’un statut financier/scanner et l’état « contrôle manuel requis ».
9. Préparer un script de sauvegarde, un contrôle d’intégrité et une procédure de restauration.

### Frontend / Claude

1. Centraliser les écritures dans une couche unique avec messages d’erreur visibles.
2. Supprimer les calculs financiers locaux comme source de vérité.
3. Finaliser les états `loading`, vide, refusé, session expirée, réseau et erreur serveur.
4. Tester les écrans de chaque rôle sur mobile, tablette et ordinateur.
5. Finaliser les documents officiels : numérotation, signatures, logos, impression A4, pagination, français/anglais et données manquantes.
6. Vérifier l’accessibilité : clavier, contraste, taille des zones tactiles, textes alternatifs et messages d’erreur.
7. Vérifier l’installation PWA, la mise à jour du service worker, la purge des anciens caches et la confidentialité des données hors ligne.
8. Supprimer le code mort et les fonctions exposées sans appelant après validation.

## 7. Travaux P2 après stabilisation

- mesurer les requêtes avec 350 élèves ;
- optimiser les index à partir de statistiques réelles ;
- ne pas supprimer les index actuellement « inutilisés » tant que la base est vide ;
- améliorer la vitesse du premier affichage ;
- ajouter supervision, alertes, journalisation des erreurs et tableau de santé ;
- améliorer la qualité visuelle et les animations après la sécurité ;
- documenter la formation Direction, Caisse, Gardien, Enseignant et Parent.

## 8. Matrice par module

| Module | État | Principal restant | Responsable |
|---|---|---|---|
| Site public | avancé | recette visuelle, liens, domaine, accessibilité | Claude + ChatGPT |
| Auth | backend prêt | parcours invitation complet | Claude + ChatGPT |
| Direction 1 | partiellement raccordé | erreurs visibles, profils, documents, archives | Claude |
| Direction 2 | confidentialité améliorée | recette réelle sans finance | Claude |
| Caisse | backend solide | contrepassation, reçus, scénarios complets | Claude |
| Enseignant | fonctionnalités présentes | portée multi-classes, écritures, fichiers | Claude |
| Parent | périmètre mieux filtré | masquer sources RLS absentes, multi-enfants | Claude |
| Gardien | sortie financière générique | annuaire minimal, hors ligne, incidents | ChatGPT + Claude |
| Scanner | RPC opérationnelles | séparation scan/annuaire/contact | ChatGPT |
| Paiements | modèle serveur solide | données réelles, interface annulation, reçus | Claude |
| R2 | production active | retrait des tests, réconciliation, B2 | ChatGPT |
| Archives | contrat prêt | interface finale, clôture annuelle | Claude + ChatGPT |
| Documents officiels | premier lot intégré | validation administrative et impression | Claude |
| PWA | existante | CSP, CDN, cache, mise à jour sûre | Claude |
| CI/CD | déploiement fonctionnel | audits et tests bloquants | Claude |
| Sauvegarde | partielle | export annuel, restauration, B2 | ChatGPT |

## 9. Plan d’exécution recommandé

### Lot 1 — Stabilisation des branches

- rebase ;
- intégration backend ;
- aucune publication.

### Lot 2 — Blocages fonctionnels

- invitation ;
- contrepassation ;
- Parent ;
- erreurs d’écriture ;
- annuaire scanner.

### Lot 3 — Sécurité

- fonctions de diagnostic ;
- protection mots de passe ;
- RPC privilégiées ;
- CSP/SRI/service worker ;
- redirections et CORS.

### Lot 4 — Recette

- jeu de données multi-rôles ;
- scénarios positifs et refus ;
- réseau coupé ;
- reprise ;
- impression ;
- mobile ;
- 350 élèves.

### Lot 5 — Publication

- sauvegarde ;
- workflow CI vert ;
- vérification du domaine ;
- validation finale de Loms ;
- fusion/publication par Claude ;
- contrôle post-publication ;
- procédure de retour arrière prête.

## 10. Critères obligatoires de « terminé »

SchoolSafe sera prêt à publier uniquement lorsque :

1. les branches sont à jour et intégrées sans perte ;
2. aucun écran ne confirme une sauvegarde refusée ;
3. chaque rôle ne reçoit que ses données ;
4. Parent et Gardien ne voient aucune donnée financière interdite ;
5. la Caisse sait enregistrer et contrepasser un paiement ;
6. les invitations créent réellement des comptes utilisables ;
7. les photos et documents passent par R2 ;
8. les fonctions de test sont retirées ;
9. les audits et tests s’exécutent dans GitHub Actions ;
10. les six rôles passent la recette ;
11. la sauvegarde et le retour arrière sont testés ;
12. Loms autorise explicitement la publication.

## 11. Limite méthodologique

L’audit présent combine :

- métadonnées et différences GitHub ;
- documents de contrats ;
- migrations versionnées ;
- inspection directe de la base active ;
- conseillers Supabase ;
- inventaire des Edge Functions ;
- résultats des tests backend déjà exécutés.

Le monolithe `dist/index.html` est très volumineux et n’a pas pu être récupéré intégralement dans l’environnement d’audit pour relancer localement tous les scripts après le dernier commit Claude. La présence des outils d’audit est vérifiée, mais leur réussite sur la tête actuelle de la branche doit encore être démontrée par une exécution CI reproductible. Cette limitation est précisément la raison pour laquelle le workflow GitHub doit lancer les audits avant publication.
