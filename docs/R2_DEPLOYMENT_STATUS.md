# R2 deployment status

Date : 2026-08-03

## Fonctions actives

### `r2-upload`

- Version : 1
- Statut : ACTIVE
- JWT : obligatoire
- Usage : tous les nouveaux envois de JPEG, PNG, WebP et PDF
- Source maximale : 8 Mo
- Fichier final R2 : 5 Mo maximum
- Image maximale : 12 000 px par côté et 40 mégapixels
- Images : orientation, retrait de métadonnées sensibles, redimensionnement et WebP lorsque le résultat économise le stockage
- PDF : transmis sans conversion

### `r2-files`

- Version : 5
- Statut : ACTIVE
- JWT : obligatoire
- Usage frontend : liste, lecture temporaire, suppression auditée
- Usage interne : permissions SchoolSafe, validation du propriétaire et écriture R2
- Année scolaire fournie par le serveur

### `r2-archives`

- Version : 1
- Statut : ACTIVE
- JWT : obligatoire
- Accès : Direction 1 uniquement
- Usage : résumé par année, liste, ouverture, archivage et restauration

### Endpoints retirés du circuit

- `r2-upload-test` version 2 : répond `410`, JWT obligatoire
- `r2-compression-self-test` version 2 : répond `410`, JWT obligatoire

## Migrations R2 appliquées

- `20260803062940_harden_r2_files_and_link_receipts`
- `20260803064521_add_teacher_preparation_and_administrative_documents_r2`
- `20260803065147_optimize_administrative_documents_and_cahier_prep_rls`
- `20260803075027_secure_r2_access_and_school_year`
- `20260803075840_normalize_student_access_flags`
- `20260803081937_add_secure_archive_workflow`
- `20260803082004_add_archive_summary_rpc`
- `20260803082028_lock_archive_rpc_execution`
- `20260803083125_index_archive_audit_foreign_keys`
- `20260803083433_enforce_school_file_archive_audit`
- `20260803090930_add_r2_image_optimization_metrics`

Les sources portent les mêmes versions dans `supabase/migrations/` sur la branche de travail.

## Métriques de compression enregistrées

`school_files` conserve maintenant :

- nom, type et taille du fichier source ;
- largeur et hauteur source ;
- largeur et hauteur finales ;
- profil et qualité de compression ;
- indicateur `optimized` ;
- version du traitement ;
- économie calculée en octets ;
- économie calculée en pourcentage.

## Profils actifs

| Profil | Dimension maximale | Qualité initiale |
|---|---:|---:|
| photo | 1280 px | 76 |
| identité | 1600 px | 80 |
| carte | 1800 px | 84 |
| document photographié | 2400 px | 84 |

Une image déjà efficace est conservée dans son format initial lorsque la conversion WebP n’économise pas au moins 2 %. Une image source supérieure à 5 Mo doit être réduite sous 5 Mo pour être acceptée.

## Capacités générales actives

- reçus liés aux transactions confirmées ;
- idempotence et reprise ;
- séparation Direction 1 / Direction 2 / Caisse ;
- liste blanche Parent ;
- interdiction des finances pour l’Enseignant ;
- aucun accès direct R2 pour le Gardien ;
- validation du propriétaire et de la catégorie ;
- année scolaire résolue côté serveur ;
- contrôle binaire JPEG, PNG, WebP et PDF ;
- compression automatique avant R2 ;
- archivage et restauration audités ;
- dossiers administratifs et cahiers avec plusieurs pièces ;
- URLs signées valables 300 secondes.

## Tests effectués

### Connexion R2

- PUT : réussi ;
- GET : réussi ;
- contenu et taille : identiques ;
- liste : réussie ;
- suppression : réussie.

### Compression réelle

Une image PNG synthétique de 256 × 256 et 568 octets a été traitée :

- sortie : WebP 128 × 128 ;
- taille finale : 116 octets ;
- économie : 452 octets ;
- réduction : 79,58 % ;
- envoi R2 : réussi ;
- relecture et comparaison : réussies ;
- objet supprimé après test : oui.

Ce taux est une preuve de fonctionnement, pas une garantie pour toutes les images.

### Base de données

- colonnes générées testées : 1000 octets source → 400 octets final → 600 octets et 60,00 % d’économie ;
- test exécuté dans une transaction avec `ROLLBACK` ;
- aucune fausse donnée conservée.

### Sécurité

- `r2-upload` sans JWT : HTTP 401 ;
- aucune nouvelle alerte de sécurité liée à la compression ;
- les anciennes alertes scanner `SECURITY DEFINER` et la protection des mots de passe compromis restent à traiter.

## Code versionné

- `supabase/functions/r2-upload/index.ts`
- `supabase/functions/r2-upload/deno.json`
- `supabase/migrations/20260803090930_add_r2_image_optimization_metrics.sql`
- `docs/R2_IMAGE_OPTIMIZATION_API.md`
- `docs/R2_STORAGE_API.md`

## État des données

- zéro fichier réel dans `school_files` au contrôle final de l’étape ;
- zéro document administratif réel ;
- zéro préparation réelle ;
- zéro archive réelle ;
- aucun objet de test R2 conservé.

## Restant

- tests authentifiés avec Direction 1, Direction 2, Caisse, Enseignant, Parent et Gardien ;
- interdire techniquement l’upload direct d’images vers `r2-files` après intégration frontend de `r2-upload` ;
- clôture et archivage annuel automatique ;
- inventaire annuel exportable ;
- réconciliation R2 ↔ `school_files` ;
- sauvegarde Backblaze B2 ;
- correction des anciennes fonctions scanner `SECURITY DEFINER` ;
- activation de la protection contre les mots de passe compromis.
