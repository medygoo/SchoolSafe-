# Migrations Supabase SchoolSafe

Ce dossier documente les migrations déjà appliquées au projet SchoolSafe.

## Migrations appliquées

### `20260802205234_add_payment_control_backend_v1`

Ajoute :

- obligations scolaires ;
- transactions ;
- allocations ;
- dérogations ;
- journal de contrôle ;
- RLS et RPC Parent, Caisse et Gardien.

### `20260803062940_harden_r2_files_and_link_receipts`

Ajoute :

- liaison des reçus R2 aux transactions ;
- idempotence ;
- suppression auditée ;
- index contre les doublons.

### `20260803064521_add_teacher_preparation_and_administrative_documents_r2`

Ajoute :

- `administrative_document_types` ;
- `administrative_documents` ;
- 18 types administratifs standards ;
- registre avec nom, date, référence, période, fournisseur, montant, devise, année et notes ;
- liaisons R2 vers `cahier_prep` et le registre administratif ;
- champ `display_name` ;
- RLS par rôle ;
- RPC `create_administrative_document(...)` ;
- RPC `archive_administrative_document(...)`.

### `20260803065147_optimize_administrative_documents_and_cahier_prep_rls`

Ajoute :

- index de performance ;
- politiques RLS consolidées ;
- droits Direction 1, Direction 2 et enseignant propriétaire sur le cahier de préparation.

## État

Toutes les migrations ci-dessus ont été appliquées avec succès dans Supabase.

Les tests de contraintes ont été exécutés dans des transactions suivies d’un `ROLLBACK`. Aucune fausse donnée n’a été conservée.

## Règles

- Ne jamais modifier rétroactivement une migration déjà appliquée.
- Toute correction doit utiliser une nouvelle migration.
- Le SQL complet reste aussi enregistré dans l’historique Supabase.
- Lors d’une synchronisation CLI, utiliser `supabase db pull` depuis une branche locale propre.
- Ne jamais ajouter une clé secrète ou un secret R2 dans ce dossier.
