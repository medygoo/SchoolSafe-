-- ============================================================================
-- SchoolSafe — INSCRIPTION ELEVE : VERIFICATION LECTURE SEULE
-- À lancer seulement APRES application sur une base de test.
-- Ne modifie aucune donnée et ne révèle aucun secret.
-- ============================================================================

-- 1. Colonnes structurantes
SELECT
  EXISTS(
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='students'
      AND column_name='photo_file_id' AND udt_name='uuid'
  ) AS photo_file_id_ok,
  EXISTS(
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='students'
      AND column_name='sexe'
  ) AS sexe_ok,
  EXISTS(
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='students'
      AND column_name='ecole_provenance'
  ) AS ecole_provenance_ok,
  EXISTS(
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='students'
      AND column_name='tutelle_principale'
  ) AS tutelle_principale_ok;

-- 2. Contraintes / index attendus
SELECT wanted.name,
       EXISTS(
         SELECT 1 FROM pg_constraint c
         WHERE c.conrelid='public.students'::regclass
           AND c.conname=wanted.name
       ) AS exists
FROM (VALUES
  ('students_photo_file_id_fkey'),
  ('students_cid_fkey'),
  ('students_pid_fkey'),
  ('students_created_by_fkey'),
  ('students_leave_alone_authorized_by_fkey')
) AS wanted(name)
ORDER BY wanted.name;

SELECT wanted.name,
       EXISTS(
         SELECT 1 FROM pg_indexes i
         WHERE i.schemaname='public'
           AND i.tablename='students'
           AND i.indexname=wanted.name
       ) AS exists
FROM (VALUES
  ('uq_students_mat_normalized'),
  ('uq_students_num_inscription_normalized')
) AS wanted(name)
ORDER BY wanted.name;

-- 3. RPC / helpers et sécurité
SELECT
  n.nspname AS schema_name,
  p.proname,
  pg_get_function_identity_arguments(p.oid) AS args,
  p.prosecdef AS security_definer
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE (n.nspname,p.proname) IN (
  ('public','save_student_profile'),
  ('public','set_student_photo_file'),
  ('public','set_student_primary_parent'),
  ('private','next_student_identity'),
  ('private','ensure_student_fee_obligations')
)
ORDER BY n.nspname,p.proname;

-- save_student_profile doit être SECURITY DEFINER dans la version verrouillable.
SELECT
  p.prosecdef AS save_student_profile_security_definer,
  has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.proname='save_student_profile'
  AND pg_get_function_identity_arguments(p.oid)='p_student jsonb';

-- 4. Vérifier que la génération serveur réutilise le même compteur que la
-- préinscription sans exposer sa valeur.
SELECT
  EXISTS(
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='private'
      AND p.proname='next_student_identity'
      AND position('student_mat:' in pg_get_functiondef(p.oid))>0
  ) AS manual_uses_student_counter,
  EXISTS(
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public'
      AND p.proname='validate_preinscription_email'
      AND position('student_mat:' in pg_get_functiondef(p.oid))>0
  ) AS preinscription_uses_student_counter;

-- 5. Préflight des données existantes AVANT contraintes finales.
-- Les résultats attendus sont 0. Aucun nom/matricule n'est affiché.
SELECT
  (SELECT count(*) FROM public.students s
    LEFT JOIN public.classes c ON c.id=s.cid
    WHERE s.cid IS NOT NULL AND c.id IS NULL) AS orphan_classes,
  (SELECT count(*) FROM public.students s
    LEFT JOIN public.users u ON u.id=s.pid
    WHERE s.pid IS NOT NULL AND u.id IS NULL) AS orphan_parents,
  (SELECT count(*) FROM (
     SELECT lower(btrim(mat)) k FROM public.students
     WHERE mat IS NOT NULL AND btrim(mat)<>''
     GROUP BY lower(btrim(mat)) HAVING count(*)>1
   ) d) AS duplicate_matricules,
  (SELECT count(*) FROM (
     SELECT lower(btrim(num_inscription)) k FROM public.students
     WHERE num_inscription IS NOT NULL AND btrim(num_inscription)<>''
     GROUP BY lower(btrim(num_inscription)) HAVING count(*)>1
   ) d) AS duplicate_registration_numbers,
  (SELECT count(*) FROM public.students s
    LEFT JOIN public.school_files f ON f.id=s.photo_file_id
    WHERE s.photo_file_id IS NOT NULL
      AND (f.id IS NULL OR f.owner_type<>'student' OR f.owner_id<>s.id OR f.category<>'photo')) AS invalid_photo_links;

-- 6. Etat des frais : résumé uniquement.
SELECT
  count(*) FILTER (WHERE COALESCE(active,true)) AS active_fee_types,
  count(*) FILTER (WHERE COALESCE(active,true) AND COALESCE(montant_defaut,0)>0) AS configured_positive_fee_types
FROM public.fee_types;

-- 7. Etat du verrouillage direct.
-- Avant la phase 2 : INSERT/UPDATE/DELETE peuvent encore être true.
-- Après raccordement Claude + migration lockdown : ils doivent être false.
SELECT
  has_table_privilege('authenticated','public.students','SELECT') AS authenticated_select,
  has_table_privilege('authenticated','public.students','INSERT') AS authenticated_insert,
  has_table_privilege('authenticated','public.students','UPDATE') AS authenticated_update,
  has_table_privilege('authenticated','public.students','DELETE') AS authenticated_delete,
  EXISTS(
    SELECT 1 FROM pg_policies
    WHERE schemaname='public' AND tablename='students'
      AND policyname='students_direction_write'
  ) AS legacy_direction_write_policy_present;

-- 8. R2 : school_files.id reste la référence permanente.
SELECT
  c.data_type,
  c.udt_name
FROM information_schema.columns c
WHERE c.table_schema='public'
  AND c.table_name='school_files'
  AND c.column_name='id';
