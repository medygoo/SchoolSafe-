-- ============================================================================
-- SchoolSafe P0-1b — INTEGRITE DES ALLOCATIONS DE PAIEMENT
-- DRAFT — NE PAS APPLIQUER EN PRODUCTION
-- ROLLBACK final volontaire.
--
-- Objectif : toute allocation de paiement devient un fait comptable append-only
-- et ne peut jamais dépasser le reçu ni le solde de l'obligation.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION private.enforce_payment_allocation_integrity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_tx public.payment_transactions%rowtype;
  v_ob public.student_fee_obligations%rowtype;
  v_tx_allocated numeric(14,2) := 0;
  v_ob_paid numeric(14,2) := 0;
BEGIN
  -- Une allocation enregistrée ne se réécrit jamais. La correction d'un
  -- encaissement passe par reverse_payment_transaction(), qui conserve toute
  -- l'histoire du reçu et de ses allocations.
  IF TG_OP IN ('UPDATE','DELETE') THEN
    RAISE EXCEPTION 'ALLOCATION_IMMUTABLE: utilisez la contrepassation de la transaction'
      USING ERRCODE='23514';
  END IF;

  IF NEW.amount IS NULL OR NEW.amount<=0 THEN
    RAISE EXCEPTION 'ALLOCATION_AMOUNT_INVALID'
      USING ERRCODE='23514';
  END IF;

  -- Sérialise tous les encaissements d'un même élève/année/devise. Cela ferme
  -- les courses entre deux postes de Caisse et évite les deadlocks lorsque
  -- plusieurs obligations sont réparties dans des ordres différents.
  SELECT * INTO v_tx
  FROM public.payment_transactions t
  WHERE t.id=NEW.transaction_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PAYMENT_TRANSACTION_NOT_FOUND'
      USING ERRCODE='23503';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('payment-allocation'),
    pg_catalog.hashtext(
      COALESCE(v_tx.sid,'')||':'||COALESCE(v_tx.school_year,'')||':'||COALESCE(v_tx.currency,'')
    )
  );

  IF v_tx.status<>'confirmed' THEN
    RAISE EXCEPTION 'PAYMENT_TRANSACTION_NOT_CONFIRMED'
      USING ERRCODE='23514';
  END IF;

  SELECT * INTO v_ob
  FROM public.student_fee_obligations o
  WHERE o.id=NEW.obligation_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PAYMENT_OBLIGATION_NOT_FOUND'
      USING ERRCODE='23503';
  END IF;

  IF NOT v_ob.active THEN
    RAISE EXCEPTION 'PAYMENT_OBLIGATION_INACTIVE'
      USING ERRCODE='23514';
  END IF;

  IF v_ob.sid IS DISTINCT FROM v_tx.sid THEN
    RAISE EXCEPTION 'ALLOCATION_STUDENT_MISMATCH'
      USING ERRCODE='23514';
  END IF;

  IF v_ob.school_year IS DISTINCT FROM v_tx.school_year THEN
    RAISE EXCEPTION 'ALLOCATION_SCHOOL_YEAR_MISMATCH'
      USING ERRCODE='23514';
  END IF;

  IF v_ob.currency IS DISTINCT FROM v_tx.currency THEN
    RAISE EXCEPTION 'ALLOCATION_CURRENCY_MISMATCH'
      USING ERRCODE='23514';
  END IF;

  -- Une transaction ne peut jamais répartir plus que le montant du reçu.
  SELECT COALESCE(sum(a.amount),0)::numeric(14,2)
  INTO v_tx_allocated
  FROM public.payment_allocations a
  WHERE a.transaction_id=v_tx.id;

  IF v_tx_allocated + NEW.amount > v_tx.amount THEN
    RAISE EXCEPTION 'ALLOCATION_EXCEEDS_TRANSACTION_AMOUNT'
      USING ERRCODE='23514';
  END IF;

  -- Une obligation ne peut jamais recevoir plus que son montant dû au travers
  -- de transactions encore confirmées. Les transactions reversed/voided ne
  -- comptent pas dans le solde payé.
  SELECT COALESCE(sum(a.amount),0)::numeric(14,2)
  INTO v_ob_paid
  FROM public.payment_allocations a
  JOIN public.payment_transactions t ON t.id=a.transaction_id
  WHERE a.obligation_id=v_ob.id
    AND t.status='confirmed';

  IF v_ob_paid + NEW.amount > v_ob.amount_due THEN
    RAISE EXCEPTION 'ALLOCATION_EXCEEDS_OBLIGATION_BALANCE'
      USING ERRCODE='23514';
  END IF;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.enforce_payment_allocation_integrity()
FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.enforce_payment_allocation_integrity()
TO service_role;

DROP TRIGGER IF EXISTS trg_payment_allocation_integrity
ON public.payment_allocations;

CREATE TRIGGER trg_payment_allocation_integrity
BEFORE INSERT OR UPDATE OR DELETE ON public.payment_allocations
FOR EACH ROW
EXECUTE FUNCTION private.enforce_payment_allocation_integrity();

ROLLBACK;
