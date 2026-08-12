-- ============================================================================
-- SchoolSafe — ETATS SENSIBLES DE L'ELEVE
-- DRAFT — NE PAS APPLIQUER EN PRODUCTION
-- Issue #89. ROLLBACK final volontaire.
-- ============================================================================

BEGIN;

-- --------------------------------------------------------------------------
-- 1. Accès du parent à la fiche de cet enfant
--    private.owns_student() et get_parent_pedagogic_context() lisent déjà
--    students.access_parent : cette RPC rend la transition explicite/auditée.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_student_parent_access(
  p_sid text,
  p_enabled boolean
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
  s public.students%rowtype;
BEGIN
  IF v_role NOT IN ('direction','direction2') OR v_uid IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','FORBIDDEN');
  END IF;
  IF p_enabled IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','enabled');
  END IF;

  SELECT u.name INTO v_name
  FROM public.users u
  WHERE u.id=v_uid AND u.status='active';
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); END IF;

  SELECT * INTO s
  FROM public.students
  WHERE id=p_sid
  FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','STUDENT_NOT_FOUND'); END IF;
  IF COALESCE(s.archived,false) THEN RETURN jsonb_build_object('ok',false,'code','STUDENT_ARCHIVED'); END IF;

  IF COALESCE(s.access_parent,true)=p_enabled THEN
    RETURN jsonb_build_object(
      'ok',true,
      'code','STUDENT_PARENT_ACCESS_ALREADY_SET',
      'student_id',s.id,
      'access_parent',p_enabled
    );
  END IF;

  UPDATE public.students
  SET access_parent=p_enabled
  WHERE id=s.id;

  PERFORM private.write_audit_event(
    v_uid,v_name,'student_parent_access_changed',
    jsonb_build_object(
      'student_id',s.id,
      'old_value',COALESCE(s.access_parent,true),
      'new_value',p_enabled
    ),
    s.id
  );

  RETURN jsonb_build_object(
    'ok',true,
    'code','STUDENT_PARENT_ACCESS_UPDATED',
    'student_id',s.id,
    'access_parent',p_enabled
  );
END;
$$;

REVOKE ALL ON FUNCTION public.set_student_parent_access(text,boolean)
FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_student_parent_access(text,boolean)
TO authenticated,service_role;

-- --------------------------------------------------------------------------
-- 2. Autorisation de sortie autonome
--    scan_student_exit_at_gate() applique déjà may_leave_alone + date.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_student_self_exit_authorization(
  p_sid text,
  p_allowed boolean,
  p_until date DEFAULT NULL
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
  v_today date := timezone('Africa/Kinshasa',now())::date;
  s public.students%rowtype;
BEGIN
  IF v_role NOT IN ('direction','direction2') OR v_uid IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','FORBIDDEN');
  END IF;
  IF p_allowed IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','allowed');
  END IF;
  IF p_allowed AND p_until IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','LEAVE_AUTHORIZATION_DATE_REQUIRED');
  END IF;
  IF p_allowed AND p_until<v_today THEN
    RETURN jsonb_build_object('ok',false,'code','LEAVE_AUTHORIZATION_DATE_EXPIRED');
  END IF;

  SELECT u.name INTO v_name
  FROM public.users u
  WHERE u.id=v_uid AND u.status='active';
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); END IF;

  SELECT * INTO s
  FROM public.students
  WHERE id=p_sid
  FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','STUDENT_NOT_FOUND'); END IF;
  IF COALESCE(s.archived,false) THEN RETURN jsonb_build_object('ok',false,'code','STUDENT_ARCHIVED'); END IF;

  IF COALESCE(s.may_leave_alone,false)=p_allowed
     AND s.leave_alone_until IS NOT DISTINCT FROM CASE WHEN p_allowed THEN p_until ELSE NULL END THEN
    RETURN jsonb_build_object(
      'ok',true,
      'code','STUDENT_SELF_EXIT_ALREADY_SET',
      'student_id',s.id,
      'may_leave_alone',p_allowed,
      'leave_alone_until',CASE WHEN p_allowed THEN p_until ELSE NULL END
    );
  END IF;

  UPDATE public.students
  SET may_leave_alone=p_allowed,
      leave_alone_until=CASE WHEN p_allowed THEN p_until ELSE NULL END,
      leave_alone_authorized_by=CASE WHEN p_allowed THEN v_uid ELSE NULL END,
      leave_alone_authorized_at=CASE WHEN p_allowed THEN now() ELSE NULL END
  WHERE id=s.id;

  PERFORM private.write_audit_event(
    v_uid,v_name,'student_self_exit_authorization_changed',
    jsonb_build_object(
      'student_id',s.id,
      'old_allowed',COALESCE(s.may_leave_alone,false),
      'old_until',s.leave_alone_until,
      'new_allowed',p_allowed,
      'new_until',CASE WHEN p_allowed THEN p_until ELSE NULL END
    ),
    s.id
  );

  RETURN jsonb_build_object(
    'ok',true,
    'code','STUDENT_SELF_EXIT_AUTHORIZATION_UPDATED',
    'student_id',s.id,
    'may_leave_alone',p_allowed,
    'leave_alone_until',CASE WHEN p_allowed THEN p_until ELSE NULL END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.set_student_self_exit_authorization(text,boolean,date)
FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_student_self_exit_authorization(text,boolean,date)
TO authenticated,service_role;

ROLLBACK;
