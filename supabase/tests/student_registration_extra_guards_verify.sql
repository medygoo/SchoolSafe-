-- ============================================================================
-- SchoolSafe — INSCRIPTION ELEVE : GARDE DOUBLON + ROTATION PHOTO
-- VERIFICATION LECTURE SEULE APRES APPLICATION SUR BASE DE TEST.
-- Ne modifie aucune donnée et n'affiche aucune information personnelle.
-- ============================================================================

-- 1. La porte save_student_profile doit porter un verrou anti-double création
-- et le code métier STUDENT_ALREADY_EXISTS.
SELECT
  position('pg_advisory_xact_lock' in pg_get_functiondef(p.oid))>0 AS concurrent_create_lock_present,
  position('STUDENT_ALREADY_EXISTS' in pg_get_functiondef(p.oid))>0 AS duplicate_code_present,
  position('lower(btrim' in pg_get_functiondef(p.oid))>0 AS normalized_name_guard_present
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.proname='save_student_profile'
  AND pg_get_function_identity_arguments(p.oid)='p_student jsonb';

-- 2. Résumé des doublons actifs nom + date de naissance.
-- Résultat attendu avant migration finale : 0. Aucun nom/date n'est affiché.
SELECT count(*) AS active_duplicate_identity_groups
FROM (
  SELECT lower(btrim(COALESCE(name,''))) AS normalized_name,
         NULLIF(btrim(COALESCE(dob,'')),'') AS dob_key
  FROM public.students
  WHERE NOT COALESCE(archived,false)
    AND NULLIF(btrim(COALESCE(name,'')),'') IS NOT NULL
    AND NULLIF(btrim(COALESCE(dob,'')),'') IS NOT NULL
  GROUP BY lower(btrim(COALESCE(name,''))),NULLIF(btrim(COALESCE(dob,'')),'')
  HAVING count(*)>1
) d;

-- 3. La liaison d'une nouvelle photo doit archiver l'ancienne métadonnée
-- plutôt que la supprimer.
SELECT
  position('previous_file_id' in pg_get_functiondef(p.oid))>0 AS previous_photo_audited,
  position('archived_at' in pg_get_functiondef(p.oid))>0 AS superseded_photo_archived,
  position('DELETE FROM public.school_files' in upper(pg_get_functiondef(p.oid)))=0 AS no_metadata_delete
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.proname='set_student_photo_file'
  AND pg_get_function_identity_arguments(p.oid)='p_sid text, p_file_id uuid';

-- 4. Aucune fiche élève ne doit pointer vers un fichier photo archivé/supprimé.
SELECT count(*) AS invalid_active_student_photo_links
FROM public.students s
JOIN public.school_files f ON f.id=s.photo_file_id
WHERE NOT COALESCE(s.archived,false)
  AND (f.archived_at IS NOT NULL OR f.deleted_at IS NOT NULL
       OR f.owner_type<>'student' OR f.owner_id<>s.id OR f.category<>'photo');
