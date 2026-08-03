# R2 deployment status

Date : 2026-08-03

## Fonction active

- Supabase Edge Function : `r2-files`
- Version : 4
- Statut : ACTIVE
- JWT : obligatoire
- Formats : JPEG, PNG, WebP et PDF
- Taille maximale : 5 Mo

## Migrations appliquées

- `20260803062940_harden_r2_files_and_link_receipts`
- `20260803064521_add_teacher_preparation_and_administrative_documents_r2`
- `20260803065147_optimize_administrative_documents_and_cahier_prep_rls`

## Capacités actives

- reçus liés aux transactions ;
- idempotence ;
- suppression auditée ;
- fichiers du cahier de préparation ;
- plusieurs fichiers par préparation ;
- registre des documents administratifs ;
- plusieurs fichiers par dossier administratif ;
- nom lisible `display_name` ;
- séparation Direction 1 / Direction 2 / Caisse ;
- aucun accès direct R2 pour le Gardien.

## État des données

- 18 types administratifs actifs ;
- 0 document administratif réel ;
- 0 préparation réelle dans `cahier_prep` ;
- 0 métadonnée R2 active dans `school_files` au moment du contrôle.

Les tests réalisés ont utilisé des transactions avec `ROLLBACK`. Aucun faux document et aucun faux fichier n’ont été conservés.

## Restant

- cycle R2 réel avec un compte Direction 1 ;
- tests authentifiés par rôle ;
- compression automatique des images côté serveur ;
- consultation spéciale des archives par Direction 1 ;
- archivage annuel automatique ;
- réconciliation des objets orphelins ;
- sauvegarde Backblaze B2.
