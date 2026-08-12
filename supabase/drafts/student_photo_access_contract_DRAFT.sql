-- ============================================================================
-- SchoolSafe #89 — AUTORISATION CENTRALISEE DE LA PHOTO ELEVE
-- DRAFT — NE PAS APPLIQUER EN PRODUCTION
-- ROLLBACK final volontaire.
-- ============================================================================
--
-- Motif : private.can_scan() inclut actuellement direction3 (Caisse), et
-- get_scanner_students() n'est pas filtré par classe pour les enseignants.
-- La photo ne doit donc PAS réutiliser can_scan() ni can_view_student() tels
-- quels : direction3 serait autorisée, ce qui n'est pas le contrat de #89.
--
-- Contrat photo :
--   Direction 1/2 : oui
--   Gardien       : oui, pour vérification au portail
--   Enseignant    : uniquement un élève d'une classe qu'il enseigne
--   Parent        : uniquement son enfant avec access_parent actif
--   Caisse        : non
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.get_student_photo_file_ref(p_sid text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_role text := private.current_app_role();
  v_uid text := private.current_app_user_id();
  s public.students%rowtype;
  v_allowed boolean := false;
BEGIN
  IF v_uid IS NULL OR v_role IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','FORBIDDEN');
  END IF;

  SELECT * INTO s
  FROM public.students
  WHERE id=p_sid;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'code','STUDENT_NOT_FOUND');
  END IF;
  IF COALESCE(s.archived,false) THEN
    RETURN jsonb_build_object('ok',false,'code','STUDENT_ARCHIVED');
  END IF;

  v_allowed := CASE
    WHEN v_role IN ('direction','direction2') THEN true
    WHEN v_role='gardien' THEN true
    WHEN v_role='enseignant' THEN private.teaches_class(s.cid)
    WHEN v_role='parent' THEN private.owns_student(s.id)
    ELSE false
  END;

  IF NOT v_allowed THEN
    RETURN jsonb_build_object('ok',false,'code','STUDENT_PHOTO_FORBIDDEN');
  END IF;

  IF s.photo_file_id IS NULL THEN
    RETURN jsonb_build_object(
      'ok',false,
      'code','STUDENT_PHOTO_NOT_SET',
      'student_id',s.id,
      'legacy_photo_present',NULLIF(btrim(COALESCE(s.photo,'')),'') IS NOT NULL
    );
  END IF;

  -- Aucune URL R2, aucun chemin de stockage et aucune donnée d'identité ne
  -- sortent de cette RPC : seulement la référence UUID permanente.
  RETURN jsonb_build_object(
    'ok',true,
    'code','STUDENT_PHOTO_FILE_REF_READY',
    'student_id',s.id,
    'file_id',s.photo_file_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_student_photo_file_ref(text)
FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_student_photo_file_ref(text)
TO authenticated,service_role;

ROLLBACK;
