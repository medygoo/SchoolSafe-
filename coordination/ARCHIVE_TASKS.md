# SchoolSafe — Tâches permanentes des archives

Date : 2026-08-03

Ce fichier complète `coordination/TASKS.md` et doit être lu avant toute intégration frontend des archives.

## Travail Claude — écran Archives Direction 1

- [ ] Ajouter une rubrique « Archives » visible uniquement dans Direction 1.
- [ ] Ne jamais afficher cette rubrique à Direction 2, Caisse, Enseignant, Parent ou Gardien.
- [ ] Créer un client frontend pour la fonction Supabase `r2-archives` avec le JWT de la session.
- [ ] Utiliser l’action `summary` pour afficher le nombre de fichiers et la taille totale par année.
- [ ] Utiliser l’action `list` avec pagination.
- [ ] Ajouter les filtres : année scolaire, type de propriétaire, catégorie et propriétaire précis.
- [ ] Afficher le nom lisible, le type, la taille, l’année, la date d’archivage et l’auteur de l’archivage.
- [ ] Ouvrir une archive avec l’action `download` et ne jamais conserver l’URL signée.
- [ ] Ajouter une confirmation avant toute restauration.
- [ ] Restaurer un fichier individuel avec l’action `restore` uniquement lorsque son dossier parent n’est pas archivé.
- [ ] Pour un dossier administratif archivé, utiliser uniquement `restore_administrative_document(p_document_id)` afin de restaurer toutes les pages ensemble.
- [ ] Archiver un dossier administratif avec `archive_administrative_document(p_document_id)`.
- [ ] Ne jamais modifier directement `archived_at`, `archived_by`, `restored_at` ou `restored_by` depuis le navigateur.
- [ ] Ne jamais supprimer physiquement un objet R2 depuis l’écran Archives.
- [ ] Afficher un état vide lorsque l’année ne contient aucune archive.
- [ ] Gérer chargement, erreur, session expirée, réponse 401, réponse 403 et réponse 409.
- [ ] Prévoir un affichage mobile Android avec pagination claire.

## Backend ChatGPT — terminé

- [x] Ajout de l’audit `archived_by`, `restored_at` et `restored_by`.
- [x] Synchronisation transactionnelle dossier administratif ↔ pièces jointes.
- [x] Création de `restore_administrative_document(p_document_id)`.
- [x] Blocage de la modification directe d’un dossier archivé.
- [x] Suppression des droits directs INSERT/UPDATE/DELETE des utilisateurs authentifiés sur `school_files`.
- [x] Correction de l’année par défaut des documents administratifs avec `settings.year`.
- [x] Création de `get_archive_summary()`.
- [x] Déploiement de `r2-archives` version 1 avec JWT obligatoire.
- [x] Liste paginée et filtrée des archives.
- [x] Téléchargement temporaire des archives.
- [x] Archivage et restauration individuels audités.
- [x] Interdiction de restaurer une seule page d’un dossier administratif encore archivé.
- [x] Code et migrations enregistrés dans GitHub.

## Backend ChatGPT — restant pour les archives

- [ ] Définir la clôture complète d’une année scolaire.
- [ ] Créer l’archivage annuel automatique après validation Direction 1.
- [ ] Ajouter l’inventaire annuel exportable.
- [ ] Ajouter la réconciliation R2 ↔ `school_files`.
- [ ] Ajouter la copie secondaire Backblaze B2.
- [ ] Effectuer les tests avec une vraie session Direction 1 dès que l’écran frontend appelle le service.
