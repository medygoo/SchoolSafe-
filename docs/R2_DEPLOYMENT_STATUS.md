# R2 deployment status

Date : 2026-08-03

## Fonctions de production actives

### `r2-upload`

- Version : 4
- Statut : ACTIVE
- JWT : obligatoire
- Usage : tous les nouveaux envois de JPEG, PNG, WebP et PDF
- Source maximale : 8 Mo
- Fichier final R2 : 5 Mo maximum
- Image maximale : 12 000 px par côté et 40 mégapixels
- Images : validation binaire, décodage, orientation lorsque disponible, retrait des profils sensibles lorsque présents, redimensionnement et WebP lorsque le résultat économise le stockage
- Images réellement indécodables : rejet HTTP `415` sans création d’objet R2
- PDF : transmis sans conversion
- Métadonnées : taille et dimensions source/finales, profil, qualité, version et économie

### `r2-files`

- Version : 5
- Statut : ACTIVE
- JWT : obligatoire
- Usage frontend : liste, lecture temporaire et suppression auditée
- Usage interne : permissions SchoolSafe, validation du propriétaire et écriture R2
- Année scolaire fournie par le serveur

### `r2-archives`

- Version : 1
- Statut : ACTIVE
- JWT : obligatoire
- Accès : Direction 1 uniquement
- Usage : résumé par année, liste, ouverture, archivage et restauration

## Endpoints de test retirés du circuit

Les fonctions suivantes exigent maintenant un JWT et répondent uniquement `410 Disabled` :

- `r2-upload-test`
- `r2-compression-self-test`
- `r2-self-test`
- `r2-role-self-test`
- `r2-role-self-test-a`
- `r2-role-self-test-b`
- `image-magick-diagnostic`
- `r2-upload-v4-self-test`

## Migrations R2 appliquées

- `20260803062940_harden_r2_files_and_link_receipts`
- `20260803064521_add_teacher_preparation_and_administrative_documents_r2`
- `20260803065147_optimize_administrative_documents_and_cahier_prep_rls`
- `20260803070815_enable_pg_net_for_storage_jobs`
- `20260803075027_secure_r2_access_and_school_year`
- `20260803075840_normalize_student_access_flags`
- `20260803081937_add_secure_archive_workflow`
- `20260803082004_add_archive_summary_rpc`
- `20260803082028_lock_archive_rpc_execution`
- `20260803083125_index_archive_audit_foreign_keys`
- `20260803083433_enforce_school_file_archive_audit`
- `20260803090930_add_r2_image_optimization_metrics`
- `20260803101640_normalize_administrative_document_currency`

## Métriques de compression enregistrées

`school_files` conserve :

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
- séparation Direction 1 / Direction 2 / Caisse / Enseignant / Parent / Gardien ;
- liste blanche Parent ;
- interdiction des finances pour l’Enseignant ;
- aucun accès direct R2 pour le Gardien ;
- validation du propriétaire et de la catégorie ;
- année scolaire résolue côté serveur ;
- contrôle binaire JPEG, PNG, WebP et PDF ;
- décodage réel des images avant stockage ;
- compression automatique avant R2 ;
- archivage et restauration audités ;
- dossiers administratifs et cahiers avec plusieurs pièces ;
- URLs signées valables 300 secondes ;
- devise administrative vide normalisée en `USD`.

## Tests effectués

### Connexion R2

- PUT : réussi ;
- GET : réussi ;
- contenu et taille : identiques ;
- liste : réussie ;
- suppression : réussie.

### Compression technique initiale

Une image PNG synthétique de 256 × 256 et 568 octets a été traitée :

- sortie : WebP 128 × 128 ;
- taille finale : 116 octets ;
- économie : 452 octets ;
- réduction : 79,58 % ;
- envoi R2 : réussi ;
- relecture et comparaison : réussies ;
- objet supprimé après test : oui.

Ce taux est une preuve de fonctionnement, pas une garantie pour toutes les images.

### Étape 5 — tests authentifiés des rôles

Deux lots contrôlés ont été exécutés avec des comptes et données temporaires :

- lot A : 22/22 contrôles réussis ;
- lot B : 20/20 contrôles réussis ;
- total : 42/42 contrôles réussis.

Résultats principaux :

- Direction 1 : compression, envoi, liste, téléchargement, URL signée et accès R2 réussis ;
- Caisse : reçu lié à une transaction confirmée, compression et téléchargement réussis ;
- Direction 2 : accès non financier réussi, accès financier et reçus bloqués ;
- Enseignant : propres devoirs/préparations autorisés, reçus bloqués ;
- Parent : photo et reçu de son enfant autorisés, identité interne et autre élève bloqués ;
- Gardien : aucun upload, téléchargement ou accès aux archives ;
- archives : Direction 1 uniquement ; cycle actif → archive → téléchargement archive → restauration → suppression réussi.

Mesures du lot A :

- photo : 568 → 194 octets, économie 374 octets, réduction 65,85 % ;
- reçu : 568 → 198 octets, économie 370 octets, réduction 65,14 %.

### Validation ciblée `r2-upload` version 4

Le dernier test ciblé a obtenu 4/4 contrôles réussis :

- PNG valide de 64 × 64 : 133 → 100 octets ;
- économie : 33 octets ;
- réduction : 24,81 % ;
- fichier valide créé et métriques enregistrées ;
- image volontairement corrompue rejetée en HTTP `415` ;
- aucun fichier créé pour l’image corrompue ;
- suppression du fichier valide réussie.

### Données et nettoyage

Après les tests :

- 0 compte Auth temporaire ;
- 0 utilisateur applicatif temporaire ;
- 0 profil temporaire ;
- 0 invitation temporaire ;
- 0 fichier actif dans `school_files` ;
- 0 objet R2 de test conservé.

## Code versionné

- `supabase/functions/r2-upload/index.ts`
- `supabase/functions/r2-upload/deno.json`
- `supabase/functions/r2-files/index.ts`
- `supabase/functions/r2-archives/index.ts`
- `supabase/migrations/20260803090930_add_r2_image_optimization_metrics.sql`
- `supabase/migrations/20260803101640_normalize_administrative_document_currency.sql`
- `docs/R2_IMAGE_OPTIMIZATION_API.md`
- `docs/R2_STORAGE_API.md`
- `coordination/TASKS.md`

## Restant

- interdire techniquement l’upload direct d’images vers `r2-files` après intégration frontend de `r2-upload` ;
- clôture et archivage annuel automatique ;
- inventaire annuel exportable ;
- réconciliation R2 ↔ `school_files` ;
- sauvegarde Backblaze B2 ;
- correction des anciennes fonctions scanner `SECURITY DEFINER` ;
- activation de la protection contre les mots de passe compromis ;
- configuration du nouveau domaine, DNS, SSL, redirections et CORS quand le domaine définitif sera disponible.
