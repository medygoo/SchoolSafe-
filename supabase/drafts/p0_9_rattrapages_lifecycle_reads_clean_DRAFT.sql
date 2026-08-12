-- ==========================================================================
-- SchoolSafe P0-9 — CYCLE DU RATTRAPAGE + LECTURES PAR ROLE
-- DRAFT — NE PAS APPLIQUER EN PRODUCTION
-- ROLLBACK final volontaire.
-- ==========================================================================

BEGIN;

ALTER TABLE public.rattrapages
  ADD COLUMN IF NOT EXISTS class_id text,
  ADD COLUMN IF NOT EXISTS class_name_snapshot text,
  ADD COLUMN IF NOT EXISTS school_year text,
  ADD COLUMN IF NOT EXISTS period_month date,
  ADD COLUMN IF NOT EXISTS grade_count integer,
  ADD COLUMN IF NOT EXISTS teacher_share_pct numeric(5,2),
  ADD COLUMN IF NOT EXISTS teacher_share_amount numeric(14,2),
  ADD COLUMN IF NOT EXISTS school_share_amount numeric(14,2),
  ADD COLUMN IF NOT EXISTS currency text,
  ADD COLUMN IF NOT EXISTS fee_obligation_id text,
  ADD COLUMN IF NOT EXISTS financial_terms_set_at timestamptz,
  ADD COLUMN IF NOT EXISTS financial_terms_set_by text,
  ADD COLUMN IF NOT EXISTS payment_completed_at timestamptz,
  ADD COLUMN IF NOT EXISTS payment_confirmed_amount numeric(14,2),
  ADD COLUMN IF NOT EXISTS validated_by_name text,
  ADD COLUMN IF NOT EXISTS archived_at timestamptz,
  ADD COLUMN IF NOT EXISTS archived_by text,
  ADD COLUMN IF NOT EXISTS archive_reason text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.rattrapages'::regclass
      AND conname='rattrapages_archived_by_fkey'
  ) THEN
    ALTER TABLE public.rattrapages
      ADD CONSTRAINT rattrapages_archived_by_fkey
      FOREIGN KEY (archived_by) REFERENCES public.users(id) ON DELETE SET NULL;
  END IF;
END $$;

-- --------------------------------------------------------------------------
-- Helper acteur
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.rattrapage_actor_name()
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT u.name
  FROM public.users u
  WHERE u.id=private.current_app_user_id()
    AND u.status='active'
  LIMIT 1
$$;

REVOKE ALL ON FUNCTION private.rattrapage_actor_name() FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.rattrapage_actor_name() TO service_role;

-- --------------------------------------------------------------------------
-- 1. Validation pédagogique — Direction 1 ou Direction 2
-- --------------------------------------------------------------------------
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

  SELECT * INTO r FROM public.rattrapages WHERE id=p_rattrapage_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','RATTRAPAGE_NOT_FOUND'); END IF;
  IF COALESCE(r.archived,false) THEN RETURN jsonb_build_object('ok',false,'code','RATTRAPAGE_ARCHIVED'); END IF;
  IF COALESCE(r.done,false) THEN RETURN jsonb_build_object('ok',false,'code','RATTRAPAGE_ALREADY_DONE'); END IF;

  v_status := CASE WHEN v_decision='approved' THEN 'validated' ELSE 'refused' END;

  IF r.status=v_status THEN
    RETURN jsonb_build_object('ok',true,'code','RATTRAPAGE_ALREADY_'||upper(v_status),'status',r.status);
  END IF;
  IF r.status IN ('validated','refused') AND r.status<>v_status THEN
    RETURN jsonb_build_object('ok',false,'code','RATTRAPAGE_DECISION_LOCKED','status',r.status);
  END IF;

  UPDATE public.rattrapages
  SET status=v_status,
      validated_by=v_uid,
      validated_by_name=v_name,
      validated_date=pg_catalog.to_char(pg_catalog.timezone('Africa/Kinshasa',pg_catalog.now())::date,'YYYY-MM-DD'),
      note=COALESCE(v_note,note),
      d2_validated=CASE WHEN v_role='direction2' AND v_decision='approved' THEN true ELSE COALESCE(d2_validated,false) END,
      validated_by_d2=CASE WHEN v_role='direction2' THEN v_uid ELSE validated_by_d2 END,
      validated_by_d2_name=CASE WHEN v_role='direction2' THEN v_name ELSE validated_by_d2_name END
  WHERE id=r.id;

  PERFORM private.write_audit_event(
    v_uid,v_name,'rattrapage_'||v_status,
    jsonb_build_object('rattrapage_id',r.id,'student_id',r.sid,'decision',v_decision,'note',v_note),
    r.id
  );

  RETURN jsonb_build_object('ok',true,'code','RATTRAPAGE_'||upper(v_status),'status',v_status,'rattrapage_id',r.id);
END;
$$;

-- --------------------------------------------------------------------------
-- 2. Affectation / changement enseignant — Direction 1
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assign_rattrapage_teacher(
  p_rattrapage_id text,
  p_teacher_id text
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
  v_confirmed numeric(14,2):=0;
  v_teacher_name text;
BEGIN
  IF private.current_app_role() IS DISTINCT FROM 'direction' OR v_uid IS NULL OR v_name IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','DIRECTION1_REQUIRED');
  END IF;

  SELECT u.name INTO v_teacher_name
  FROM public.users u
  WHERE u.id=p_teacher_id AND u.role='enseignant' AND u.status='active';
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','TEACHER_NOT_FOUND'); END IF;

  SELECT * INTO r FROM public.rattrapages WHERE id=p_rattrapage_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','RATTRAPAGE_NOT_FOUND'); END IF;
  IF COALESCE(r.archived,false) THEN RETURN jsonb_build_object('ok',false,'code','RATTRAPAGE_ARCHIVED'); END IF;
  IF COALESCE(r.done,false) THEN RETURN jsonb_build_object('ok',false,'code','RATTRAPAGE_ALREADY_DONE'); END IF;
  IF r.status='refused' THEN RETURN jsonb_build_object('ok',false,'code','RATTRAPAGE_REFUSED'); END IF;

  IF r.fee_obligation_id IS NOT NULL THEN
    SELECT COALESCE(sum(a.amount),0)::numeric(14,2)
    INTO v_confirmed
    FROM public.payment_allocations a
    JOIN public.payment_transactions t ON t.id=a.transaction_id
    WHERE a.obligation_id=r.fee_obligation_id AND t.status='confirmed';
    IF v_confirmed>0 THEN
      RETURN jsonb_build_object('ok',false,'code','PAYMENT_ALREADY_STARTED');
    END IF;
  END IF;

  UPDATE public.rattrapages SET teacher_id=p_teacher_id WHERE id=r.id;

  PERFORM private.write_audit_event(
    v_uid,v_name,'rattrapage_teacher_assigned',
    jsonb_build_object('rattrapage_id',r.id,'teacher_id',p_teacher_id,'teacher_name',v_teacher_name),r.id
  );

  RETURN jsonb_build_object('ok',true,'code','RATTRAPAGE_TEACHER_ASSIGNED','rattrapage_id',r.id,'teacher_id',p_teacher_id,'teacher_name',v_teacher_name);
END;
$$;

-- --------------------------------------------------------------------------
-- 3. Planification — Direction 1, paiement complet obligatoire
-- --------------------------------------------------------------------------
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
  IF v_time IS NOT NULL AND v_time !~ '^[0-2][0-9]:[0-5][0-9]$' THEN
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

  RETURN jsonb_build_object('ok',true,'code','RATTRAPAGE_SESSION_SCHEDULED','rattrapage_id',r.id,'session_date',p_session_date,'session_time',v_time,'session_place',v_place);
END;
$$;

-- --------------------------------------------------------------------------
-- 4. Cours effectué — Direction 1 ou enseignant affecté
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mark_rattrapage_done(
  p_rattrapage_id text,
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
  v_note text := NULLIF(btrim(COALESCE(p_note,'')),'');
  r public.rattrapages%rowtype;
BEGIN
  IF v_uid IS NULL OR v_name IS NULL OR v_role NOT IN ('direction','enseignant') THEN
    RETURN jsonb_build_object('ok',false,'code','FORBIDDEN');
  END IF;

  SELECT * INTO r FROM public.rattrapages WHERE id=p_rattrapage_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','RATTRAPAGE_NOT_FOUND'); END IF;
  IF COALESCE(r.archived,false) THEN RETURN jsonb_build_object('ok',false,'code','RATTRAPAGE_ARCHIVED'); END IF;
  IF r.status IS DISTINCT FROM 'validated' THEN RETURN jsonb_build_object('ok',false,'code','RATTRAPAGE_NOT_VALIDATED'); END IF;
  IF NOT COALESCE(r.paid,false) THEN RETURN jsonb_build_object('ok',false,'code','PAYMENT_REQUIRED'); END IF;
  IF r.session_date IS NULL THEN RETURN jsonb_build_object('ok',false,'code','SESSION_NOT_SCHEDULED'); END IF;
  IF v_role='enseignant' AND r.teacher_id IS DISTINCT FROM v_uid THEN
    RETURN jsonb_build_object('ok',false,'code','NOT_ASSIGNED_TEACHER');
  END IF;

  IF COALESCE(r.done,false) THEN
    RETURN jsonb_build_object('ok',true,'code','RATTRAPAGE_ALREADY_DONE','rattrapage_id',r.id,'done_date',r.done_date);
  END IF;

  UPDATE public.rattrapages
  SET done=true,
      done_date=pg_catalog.to_char(pg_catalog.timezone('Africa/Kinshasa',pg_catalog.now())::date,'YYYY-MM-DD'),
      done_note=v_note
  WHERE id=r.id;

  PERFORM private.write_audit_event(
    v_uid,v_name,'rattrapage_done',
    jsonb_build_object('rattrapage_id',r.id,'student_id',r.sid,'teacher_id',r.teacher_id,'note',v_note),r.id
  );

  RETURN jsonb_build_object('ok',true,'code','RATTRAPAGE_DONE','rattrapage_id',r.id,'done',true);
END;
$$;

-- --------------------------------------------------------------------------
-- 5. Archivage — Direction 1, jamais suppression
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.archive_rattrapage(
  p_rattrapage_id text,
  p_reason text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_uid text := private.current_app_user_id();
  v_name text := private.rattrapage_actor_name();
  v_reason text := NULLIF(btrim(COALESCE(p_reason,'')),'');
  r public.rattrapages%rowtype;
BEGIN
  IF private.current_app_role() IS DISTINCT FROM 'direction' OR v_uid IS NULL OR v_name IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','DIRECTION1_REQUIRED');
  END IF;
  IF v_reason IS NULL OR length(v_reason)<3 OR length(v_reason)>500 THEN
    RETURN jsonb_build_object('ok',false,'code','ARCHIVE_REASON_REQUIRED');
  END IF;

  SELECT * INTO r FROM public.rattrapages WHERE id=p_rattrapage_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','RATTRAPAGE_NOT_FOUND'); END IF;
  IF COALESCE(r.archived,false) THEN
    RETURN jsonb_build_object('ok',true,'code','RATTRAPAGE_ALREADY_ARCHIVED','rattrapage_id',r.id);
  END IF;
  IF NOT COALESCE(r.done,false) AND r.status IS DISTINCT FROM 'refused' THEN
    RETURN jsonb_build_object('ok',false,'code','RATTRAPAGE_NOT_CLOSABLE');
  END IF;

  UPDATE public.rattrapages
  SET archived=true,
      archived_at=pg_catalog.now(),
      archived_by=v_uid,
      archive_reason=v_reason
  WHERE id=r.id;

  PERFORM private.write_audit_event(
    v_uid,v_name,'rattrapage_archived',
    jsonb_build_object('rattrapage_id',r.id,'reason',v_reason),r.id
  );

  RETURN jsonb_build_object('ok',true,'code','RATTRAPAGE_ARCHIVED','rattrapage_id',r.id);
END;
$$;

-- --------------------------------------------------------------------------
-- 6. Centre filtré selon rôle
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_rattrapage_center(
  p_sid text DEFAULT NULL,
  p_period_month date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_role text := private.current_app_role();
  v_uid text := private.current_app_user_id();
  v_month date := CASE WHEN p_period_month IS NULL THEN NULL ELSE pg_catalog.date_trunc('month',p_period_month)::date END;
  v_items jsonb;
BEGIN
  IF v_role NOT IN ('direction','direction2','direction3','enseignant','parent') OR v_uid IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','FORBIDDEN');
  END IF;

  SELECT COALESCE(jsonb_agg(q.item ORDER BY q.sort_month DESC,q.sort_subject,q.sort_student),'[]'::jsonb)
  INTO v_items
  FROM (
    SELECT
      COALESCE(r.period_month,date '1900-01-01') AS sort_month,
      lower(COALESCE(r.matiere,'')) AS sort_subject,
      lower(COALESCE(s.name,'')) AS sort_student,
      CASE
        WHEN v_role='direction3' THEN
          jsonb_strip_nulls(jsonb_build_object(
            'id',r.id,
            'student_id',r.sid,
            'student_name',s.name,
            'class_id',COALESCE(r.class_id,s.cid),
            'class_name',COALESCE(r.class_name_snapshot,cl.name),
            'subject',r.matiere,
            'status',r.status,
            'amount',r.amount,
            'currency',r.currency,
            'paid',COALESCE(r.paid,false),
            'paid_date',r.paid_date,
            'payment_confirmed_amount',COALESCE(r.payment_confirmed_amount,0),
            'balance_due',greatest(COALESCE(r.amount,0)-COALESCE(r.payment_confirmed_amount,0),0),
            'fee_obligation_id',r.fee_obligation_id
          ))
        ELSE
          jsonb_strip_nulls(
            jsonb_build_object(
              'id',r.id,
              'student_id',r.sid,
              'student_name',s.name,
              'class_id',COALESCE(r.class_id,s.cid),
              'class_name',COALESCE(r.class_name_snapshot,cl.name),
              'teacher_id',r.teacher_id,
              'teacher_name',tu.name,
              'subject',r.matiere,
              'reason',r.motif,
              'status',r.status,
              'score',r.score,
              'grade_count',r.grade_count,
              'period_month',r.period_month,
              'school_year',r.school_year,
              'trimestre',r.trimestre,
              'validated_by_name',r.validated_by_name,
              'validated_date',r.validated_date,
              'd2_validated',COALESCE(r.d2_validated,false),
              'session_date',r.session_date,
              'session_time',r.session_time,
              'session_place',r.session_place,
              'done',COALESCE(r.done,false),
              'done_date',r.done_date,
              'done_note',r.done_note
            )
            || CASE
              WHEN v_role='direction' THEN jsonb_build_object(
                'amount',r.amount,
                'currency',r.currency,
                'paid',COALESCE(r.paid,false),
                'paid_date',r.paid_date,
                'payment_confirmed_amount',COALESCE(r.payment_confirmed_amount,0),
                'balance_due',greatest(COALESCE(r.amount,0)-COALESCE(r.payment_confirmed_amount,0),0),
                'fee_obligation_id',r.fee_obligation_id,
                'teacher_share_pct',r.teacher_share_pct,
                'teacher_share_amount',r.teacher_share_amount,
                'school_share_amount',r.school_share_amount,
                'financial_terms_set_at',r.financial_terms_set_at,
                'payment_completed_at',r.payment_completed_at,
                'archived',COALESCE(r.archived,false),
                'archived_at',r.archived_at,
                'archive_reason',r.archive_reason
              )
              WHEN v_role='parent' THEN jsonb_build_object(
                'amount',r.amount,
                'currency',r.currency,
                'paid',COALESCE(r.paid,false),
                'paid_date',r.paid_date,
                'balance_due',greatest(COALESCE(r.amount,0)-COALESCE(r.payment_confirmed_amount,0),0)
              )
              ELSE '{}'::jsonb
            END
          )
      END AS item
    FROM public.rattrapages r
    JOIN public.students s ON s.id=r.sid
    LEFT JOIN public.classes cl ON cl.id=COALESCE(r.class_id,s.cid)
    LEFT JOIN public.users tu ON tu.id=r.teacher_id
    WHERE NOT COALESCE(r.archived,false)
      AND (p_sid IS NULL OR r.sid=p_sid)
      AND (v_month IS NULL OR r.period_month=v_month)
      AND (
        v_role IN ('direction','direction2')
        OR (v_role='direction3' AND r.fee_obligation_id IS NOT NULL)
        OR (v_role='enseignant' AND r.teacher_id=v_uid)
        OR (v_role='parent' AND private.owns_student(r.sid))
      )
  ) q;

  RETURN jsonb_build_object(
    'ok',true,
    'code','RATTRAPAGE_CENTER_READY',
    'role',v_role,
    'items',v_items
  );
END;
$$;

-- --------------------------------------------------------------------------
-- 7. Droits : mutations et lecture métier passent par RPC.
-- À appliquer seulement après raccordement Claude.
-- --------------------------------------------------------------------------
REVOKE ALL ON public.rattrapages FROM anon,authenticated;
GRANT ALL ON public.rattrapages TO service_role;

REVOKE ALL ON FUNCTION public.validate_rattrapage(text,text,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.assign_rattrapage_teacher(text,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.schedule_rattrapage_session(text,date,text,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.mark_rattrapage_done(text,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.archive_rattrapage(text,text) FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.get_rattrapage_center(text,date) FROM PUBLIC,anon;

GRANT EXECUTE ON FUNCTION public.validate_rattrapage(text,text,text) TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.assign_rattrapage_teacher(text,text) TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.schedule_rattrapage_session(text,date,text,text) TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.mark_rattrapage_done(text,text) TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.archive_rattrapage(text,text) TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.get_rattrapage_center(text,date) TO authenticated,service_role;

ROLLBACK;
