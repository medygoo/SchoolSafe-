-- ==========================================================================
-- SchoolSafe P0-9 — AUTORITE DIRECTION 1 + VALIDATION HEURE
-- DRAFT — NE PAS APPLIQUER EN PRODUCTION
-- À exécuter après lifecycle_reads sur une base de test.
-- ROLLBACK final volontaire.
-- ==========================================================================

BEGIN;

ALTER TABLE public.rattrapages
  ADD COLUMN IF NOT EXISTS validated_by_role text;

-- Direction 2 donne une décision pédagogique, mais Direction 1 garde
-- l'autorité finale tant que le dossier n'est pas engagé financièrement.
CREATE OR REPLACE FUNCTION public.validate_rattrapage(
  p_rattrapage_id text,
  p_decision text,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_role text := private.current_app_role();
  v_uid text := private.current_app_user_id();
  v_name text := private.rattrapage_actor_name();
  v_decision text := lower(btrim(COALESCE(p_decision,'')));
  v_note text := NULLIF(btrim(COALESCE(p_note,'')),'');
  r public.rattrapages%rowtype;
  v_status text;
BEGIN
  IF v_role NOT IN ('direction','direction2') OR v_uid IS NULL OR v_name IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','FORBIDDEN');
  END IF;
  IF v_decision NOT IN ('approved','refused') THEN
    RETURN jsonb_build_object('ok',false,'code','DECISION_INVALID');
  END IF;
  IF v_decision='refused' AND (v_note IS NULL OR length(v_note)<3) THEN
    RETURN jsonb_build_object('ok',false,'code','REFUSAL_REASON_REQUIRED');
  END IF;

  SELECT * INTO r
  FROM public.rattrapages
  WHERE id=p_rattrapage_id
  FOR UPDATE;

  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','RATTRAPAGE_NOT_FOUND'); END IF;
  IF COALESCE(r.archived,false) THEN RETURN jsonb_build_object('ok',false,'code','RATTRAPAGE_ARCHIVED'); END IF;
  IF COALESCE(r.done,false) THEN RETURN jsonb_build_object('ok',false,'code','RATTRAPAGE_ALREADY_DONE'); END IF;

  v_status := CASE WHEN v_decision='approved' THEN 'validated' ELSE 'refused' END;

  IF r.status=v_status THEN
    RETURN jsonb_build_object('ok',true,'code','RATTRAPAGE_ALREADY_'||upper(v_status),'status',r.status);
  END IF;

  -- Une décision déjà prise n'est réversible que par D1, et seulement avant
  -- toute condition financière / paiement / planification.
  IF r.status IN ('validated','refused') AND r.status<>v_status THEN
    IF v_role<>'direction' THEN
      RETURN jsonb_build_object('ok',false,'code','DIRECTION1_OVERRIDE_REQUIRED','status',r.status);
    END IF;

    IF r.financial_terms_set_at IS NOT NULL
       OR r.fee_obligation_id IS NOT NULL
       OR COALESCE(r.payment_confirmed_amount,0)>0
       OR COALESCE(r.paid,false)
       OR r.session_date IS NOT NULL THEN
      RETURN jsonb_build_object('ok',false,'code','RATTRAPAGE_DECISION_FINANCIALLY_LOCKED','status',r.status);
    END IF;
  END IF;

  UPDATE public.rattrapages
  SET status=v_status,
      validated_by=v_uid,
      validated_by_name=v_name,
      validated_by_role=v_role,
      validated_date=pg_catalog.to_char(pg_catalog.timezone('Africa/Kinshasa',pg_catalog.now())::date,'YYYY-MM-DD'),
      note=COALESCE(v_note,note),
      d2_validated=CASE
        WHEN v_role='direction2' AND v_decision='approved' THEN true
        ELSE COALESCE(d2_validated,false)
      END,
      validated_by_d2=CASE WHEN v_role='direction2' THEN v_uid ELSE validated_by_d2 END,
      validated_by_d2_name=CASE WHEN v_role='direction2' THEN v_name ELSE validated_by_d2_name END
  WHERE id=r.id;

  PERFORM private.write_audit_event(
    v_uid,v_name,'rattrapage_'||v_status,
    jsonb_build_object(
      'rattrapage_id',r.id,
      'student_id',r.sid,
      'decision',v_decision,
      'actor_role',v_role,
      'previous_status',r.status,
      'note',v_note
    ),
    r.id
  );

  RETURN jsonb_build_object(
    'ok',true,
    'code','RATTRAPAGE_'||upper(v_status),
    'status',v_status,
    'rattrapage_id',r.id,
    'validated_by_role',v_role
  );
END;
$$;

-- Redéfinition de la planification avec heure 00:00–23:59 stricte.
CREATE OR REPLACE FUNCTION public.schedule_rattrapage_session(
  p_rattrapage_id text,
  p_session_date date,
  p_session_time text DEFAULT NULL,
  p_session_place text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_uid text := private.current_app_user_id();
  v_name text := private.rattrapage_actor_name();
  r public.rattrapages%rowtype;
  v_today date := pg_catalog.timezone('Africa/Kinshasa',pg_catalog.now())::date;
  v_time text := NULLIF(btrim(COALESCE(p_session_time,'')),'');
  v_place text := NULLIF(btrim(COALESCE(p_session_place,'')),'');
BEGIN
  IF private.current_app_role() IS DISTINCT FROM 'direction' OR v_uid IS NULL OR v_name IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','DIRECTION1_REQUIRED');
  END IF;
  IF p_session_date IS NULL OR p_session_date<v_today THEN
    RETURN jsonb_build_object('ok',false,'code','SESSION_DATE_INVALID');
  END IF;
  IF v_time IS NOT NULL AND v_time !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' THEN
    RETURN jsonb_build_object('ok',false,'code','SESSION_TIME_INVALID');
  END IF;
  IF v_place IS NOT NULL AND length(v_place)>180 THEN
    RETURN jsonb_build_object('ok',false,'code','SESSION_PLACE_INVALID');
  END IF;

  SELECT * INTO r FROM public.rattrapages WHERE id=p_rattrapage_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','RATTRAPAGE_NOT_FOUND'); END IF;
  IF COALESCE(r.archived,false) THEN RETURN jsonb_build_object('ok',false,'code','RATTRAPAGE_ARCHIVED'); END IF;
  IF r.status IS DISTINCT FROM 'validated' THEN RETURN jsonb_build_object('ok',false,'code','RATTRAPAGE_NOT_VALIDATED'); END IF;
  IF NOT COALESCE(r.paid,false) THEN RETURN jsonb_build_object('ok',false,'code','PAYMENT_REQUIRED'); END IF;
  IF r.teacher_id IS NULL THEN RETURN jsonb_build_object('ok',false,'code','TEACHER_REQUIRED'); END IF;
  IF COALESCE(r.done,false) THEN RETURN jsonb_build_object('ok',false,'code','RATTRAPAGE_ALREADY_DONE'); END IF;

  UPDATE public.rattrapages
  SET session_date=pg_catalog.to_char(p_session_date,'YYYY-MM-DD'),
      session_time=v_time,
      session_place=v_place
  WHERE id=r.id;

  PERFORM private.write_audit_event(
    v_uid,v_name,'rattrapage_session_scheduled',
    jsonb_build_object('rattrapage_id',r.id,'session_date',p_session_date,'session_time',v_time,'session_place',v_place),r.id
  );

  RETURN jsonb_build_object(
    'ok',true,'code','RATTRAPAGE_SESSION_SCHEDULED','rattrapage_id',r.id,
    'session_date',p_session_date,'session_time',v_time,'session_place',v_place
  );
END;
$$;

ROLLBACK;
