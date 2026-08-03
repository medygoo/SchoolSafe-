# R2 deployment status

Date : 2026-08-03

## Fonctions actives

### `r2-files`

- Version : 5
- Statut : ACTIVE
- JWT : obligatoire
- Usage : fichiers actifs, envoi, liste, lecture et suppression auditée
- Formats : JPEG, PNG, WebP et PDF
- Taille maximale : 5 Mo
- Année scolaire courante fournie par `settings.year`

### `r2-archives`

- Version : 1
- Statut : ACTIVE
- JWT : obligatoire
- Accès : Direction 1 uniquement
- Usage : résumé par année, liste paginée, ouverture temporaire, archivage et restauration
- Les objets ne sont ni copiés ni déplacés dans R2 pendant l’archivage

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

Les sources portent les mêmes versions dans `supabase/migrations/` sur la branche de travail.

## Capacités actives

- reçus liés aux transactions confirmées ;
- idempotence ;
- suppression auditée ;
- cahier de préparation avec plusieurs pièces ;
- registre des documents administratifs avec plusieurs pièces ;
- séparation Direction 1 / Direction 2 / Caisse ;
- aucun accès direct R2 pour le Gardien ;
- liste blanche Parent ;
- interdiction des finances pour l’Enseignant ;
- validation de l’existence de chaque propriétaire ;
- validation des couples propriétaire/catégorie ;
- année scolaire résolue côté serveur ;
- vérification binaire JPEG, PNG, WebP et PDF ;
- archivage et restauration audités ;
- synchronisation transactionnelle d’un dossier administratif avec toutes ses pièces ;
- consultation des archives uniquement par Direction 1 ;
- résumé du nombre de fichiers et de la taille par année ;
- URLs signées d’archive valables 300 secondes ;
- rejet de toute archive sans `archived_by` ;
- rejet de toute restauration sans `restored_at` et `restored_by`.

## Code versionné

- `supabase/functions/r2-files/index.ts`
- `supabase/functions/r2-files/deno.json`
- `supabase/functions/r2-archives/index.ts`
- `supabase/functions/r2-archives/deno.json`
- migrations SQL correspondantes
- `docs/R2_STORAGE_API.md`
- `docs/R2_ARCHIVES_API.md`
- `coordination/ARCHIVE_TASKS.md`

## Tests effectués

- cycle réel Cloudflare R2 : PUT, GET, contenu, taille, liste et suppression réussis ;
- test transactionnel dossier administratif + pièce : archivage et restauration réussis ;
- archive sans auteur refusée ;
- restauration sans date et auteur refusée ;
- transition auditée archive → restauration réussie ;
- tous les tests de base suivis d’un `ROLLBACK` ;
- endpoint `r2-archives` vérifié : absence de JWT refusée avec HTTP 401 ;
- aucune fausse donnée conservée ;
- aucun objet de test R2 conservé.

## État des données

- 18 types administratifs actifs ;
- 0 document administratif réel ;
- 0 préparation réelle dans `cahier_prep` ;
- 0 métadonnée R2 active dans `school_files` ;
- 0 archive réelle ;
- 0 élève réel au moment du contrôle.

## Restant

- compression automatique des images côté serveur ;
- comptes et tests authentifiés Direction 2, Caisse, Enseignant, Parent et Gardien ;
- clôture et archivage annuel automatique ;
- inventaire annuel exportable ;
- réconciliation des objets orphelins ;
- sauvegarde Backblaze B2 ;
- correction progressive des anciennes fonctions scanner `SECURITY DEFINER` ;
- activation de la protection contre les mots de passe compromis.
