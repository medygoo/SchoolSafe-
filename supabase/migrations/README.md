# Migrations Supabase SchoolSafe

Ce dossier contient les sources versionnées des migrations backend appliquées à SchoolSafe.

## Paiements et contrôle

### `20260802205234_add_payment_control_backend_v1`

Ajoute obligations, transactions, allocations, dérogations, journal de contrôle, RLS et RPC Parent/Caisse/Gardien.

### Lot finance v2 — 4 août 2026

- `20260804090600_harden_payment_authorship_receipts` : auteur et rôle figés sur chaque paiement, compteur de reçus annuel côté serveur et index financiers.
- `20260804090649_upgrade_payment_rpc_contract_v2` : enregistrement et contrepassation avec contrat JSON v2, numéro permanent et auteurs immuables.
- `20260804090716_expose_payment_authors_in_fee_summary` : auteurs d’encaissement et de contrepassation inclus dans les dossiers Caisse/Parent autorisés.

## Scanner

- `20260803155814_harden_gate_access_contract` : statut de portail minimal et protégé.
- `20260803160839_fix_scanner_rpc_edge_cases` : cas limites et réponses scanner.
- `20260804091101_enforce_scanner_orientation_contract_v2` : `orient` devient `allowed=false`.
- `20260804091117_limit_scanner_contact_directory` : téléphones limités à Direction 1 et Gardien.
- `20260804091206_upgrade_scanner_recording_rpc_contract_v2` : réponses directes et aucun passage enregistré lors d’un refus ou d’une orientation.

## Profils et comptes Auth

- `20260803200317_fix_school_user_profile_auth_permission` : autorisation du contrat de sauvegarde profil.
- `20260804091650_repair_account_invitation_linkage_contract` : liaison de l’identité Auth au profil SchoolSafe existant, sans doublon.
- `20260804091901_align_account_invitation_audit_log` : préparation/annulation d’invitation alignées sur le journal d’audit réel.
- `20260804092739_optimize_profile_rls_and_payment_indexes` : protection des champs d’identité et de rôle, optimisation RLS et index.

## Parent

- `20260803110748_scope_student_ownership_to_parent_role` : propriété enfant limitée au rôle Parent.
- `20260804092250_add_parent_pedagogic_context_rpc` : classe, titulaires, emploi du temps et cahier de texte validé pour un enfant du Parent.

## Site public connecté

- `20260804092432_add_secure_public_site_content` : contenu du site en lecture publique, publication réservée à Direction 1 par RPC.

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

- `20260803081937_add_secure_archive_workflow` : audit et archivage/restauration transactionnels.
- `20260803082004_add_archive_summary_rpc` : résumé des archives par année.
- `20260803082028_lock_archive_rpc_execution` : limitation d’exécution des RPC d’archive.
- `20260803083125_index_archive_audit_foreign_keys` : index des personnes ayant archivé ou restauré.
- `20260803083433_enforce_school_file_archive_audit` : refus de toute archive/restauration sans audit complet.

## Compression d’images

### `20260803090930_add_r2_image_optimization_metrics`

Ajoute les tailles, dimensions, profils de compression, version d’optimisation et économies réalisées.

## Documents administratifs

### `20260803101640_normalize_administrative_document_currency`

Normalise la devise avant insertion ou modification.

## État

Toutes les migrations listées ont été appliquées avec succès dans Supabase. Les tests de contraintes ont été exécutés dans des transactions suivies d’un `ROLLBACK` ou avec un nettoyage complet. Aucune fausse donnée n’a été conservée.

## Règles

- Ne jamais modifier rétroactivement une migration déjà appliquée.
- Toute correction utilise une nouvelle migration.
- Les numéros de fichiers GitHub doivent correspondre exactement à l’historique Supabase.
- Lors d’une synchronisation CLI, utiliser `supabase db pull` depuis une branche propre.
- Ne jamais ajouter de clé secrète ou de secret R2 dans ce dossier.
