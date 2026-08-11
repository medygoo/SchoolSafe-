-- ============================================================================
-- SchoolSafe P0-25 — CORRECTIF DRAFT DE PORTEE DU CONTEXTE DE SORTIE
-- Ne pas appliquer en production. À exécuter après le draft principal sur une
-- base de test. ROLLBACK final volontaire.
--
-- Diagnostic réel : private.can_scan() inclut direction3/Caisse car la Caisse
-- a un scanner financier. Cela ne doit pas lui donner l'identité des personnes
-- autorisées à venir chercher un enfant.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.get_scanner_aps()
RETURNS TABLE(
  id text,
  sid text,
  name text,
  relation text,
  photo text,
  phone text,
  valid_until date,
  approval_status text,
  active boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_role text:=private.current_app_role();
BEGIN
  -- Le registre des accompagnateurs appartient au contrôle de SORTIE, pas au
  -- scanner financier. Exclut donc direction3/Caisse.
  IF NOT private.can_confirm_student_exit() THEN
    RAISE EXCEPTION 'Accès refusé' USING errcode='42501';
  END IF;

  RETURN QUERY
  SELECT a.id,a.sid,a.name,a.relation,a.photo,
         CASE WHEN v_role IN ('direction','gardien') THEN a.phone ELSE NULL END,
         a.valid_until,a.approval_status,a.active
  FROM public.aps a
  WHERE a.approval_status='approved'
    AND a.active
    AND (a.valid_until IS NULL OR a.valid_until>=timezone('Africa/Kinshasa',now())::date);
END;
$$;

CREATE OR REPLACE FUNCTION public.get_student_pickup_context(p_sid text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_role text:=private.current_app_role();
  v_student public.students%rowtype;
  v_parent public.users%rowtype;
  v_people jsonb;
  v_full_phone boolean;
BEGIN
  -- Parent : uniquement son propre enfant.
  -- Personnel : uniquement les rôles autorisés à confirmer une sortie.
  -- La Caisse n'est plus incluse par le simple droit can_scan().
  IF NOT (private.can_confirm_student_exit() OR private.owns_student(p_sid)) THEN
    RAISE EXCEPTION 'Accès refusé' USING errcode='42501';
  END IF;

  SELECT * INTO v_student FROM public.students
  WHERE id=p_sid AND NOT coalesce(archived,false);
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','STUDENT_NOT_FOUND'); END IF;

  IF v_student.pid IS NOT NULL THEN
    SELECT * INTO v_parent FROM public.users WHERE id=v_student.pid AND role='parent';
  END IF;
  v_full_phone:=v_role IN ('direction','direction2','gardien');

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',a.id,
    'kind','accredited',
    'name',a.name,
    'relation',a.relation,
    'phone',CASE WHEN v_full_phone THEN a.phone ELSE regexp_replace(a.phone,'^(\\+[0-9]{3})[0-9]+([0-9]{2})$','\\1••••••\\2') END,
    'photo_portrait',a.photo,
    'photo_full_body',a.photo_full_body,
    'photo_portrait_file_id',a.photo_file_id,
    'photo_full_body_file_id',a.photo_full_body_file_id,
    'id_doc_type',a.id_doc_type,
    'id_doc_last4',a.id_doc_last4,
    'valid_from',a.valid_from,
    'valid_until',a.valid_until
  ) ORDER BY a.name),'[]'::jsonb)
  INTO v_people
  FROM public.aps a
  WHERE a.sid=p_sid
    AND a.active
    AND a.approval_status='approved'
    AND a.valid_from<=timezone('Africa/Kinshasa',now())::date
    AND (a.valid_until IS NULL OR a.valid_until>=timezone('Africa/Kinshasa',now())::date);

  RETURN jsonb_build_object(
    'ok',true,
    'student',jsonb_build_object(
      'id',v_student.id,'name',v_student.name,'photo',v_student.photo,'class_id',v_student.cid
    ),
    'primary_parent',CASE WHEN v_parent.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id',v_parent.id,
      'kind','primary',
      'name',v_parent.name,
      'relation','Parent principal',
      'phone',CASE WHEN v_full_phone THEN v_parent.phone ELSE NULL END,
      'photo_portrait',v_parent.photo_url,
      'photo_full_body',v_parent.identity_full_body_photo_url,
      'photo_portrait_file_id',v_parent.photo_file_id,
      'photo_full_body_file_id',v_parent.identity_full_body_photo_file_id,
      'id_doc_type',v_parent.identity_document_type,
      'id_doc_last4',v_parent.identity_document_last4,
      'ready_for_pickup',v_parent.status='active'
        AND (v_parent.photo_url IS NOT NULL OR v_parent.photo_file_id IS NOT NULL)
        AND (v_parent.identity_full_body_photo_url IS NOT NULL OR v_parent.identity_full_body_photo_file_id IS NOT NULL)
    ) END,
    'authorized_people',v_people,
    'authorized_count',jsonb_array_length(v_people)
  );
END;
$$;

ROLLBACK;
