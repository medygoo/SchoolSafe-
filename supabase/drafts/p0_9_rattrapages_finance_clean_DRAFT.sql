-- ==========================================================================
-- SchoolSafe P0-9 — FINANCE RATTRAPAGE / LEDGER / 60-40
-- DRAFT — NE PAS APPLIQUER EN PRODUCTION
-- À relire avec p0_9_rattrapages_core_clean_DRAFT.sql
-- ROLLBACK final volontaire.
-- ==========================================================================

BEGIN;

-- --------------------------------------------------------------------------
-- 1. Colonnes financières additives
-- --------------------------------------------------------------------------
ALTER TABLE public.settings
  ADD COLUMN IF NOT EXISTS rattrapage_share_teacher numeric(5,2);

UPDATE public.settings
SET rattrapage_share_teacher=COALESCE(rattrapage_share_teacher,60)
WHERE id='main';

ALTER TABLE public.student_fee_obligations
  ADD COLUMN IF NOT EXISTS manual_allocation_only boolean NOT NULL DEFAULT false;

ALTER TABLE public.rattrapages
  ADD COLUMN IF NOT EXISTS school_year text,
  ADD COLUMN IF NOT EXISTS period_month date,
  ADD COLUMN IF NOT EXISTS teacher_share_pct numeric(5,2),
  ADD COLUMN IF NOT EXISTS teacher_share_amount numeric(14,2),
  ADD COLUMN IF NOT EXISTS school_share_amount numeric(14,2),
  ADD COLUMN IF NOT EXISTS currency text,
  ADD COLUMN IF NOT EXISTS fee_obligation_id text,
  ADD COLUMN IF NOT EXISTS financial_terms_set_at timestamptz,
  ADD COLUMN IF NOT EXISTS financial_terms_set_by text,
  ADD COLUMN IF NOT EXISTS payment_completed_at timestamptz,
  ADD COLUMN IF NOT EXISTS payment_confirmed_amount numeric(14,2);

UPDATE public.rattrapages
SET currency=COALESCE(NULLIF(upper(btrim(currency)),''),'USD')
WHERE currency IS NULL OR btrim(currency)='';

ALTER TABLE public.rattrapages
  ALTER COLUMN currency SET DEFAULT 'USD';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.rattrapages'::regclass
      AND conname='rattrapages_currency_check'
  ) THEN
    ALTER TABLE public.rattrapages
      ADD CONSTRAINT rattrapages_currency_check
      CHECK (currency IS NULL OR currency ~ '^[A-Z]{3}$');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.rattrapages'::regclass
      AND conname='rattrapages_teacher_share_pct_check'
  ) THEN
    ALTER TABLE public.rattrapages
      ADD CONSTRAINT rattrapages_teacher_share_pct_check
      CHECK (teacher_share_pct IS NULL OR teacher_share_pct BETWEEN 0 AND 100);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.rattrapages'::regclass
      AND conname='rattrapages_teacher_share_amount_check'
  ) THEN
    ALTER TABLE public.rattrapages
      ADD CONSTRAINT rattrapages_teacher_share_amount_check
      CHECK (teacher_share_amount IS NULL OR teacher_share_amount >= 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.rattrapages'::regclass
      AND conname='rattrapages_school_share_amount_check'
  ) THEN
    ALTER TABLE public.rattrapages
      ADD CONSTRAINT rattrapages_school_share_amount_check
      CHECK (school_share_amount IS NULL OR school_share_amount >= 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.rattrapages'::regclass
      AND conname='rattrapages_payment_confirmed_amount_check'
  ) THEN
    ALTER TABLE public.rattrapages
      ADD CONSTRAINT rattrapages_payment_confirmed_amount_check
      CHECK (payment_confirmed_amount IS NULL OR payment_confirmed_amount >= 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.rattrapages'::regclass
      AND conname='rattrapages_fee_obligation_fkey'
  ) THEN
    ALTER TABLE public.rattrapages
      ADD CONSTRAINT rattrapages_fee_obligation_fkey
      FOREIGN KEY (fee_obligation_id)
      REFERENCES public.student_fee_obligations(id)
      ON DELETE RESTRICT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.rattrapages'::regclass
      AND conname='rattrapages_financial_terms_set_by_fkey'
  ) THEN
    ALTER TABLE public.rattrapages
      ADD CONSTRAINT rattrapages_financial_terms_set_by_fkey
      FOREIGN KEY (financial_terms_set_by)
      REFERENCES public.users(id)
      ON DELETE SET NULL;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_rattrapages_fee_obligation
ON public.rattrapages(fee_obligation_id)
WHERE fee_obligation_id IS NOT NULL;

INSERT INTO public.fee_types(id,label,category,trimestre,montant_defaut,active)
VALUES ('ft_rattrapage','Cours de rattrapage','rattrapage',NULL,0,true)
ON CONFLICT (id) DO UPDATE
SET label=EXCLUDED.label,
    category=EXCLUDED.category,
    active=true;

-- --------------------------------------------------------------------------
-- 2. Ledger P0-1 durci
--    Même signature. Les obligations manuelles ne sont jamais auto-allouées.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_payment_transaction(
  p_sid text,
  p_amount numeric,
  p_currency text DEFAULT 'USD'::text,
  p_payment_method text DEFAULT 'cash'::text,
  p_external_reference text DEFAULT NULL::text,
  p_note text DEFAULT NULL::text,
  p_payment_date date DEFAULT NULL::date,
  p_allocations jsonb DEFAULT NULL::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  role_code text := private.current_app_role();
  uid text := private.current_app_user_id();
  actor_name text;
  yr text;
  txid text := 'ptx_'||replace(pg_catalog.gen_random_uuid()::text,'-','');
  receipt text;
  curr text := upper(btrim(COALESCE(p_currency,'USD')));
  method text := lower(btrim(COALESCE(p_payment_method,'cash')));
  remaining numeric(14,2) := p_amount;
  allocated numeric(14,2) := 0;
  rec record;
  piece numeric(14,2);
  item jsonb;
  v_payment_date date := COALESCE(p_payment_date,pg_catalog.timezone('Africa/Kinshasa',pg_catalog.now())::date);
  v_outstanding numeric(14,2);
BEGIN
  IF role_code NOT IN ('direction','direction3') THEN
    RAISE EXCEPTION 'Accès refusé' USING errcode='42501';
  END IF;
  IF uid IS NULL THEN
    RAISE EXCEPTION 'Compte SchoolSafe non relié' USING errcode='42501';
  END IF;

  SELECT u.name INTO actor_name
  FROM public.users u
  WHERE u.id=uid AND u.status='active';

  IF NULLIF(btrim(COALESCE(actor_name,'')),'') IS NULL THEN
    RAISE EXCEPTION 'Profil SchoolSafe actif introuvable' USING errcode='42501';
  END IF;

  IF p_amount IS NULL OR p_amount<=0 THEN
    RAISE EXCEPTION 'Montant invalide' USING errcode='22023';
  END IF;
  IF curr !~ '^[A-Z]{3}$' OR method NOT IN ('cash','bank','mobile_money','other') THEN
    RAISE EXCEPTION 'Paramètres de paiement invalides' USING errcode='22023';
  END IF;
  IF NOT EXISTS(
    SELECT 1 FROM public.students
    WHERE id=p_sid AND NOT COALESCE(archived,false)
  ) THEN
    RAISE EXCEPTION 'Élève introuvable ou archivé' USING errcode='P0002';
  END IF;

  yr := private.current_school_year();
  receipt := private.next_payment_receipt_no(yr);

  INSERT INTO public.payment_transactions(
    id,sid,school_year,amount,currency,payment_date,payment_method,
    external_reference,receipt_no,status,recorded_by,
    recorded_by_name,recorded_by_role,note
  ) VALUES (
    txid,p_sid,yr,p_amount,curr,v_payment_date,method,
    NULLIF(btrim(p_external_reference),''),receipt,'confirmed',uid,
    actor_name,role_code,NULLIF(btrim(p_note),'')
  );

  IF p_allocations IS NOT NULL
     AND jsonb_typeof(p_allocations)='array'
     AND jsonb_array_length(p_allocations)>0 THEN

    FOR item IN SELECT value FROM jsonb_array_elements(p_allocations)
    LOOP
      BEGIN
        piece := (item->>'amount')::numeric;
      EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'Allocation invalide' USING errcode='22023';
      END;

      IF NULLIF(btrim(COALESCE(item->>'obligation_id','')),'') IS NULL
         OR piece IS NULL OR piece<=0 THEN
        RAISE EXCEPTION 'Allocation invalide' USING errcode='22023';
      END IF;

      -- Verrou : le solde contrôlé reste vrai jusqu'à l'insertion.
      PERFORM 1
      FROM public.student_fee_obligations o
      WHERE o.id=item->>'obligation_id'
        AND o.sid=p_sid
        AND o.school_year=yr
        AND o.currency=curr
        AND o.active
      FOR UPDATE;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Obligation incompatible avec ce paiement' USING errcode='22023';
      END IF;

      SELECT greatest(
        o.amount_due-COALESCE((
          SELECT sum(a.amount)
          FROM public.payment_allocations a
          JOIN public.payment_transactions t ON t.id=a.transaction_id
          WHERE a.obligation_id=o.id AND t.status='confirmed'
        ),0),
        0
      )::numeric(14,2)
      INTO v_outstanding
      FROM public.student_fee_obligations o
      WHERE o.id=item->>'obligation_id';

      IF v_outstanding IS NULL OR piece>v_outstanding THEN
        RAISE EXCEPTION 'Allocation supérieure au solde de l''obligation' USING errcode='22023';
      END IF;

      INSERT INTO public.payment_allocations(transaction_id,obligation_id,amount)
      VALUES (txid,item->>'obligation_id',piece);
      allocated := allocated+piece;
    END LOOP;

    IF allocated<>p_amount THEN
      RAISE EXCEPTION 'Somme des allocations incorrecte' USING errcode='22023';
    END IF;
  ELSE
    -- Paiement général : JAMAIS de rattrapage/manual-only implicitement.
    FOR rec IN
      WITH balances AS (
        SELECT o.id,o.due_date,o.installment_no,o.amount_due,
          COALESCE(sum(a.amount) FILTER (WHERE t.status='confirmed'),0)::numeric AS paid
        FROM public.student_fee_obligations o
        LEFT JOIN public.payment_allocations a ON a.obligation_id=o.id
        LEFT JOIN public.payment_transactions t ON t.id=a.transaction_id
        WHERE o.sid=p_sid
          AND o.school_year=yr
          AND o.currency=curr
          AND o.active
          AND NOT COALESCE(o.manual_allocation_only,false)
        GROUP BY o.id,o.due_date,o.installment_no,o.amount_due
      )
      SELECT id,greatest(amount_due-paid,0)::numeric(14,2) AS outstanding
      FROM balances
      WHERE amount_due-paid>0
      ORDER BY due_date NULLS LAST,installment_no,id
    LOOP
      EXIT WHEN remaining<=0;
      piece := least(remaining,rec.outstanding);
      INSERT INTO public.payment_allocations(transaction_id,obligation_id,amount)
      VALUES (txid,rec.id,piece);
      remaining := remaining-piece;
    END LOOP;

    IF remaining<>0 THEN
      RAISE EXCEPTION 'Montant supérieur au solde exigible ou aucune obligation configurée' USING errcode='22023';
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'contract_version',2,
    'transaction_id',txid,
    'receipt_no',receipt,
    'student_id',p_sid,
    'amount',p_amount,
    'currency',curr,
    'payment_date',v_payment_date,
    'school_year',yr,
    'status','confirmed',
    'recorded_by',uid,
    'recorded_by_name',actor_name,
    'recorded_by_role',role_code,
    'created_at',pg_catalog.now()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.record_payment_transaction(text,numeric,text,text,text,text,date,jsonb)
FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.record_payment_transaction(text,numeric,text,text,text,text,date,jsonb)
TO authenticated,service_role;

-- --------------------------------------------------------------------------
-- 3. Direction 1 fixe les conditions financières
-- --------------------------------------------------------------------------
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
  v_curr text := upper(btrim(COALESCE(p_currency,'USD')));
  v_share numeric(5,2);
  v_obligation_id text;
  v_year text;
  v_confirmed numeric(14,2) := 0;
  v_installment integer;
BEGIN
  IF v_role IS DISTINCT FROM 'direction' OR v_uid IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','DIRECTION1_REQUIRED');
  END IF;

  IF NULLIF(btrim(COALESCE(p_rattrapage_id,'')),'') IS NULL
     OR p_amount IS NULL OR p_amount<=0 OR p_amount>100000000
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
  IF COALESCE(v_rat.archived,false) THEN
    RETURN jsonb_build_object('ok',false,'code','RATTRAPAGE_ARCHIVED');
  END IF;
  IF v_rat.status IS DISTINCT FROM 'validated' THEN
    RETURN jsonb_build_object('ok',false,'code','RATTRAPAGE_NOT_VALIDATED');
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
    SELECT COALESCE(sum(a.amount),0)::numeric(14,2)
    INTO v_confirmed
    FROM public.payment_allocations a
    JOIN public.payment_transactions t ON t.id=a.transaction_id
    WHERE a.obligation_id=v_obligation_id
      AND t.status='confirmed';

    IF v_confirmed>0 THEN
      RETURN jsonb_build_object('ok',false,'code','PAYMENT_ALREADY_STARTED','confirmed_amount',v_confirmed);
    END IF;
  END IF;

  SELECT COALESCE(rattrapage_share_teacher,60)
  INTO v_share
  FROM public.settings
  WHERE id='main';

  IF v_share IS NULL OR v_share<0 OR v_share>100 THEN
    RETURN jsonb_build_object('ok',false,'code','INVALID_TEACHER_SHARE_SETTING');
  END IF;

  v_year := COALESCE(NULLIF(btrim(v_rat.school_year),''),private.current_school_year());

  IF v_obligation_id IS NULL THEN
    -- Respecte l'unicité réelle élève/type/année/échéance sous concurrence.
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtext(COALESCE(v_rat.sid,'')),
      pg_catalog.hashtext(COALESCE(v_year,'')||':ft_rattrapage')
    );

    SELECT COALESCE(max(o.installment_no),0)+1
    INTO v_installment
    FROM public.student_fee_obligations o
    WHERE o.sid=v_rat.sid
      AND o.fee_type_id='ft_rattrapage'
      AND o.school_year=v_year;

    INSERT INTO public.student_fee_obligations(
      sid,fee_type_id,school_year,label,installment_no,amount_due,currency,
      due_date,active,created_by,manual_allocation_only
    ) VALUES (
      v_rat.sid,'ft_rattrapage',v_year,
      format('Rattrapage — %s%s',COALESCE(v_rat.matiere,'matière'),
        CASE WHEN v_rat.period_month IS NULL THEN ''
             ELSE ' — '||pg_catalog.to_char(v_rat.period_month,'YYYY-MM') END),
      v_installment,p_amount,v_curr,p_due_date,true,v_uid,true
    )
    RETURNING id INTO v_obligation_id;
  ELSE
    SELECT installment_no INTO v_installment
    FROM public.student_fee_obligations
    WHERE id=v_obligation_id;

    UPDATE public.student_fee_obligations o
    SET amount_due=p_amount,
        currency=v_curr,
        due_date=p_due_date,
        active=true,
        manual_allocation_only=true,
        updated_at=pg_catalog.now()
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
      school_share_amount=NULL,
      payment_confirmed_amount=0,
      paid=false,
      paid_date=NULL,
      payment_completed_at=NULL,
      financial_terms_set_at=pg_catalog.now(),
      financial_terms_set_by=v_uid,
      school_year=v_year
  WHERE id=v_rat.id;

  PERFORM private.write_audit_event(
    v_uid,
    (SELECT name FROM public.users WHERE id=v_uid),
    'rattrapage_financial_terms_set',
    jsonb_build_object(
      'rattrapage_id',v_rat.id,
      'student_id',v_rat.sid,
      'amount',p_amount,
      'currency',v_curr,
      'teacher_share_pct',v_share,
      'fee_obligation_id',v_obligation_id
    ),
    v_rat.id
  );

  RETURN jsonb_build_object(
    'ok',true,
    'code','RATTRAPAGE_FINANCIAL_TERMS_SET',
    'rattrapage_id',v_rat.id,
    'fee_obligation_id',v_obligation_id,
    'installment_no',v_installment,
    'amount',p_amount,
    'currency',v_curr,
    'teacher_share_pct',v_share,
    'school_share_pct',100-v_share,
    'paid',false
  );
END;
$$;

REVOKE ALL ON FUNCTION public.set_rattrapage_financial_terms(text,numeric,text,date)
FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_rattrapage_financial_terms(text,numeric,text,date)
TO authenticated,service_role;

-- --------------------------------------------------------------------------
-- 4. Réconciliation depuis le ledger : le ledger est la vérité.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.reconcile_rattrapage_obligation(p_obligation_id text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_rat public.rattrapages%rowtype;
  v_due numeric(14,2);
  v_paid numeric(14,2);
  v_last_payment_date date;
  v_full boolean;
  v_teacher numeric(14,2);
BEGIN
  IF p_obligation_id IS NULL THEN RETURN; END IF;

  SELECT * INTO v_rat
  FROM public.rattrapages
  WHERE fee_obligation_id=p_obligation_id
  FOR UPDATE;

  IF NOT FOUND THEN RETURN; END IF;

  SELECT o.amount_due,
         COALESCE(sum(a.amount) FILTER (WHERE t.status='confirmed'),0)::numeric(14,2),
         max(t.payment_date) FILTER (WHERE t.status='confirmed')
  INTO v_due,v_paid,v_last_payment_date
  FROM public.student_fee_obligations o
  LEFT JOIN public.payment_allocations a ON a.obligation_id=o.id
  LEFT JOIN public.payment_transactions t ON t.id=a.transaction_id
  WHERE o.id=p_obligation_id
  GROUP BY o.amount_due;

  IF v_due IS NULL THEN RETURN; END IF;

  v_full := v_due>0 AND v_paid>=v_due;
  v_teacher := CASE WHEN v_full
    THEN round(v_due*COALESCE(v_rat.teacher_share_pct,0)/100.0,2)
    ELSE NULL END;

  UPDATE public.rattrapages
  SET paid=v_full,
      payment_signaled=(v_paid>0),
      payment_confirmed_amount=v_paid,
      paid_date=CASE WHEN v_full AND v_last_payment_date IS NOT NULL
        THEN pg_catalog.to_char(v_last_payment_date,'YYYY-MM-DD') ELSE NULL END,
      payment_completed_at=CASE WHEN v_full
        THEN COALESCE(payment_completed_at,pg_catalog.now()) ELSE NULL END,
      teacher_share_amount=v_teacher,
      school_share_amount=CASE WHEN v_full THEN round(v_due-v_teacher,2) ELSE NULL END
  WHERE id=v_rat.id;
END;
$$;

REVOKE ALL ON FUNCTION private.reconcile_rattrapage_obligation(text)
FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.reconcile_rattrapage_obligation(text) TO service_role;

CREATE OR REPLACE FUNCTION private.trg_reconcile_rattrapage_allocation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
  IF TG_OP='DELETE' THEN
    PERFORM private.reconcile_rattrapage_obligation(OLD.obligation_id);
    RETURN OLD;
  END IF;

  IF TG_OP='UPDATE' AND OLD.obligation_id IS DISTINCT FROM NEW.obligation_id THEN
    PERFORM private.reconcile_rattrapage_obligation(OLD.obligation_id);
  END IF;

  PERFORM private.reconcile_rattrapage_obligation(NEW.obligation_id);
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION private.trg_reconcile_rattrapage_transaction()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  x record;
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    FOR x IN
      SELECT DISTINCT a.obligation_id
      FROM public.payment_allocations a
      WHERE a.transaction_id=NEW.id
    LOOP
      PERFORM private.reconcile_rattrapage_obligation(x.obligation_id);
    END LOOP;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_rattrapage_reconcile_allocation ON public.payment_allocations;
CREATE TRIGGER trg_rattrapage_reconcile_allocation
AFTER INSERT OR UPDATE OR DELETE ON public.payment_allocations
FOR EACH ROW EXECUTE FUNCTION private.trg_reconcile_rattrapage_allocation();

DROP TRIGGER IF EXISTS trg_rattrapage_reconcile_transaction ON public.payment_transactions;
CREATE TRIGGER trg_rattrapage_reconcile_transaction
AFTER UPDATE OF status ON public.payment_transactions
FOR EACH ROW EXECUTE FUNCTION private.trg_reconcile_rattrapage_transaction();

ROLLBACK;
