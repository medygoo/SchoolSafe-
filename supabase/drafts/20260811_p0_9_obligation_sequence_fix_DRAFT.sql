-- ============================================================================
-- SchoolSafe P0-9 — CORRECTIF DRAFT : numérotation des obligations rattrapage
-- À exécuter après 20260811_p0_9_remedial_finance_reads_DRAFT.sql sur une
-- base de test uniquement. ROLLBACK final volontaire.
--
-- Motif : student_fee_obligations possède déjà l'unicité
-- (sid, fee_type_id, school_year, installment_no). Tous les rattrapages ne
-- peuvent donc pas utiliser installment_no=1.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.set_rattrapage_financial_terms(
  p_rattrapage_id text,
  p_amount numeric,
  p_currency text DEFAULT 'USD',
  p_due_date date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_role text := private.current_app_role();
  v_uid text := private.current_app_user_id();
  v_rat public.rattrapages%rowtype;
  v_curr text := upper(btrim(coalesce(p_currency,'USD')));
  v_share numeric(5,2);
  v_obligation_id text;
  v_year text;
  v_confirmed numeric(14,2) := 0;
  v_installment integer;
BEGIN
  IF v_role IS DISTINCT FROM 'direction' OR v_uid IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','DIRECTION1_REQUIRED');
  END IF;

  IF nullif(btrim(coalesce(p_rattrapage_id,'')),'') IS NULL
     OR p_amount IS NULL OR p_amount <= 0 OR p_amount > 100000000
     OR v_curr !~ '^[A-Z]{3}$' THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR');
  END IF;

  SELECT * INTO v_rat
  FROM public.rattrapages
  WHERE id=p_rattrapage_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'code','RATTRAPAGE_NOT_FOUND');
  END IF;
  IF coalesce(v_rat.archived,false) THEN
    RETURN jsonb_build_object('ok',false,'code','RATTRAPAGE_ARCHIVED');
  END IF;
  IF v_rat.teacher_id IS NULL OR NOT EXISTS(
    SELECT 1 FROM public.users u
    WHERE u.id=v_rat.teacher_id
      AND u.status='active'
      AND u.role='enseignant'
  ) THEN
    RETURN jsonb_build_object('ok',false,'code','TEACHER_REQUIRED');
  END IF;

  v_obligation_id := v_rat.fee_obligation_id;

  IF v_obligation_id IS NOT NULL THEN
    SELECT coalesce(sum(a.amount),0)::numeric(14,2)
    INTO v_confirmed
    FROM public.payment_allocations a
    JOIN public.payment_transactions t ON t.id=a.transaction_id
    WHERE a.obligation_id=v_obligation_id
      AND t.status='confirmed';

    IF v_confirmed > 0 THEN
      RETURN jsonb_build_object(
        'ok',false,'code','PAYMENT_ALREADY_STARTED','confirmed_amount',v_confirmed
      );
    END IF;
  END IF;

  SELECT coalesce(rattrapage_share_teacher,60)
  INTO v_share
  FROM public.settings
  WHERE id='main';

  IF v_share IS NULL OR v_share < 0 OR v_share > 100 THEN
    RETURN jsonb_build_object('ok',false,'code','INVALID_TEACHER_SHARE_SETTING');
  END IF;

  v_year := coalesce(nullif(btrim(v_rat.school_year),''), private.current_school_year());

  IF v_obligation_id IS NULL THEN
    -- Deux Directions/appareils ne doivent jamais choisir le même numéro
    -- d'échéance pour le même élève et la même année.
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext(coalesce(v_rat.sid,'')),
      pg_catalog.hashtext(coalesce(v_year,'')||':ft_rattrapage')
    );

    SELECT coalesce(max(o.installment_no),0)+1
    INTO v_installment
    FROM public.student_fee_obligations o
    WHERE o.sid=v_rat.sid
      AND o.fee_type_id='ft_rattrapage'
      AND o.school_year=v_year;

    v_obligation_id := 'sfo_' || replace(gen_random_uuid()::text,'-','');

    INSERT INTO public.student_fee_obligations(
      id,sid,fee_type_id,school_year,label,installment_no,amount_due,currency,
      due_date,active,created_by,manual_allocation_only
    ) VALUES (
      v_obligation_id,
      v_rat.sid,
      'ft_rattrapage',
      v_year,
      format('Rattrapage — %s%s',coalesce(v_rat.matiere,'matière'),
        CASE WHEN v_rat.period_month IS NULL THEN ''
             ELSE ' — '||to_char(v_rat.period_month,'YYYY-MM') END),
      v_installment,
      p_amount,
      v_curr,
      p_due_date,
      true,
      v_uid,
      true
    );
  ELSE
    UPDATE public.student_fee_obligations o
    SET amount_due=p_amount,
        currency=v_curr,
        due_date=p_due_date,
        active=true,
        manual_allocation_only=true,
        updated_at=now()
    WHERE o.id=v_obligation_id
      AND o.sid=v_rat.sid
      AND o.fee_type_id='ft_rattrapage';

    IF NOT FOUND THEN
      RETURN jsonb_build_object('ok',false,'code','OBLIGATION_LINK_INVALID');
    END IF;
  END IF;

  UPDATE public.rattrapages
  SET amount=p_amount,
      currency=v_curr,
      fee_obligation_id=v_obligation_id,
      teacher_share_pct=v_share,
      teacher_share_amount=NULL,
      paid=false,
      paid_date=NULL,
      payment_completed_at=NULL,
      financial_terms_set_at=now(),
      financial_terms_set_by=v_uid,
      school_year=v_year
  WHERE id=v_rat.id;

  RETURN jsonb_build_object(
    'ok',true,
    'code','RATTRAPAGE_FINANCIAL_TERMS_SET',
    'rattrapage_id',v_rat.id,
    'fee_obligation_id',v_obligation_id,
    'installment_no',v_installment,
    'amount',p_amount,
    'currency',v_curr,
    'teacher_share_pct',v_share,
    'paid',false
  );
END;
$$;

REVOKE ALL ON FUNCTION public.set_rattrapage_financial_terms(text,numeric,text,date)
FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_rattrapage_financial_terms(text,numeric,text,date)
TO authenticated;

ROLLBACK;
