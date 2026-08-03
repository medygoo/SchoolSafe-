# R2 deployment status

Date : 2026-08-03

## Fonction active

- Supabase Edge Function : `r2-files`
- Version : 5
- Statut : ACTIVE
- JWT : obligatoire
- Formats : JPEG, PNG, WebP et PDF
- Taille maximale : 5 Mo
- Année scolaire courante fournie par `settings.year`

## Migrations appliquées

- `20260803062940_harden_r2_files_and_link_receipts`
- `20260803064521_add_teacher_preparation_and_administrative_documents_r2`
- `20260803065147_optimize_administrative_documents_and_cahier_prep_rls`
- `20260803075027_secure_r2_access_and_school_year`
- `20260803075840_normalize_student_access_flags`

Les sources correspondantes de l’étape 2 sont maintenant enregistrées dans `supabase/migrations/` sur la branche de travail avec les mêmes versions que l’historique Supabase.

## Capacités actives

- reçus liés aux transactions confirmées ;
- idempotence avec détection de réutilisation incohérente d’une clé ;
- suppression auditée ;
- fichiers du cahier de préparation ;
- plusieurs fichiers par préparation ;
- registre des documents administratifs ;
- plusieurs fichiers par dossier administratif ;
- nom lisible `display_name` ;
- séparation Direction 1 / Direction 2 / Caisse ;
- aucun accès direct R2 pour le Gardien ;
- liste blanche Parent ;
- interdiction explicite des reçus pour l’Enseignant ;
- validation de l’existence de chaque propriétaire ;
- validation des couples propriétaire/catégorie ;
- année scolaire résolue côté serveur ;
- rejet des années contradictoires ;
- vérification de la signature binaire JPEG, PNG, WebP et PDF ;
- RLS des devoirs pour Direction 1, Direction 2, enseignants affectés et Parents de la classe.

## Code versionné

- `supabase/functions/r2-files/index.ts`
- `supabase/functions/r2-files/deno.json`
- `supabase/migrations/20260803075027_secure_r2_access_and_school_year.sql`
- `supabase/migrations/20260803075840_normalize_student_access_flags.sql`

## Tests effectués

Les tests transactionnels ont confirmé que :

- l’année `2025-2026` est injectée depuis `settings.year` ;
- un propriétaire inexistant est refusé ;
- une combinaison propriétaire/catégorie interdite est refusée ;
- une année scolaire contradictoire est refusée ;
- les quatre politiques RLS des devoirs sont présentes ;
- le déclencheur `school_files_validate_metadata` est actif.

Tous les tests ont été suivis d’un `ROLLBACK`. Aucun faux document et aucun faux fichier n’ont été conservés.

## État des données

- 18 types administratifs actifs ;
- 0 document administratif réel ;
- 0 préparation réelle dans `cahier_prep` ;
- 0 métadonnée R2 active dans `school_files` au moment du contrôle ;
- 0 élève réel au moment du contrôle.

## Restant

- cycle R2 réel avec un compte Direction 1 ;
- tests authentifiés Direction 2, Caisse, Enseignant, Parent et Gardien ;
- compression automatique des images côté serveur ;
- consultation spéciale des archives par Direction 1 ;
- archivage annuel automatique ;
- réconciliation des objets orphelins ;
- sauvegarde Backblaze B2 ;
- correction progressive des anciennes fonctions scanner `SECURITY DEFINER`.
