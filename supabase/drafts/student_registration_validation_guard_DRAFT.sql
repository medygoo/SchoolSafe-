-- ============================================================================
-- SchoolSafe — INSCRIPTION ELEVE : GARDE DE VALIDATION DU DRAFT
-- À jouer APRES student_registration_core_clean_DRAFT.sql sur base de test.
-- DRAFT — ROLLBACK final volontaire.
--
-- Ce fichier existe uniquement pour garder la branche de travail sûre sans
-- réécrire artificiellement tout le premier draft. La migration finale devra
-- SQUASHER cette garde dans une seule définition de save_student_profile().
-- ============================================================================

BEGIN;

ALTER FUNCTION public.save_student_profile(jsonb)
  RENAME TO save_student_profile_core_impl_draft;

REVOKE ALL ON FUNCTION public.save_student_profile_core_impl_draft(jsonb)
FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.save_student_profile_core_impl_draft(jsonb)
TO service_role;

CREATE OR REPLACE FUNCTION public.save_student_profile(p_student jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_dummy_date date;
  v_input_id text;
  v_name text;
  v_dob_text text;
  v_duplicate_id text;
BEGIN
  IF p_student IS NULL OR jsonb_typeof(p_student)<>'object' THEN
    RETURN jsonb_build_object('ok',false,'code','INVALID_PAYLOAD');
  END IF;

  IF p_student ? 'access_parent'
     AND jsonb_typeof(p_student->'access_parent')<>'boolean' THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','access_parent');
  END IF;

  IF p_student ? 'may_leave_alone'
     AND jsonb_typeof(p_student->'may_leave_alone')<>'boolean' THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','may_leave_alone');
  END IF;

  IF p_student ? 'leave_alone_until'
     AND NULLIF(btrim(COALESCE(p_student->>'leave_alone_until','')),'') IS NOT NULL THEN
    BEGIN
      v_dummy_date := (p_student->>'leave_alone_until')::date;
    EXCEPTION
      WHEN invalid_datetime_format OR datetime_field_overflow THEN
        RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','leave_alone_until');
    END;
  END IF;

  -- Même garde que la préinscription : si le nom + la date de naissance sont
  -- connus, deux téléphones ne doivent pas pouvoir créer deux fois le même
  -- enfant. Le verrou transactionnel ferme la fenêtre de concurrence.
  v_input_id := NULLIF(btrim(COALESCE(p_student->>'id','')),'');
  v_name := NULLIF(btrim(COALESCE(p_student->>'name','')),'');
  v_dob_text := NULLIF(btrim(COALESCE(p_student->>'dob','')),'');

  IF v_input_id IS NULL AND v_name IS NOT NULL AND v_dob_text IS NOT NULL THEN
    BEGIN
      v_dummy_date := v_dob_text::date;
    EXCEPTION
      WHEN invalid_datetime_format OR datetime_field_overflow THEN
        RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','dob');
    END;

    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext('student-create'),
      pg_catalog.hashtext(lower(v_name)||':'||pg_catalog.to_char(v_dummy_date,'YYYY-MM-DD'))
    );

    SELECT s.id INTO v_duplicate_id
    FROM public.students s
    WHERE lower(btrim(COALESCE(s.name,'')))=lower(v_name)
      AND NULLIF(btrim(COALESCE(s.dob,'')),'')=pg_catalog.to_char(v_dummy_date,'YYYY-MM-DD')
      AND NOT COALESCE(s.archived,false)
    ORDER BY s.id
    LIMIT 1;

    IF v_duplicate_id IS NOT NULL THEN
      RETURN jsonb_build_object(
        'ok',false,
        'code','STUDENT_ALREADY_EXISTS',
        'student_id',v_duplicate_id,
        'field','name'
      );
    END IF;
  END IF;

  RETURN public.save_student_profile_core_impl_draft(p_student);
END;
$$;

REVOKE ALL ON FUNCTION public.save_student_profile(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_student_profile(jsonb)
TO authenticated,service_role;

ROLLBACK;
