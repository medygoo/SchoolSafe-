# Migrations Supabase SchoolSafe

Ce dossier contient les sources versionnées des migrations backend appliquées à SchoolSafe.

## Paiements et contrôle

### `20260802205234_add_payment_control_backend_v1`

Ajoute obligations, transactions, allocations, dérogations, journal de contrôle, RLS et RPC Parent/Caisse/Gardien.

## Cloudflare R2

### `20260803062940_harden_r2_files_and_link_receipts`

Ajoute liaison reçu–transaction, idempotence, suppression auditée et index contre les doublons.

### `20260803064521_add_teacher_preparation_and_administrative_documents_r2`

Ajoute le registre administratif, 18 types standards, les liaisons R2 vers `cahier_prep`, `display_name`, les RPC et RLS par rôle.

### `20260803065147_optimize_administrative_documents_and_cahier_prep_rls`

Consolide les politiques et ajoute les index de performance.

### `20260803070815_enable_pg_net_for_storage_jobs`

Active `pg_net` pour les appels HTTP contrôlés utilisés par les tests de stockage et les futurs travaux planifiés côté serveur.

### `20260803075027_secure_r2_access_and_school_year`

Ajoute la source unique de l’année scolaire, la validation du propriétaire/catégorie et les RLS des devoirs.

### `20260803075840_normalize_student_access_flags`

Rend `students.archived` et `students.access_parent` non nuls avec valeurs par défaut sûres.

## Archives

### `20260803081937_add_secure_archive_workflow`

Ajoute l’audit et l’archivage/restauration transactionnels des dossiers administratifs et de leurs pièces.

### `20260803082004_add_archive_summary_rpc`

Ajoute le résumé des archives par année.

### `20260803082028_lock_archive_rpc_execution`

Limite l’exécution des RPC d’archive.

### `20260803083125_index_archive_audit_foreign_keys`

Ajoute les index des personnes ayant archivé ou restauré.

### `20260803083433_enforce_school_file_archive_audit`

Refuse toute archive ou restauration sans audit complet.

## Compression d’images

### `20260803090930_add_r2_image_optimization_metrics`

Ajoute :

- taille et type du fichier source ;
- dimensions source et finales ;
- profil et qualité de compression ;
- indicateur et version d’optimisation ;
- économie générée en octets et en pourcentage ;
- contraintes de taille, dimensions et cohérence ;
- index de suivi par année scolaire.

## Documents administratifs

### `20260803101640_normalize_administrative_document_currency`

Normalise la devise des documents administratifs avant insertion ou modification : une valeur vide ou nulle devient `USD`, puis la devise est convertie en majuscules.

## État

Toutes les migrations listées ont été appliquées avec succès dans Supabase. Les tests de contraintes ont été exécutés dans des transactions suivies d’un `ROLLBACK` ou avec un nettoyage complet. Aucune fausse donnée n’a été conservée.

## Règles

- Ne jamais modifier rétroactivement une migration déjà appliquée.
- Toute correction utilise une nouvelle migration.
- Les numéros de fichiers GitHub doivent correspondre exactement à l’historique Supabase.
- Lors d’une synchronisation CLI, utiliser `supabase db pull` depuis une branche propre.
- Ne jamais ajouter de clé secrète ou de secret R2 dans ce dossier.
