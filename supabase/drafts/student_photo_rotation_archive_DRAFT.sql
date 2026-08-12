-- ============================================================================
-- SchoolSafe — PHOTO ELEVE : ROTATION SANS PERTE D'HISTORIQUE
-- DRAFT — NE PAS APPLIQUER EN PRODUCTION
-- À jouer APRES student_registration_core_clean_DRAFT.sql sur base de test.
-- ROLLBACK final volontaire.
--
-- Une nouvelle photo devient la référence active de students.photo_file_id.
-- L'ancienne entrée school_files n'est jamais supprimée : elle est archivée
-- afin de ne plus apparaître comme photo active tout en gardant la traçabilité.
-- La migration finale devra squasher cette définition dans le cœur #91.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.set_student_photo_file(
  p_sid text,
  p_file_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_role text := private.current_app_role();
  v_uid text := private.current_app_user_id();
  v_name text;
  v_file public.school_files%rowtype;
  v_student public.students%rowtype;
  v_old_file_id uuid;
BEGIN
  IF v_role NOT IN ('direction','direction2') OR v_uid IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','FORBIDDEN');
  END IF;
  IF p_file_id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','file_id');
  END IF;

  SELECT u.name INTO v_name
  FROM public.users u
  WHERE u.id=v_uid AND u.status='active';
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND');
  END IF;

  SELECT * INTO v_student
  FROM public.students s
  WHERE s.id=p_sid
  FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'code','STUDENT_NOT_FOUND');
  END IF;
  IF COALESCE(v_student.archived,false) THEN
    RETURN jsonb_build_object('ok',false,'code','STUDENT_ARCHIVED');
  END IF;

  IF v_student.photo_file_id IS NOT DISTINCT FROM p_file_id THEN
    RETURN jsonb_build_object(
      'ok',true,
      'code','STUDENT_PHOTO_ALREADY_LINKED',
      'student_id',v_student.id,
      'photo_file_id',p_file_id
    );
  END IF;

  SELECT * INTO v_file
  FROM public.school_files f
  WHERE f.id=p_file_id
    AND f.archived_at IS NULL
    AND f.deleted_at IS NULL;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'code','FILE_NOT_FOUND');
  END IF;

  IF v_file.owner_type<>'student' OR v_file.owner_id<>p_sid THEN
    RETURN jsonb_build_object('ok',false,'code','FILE_OWNER_MISMATCH');
  END IF;
  IF v_file.category<>'photo'
     OR v_file.mime_type NOT IN ('image/jpeg','image/png','image/webp') THEN
    RETURN jsonb_build_object('ok',false,'code','FILE_CATEGORY_INVALID');
  END IF;

  v_old_file_id := v_student.photo_file_id;

  UPDATE public.students
  SET photo_file_id=p_file_id,
      photo=NULL
  WHERE id=p_sid
  RETURNING * INTO v_student;

  -- On ne détruit jamais l'ancienne photo : on archive seulement sa fiche
  -- active. L'objet R2 reste conservé jusqu'à la politique d'archive générale.
  IF v_old_file_id IS NOT NULL AND v_old_file_id<>p_file_id THEN
    UPDATE public.school_files f
    SET archived_at=COALESCE(f.archived_at,pg_catalog.now())
    WHERE f.id=v_old_file_id
      AND f.owner_type='student'
      AND f.owner_id=p_sid
      AND f.category='photo'
      AND f.deleted_at IS NULL;
  END IF;

  PERFORM private.write_audit_event(
    v_uid,v_name,'student_photo_linked',
    jsonb_build_object(
      'student_id',p_sid,
      'new_file_id',p_file_id,
      'previous_file_id',v_old_file_id,
      'previous_file_archived',v_old_file_id IS NOT NULL AND v_old_file_id<>p_file_id
    ),
    p_sid
  );

  RETURN jsonb_build_object(
    'ok',true,
    'code','STUDENT_PHOTO_LINKED',
    'student',to_jsonb(v_student),
    'photo_file_id',p_file_id,
    'previous_photo_file_id',v_old_file_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.set_student_photo_file(text,uuid)
FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_student_photo_file(text,uuid)
TO authenticated,service_role;

ROLLBACK;
