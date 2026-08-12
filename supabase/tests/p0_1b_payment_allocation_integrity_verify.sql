-- ============================================================================
-- SchoolSafe P0-1b — VERIFICATION LECTURE SEULE
-- À lancer APRES application des drafts sur une base de test.
-- Ne modifie aucune donnée et n'affiche aucune donnée personnelle.
-- ============================================================================

-- 1. Trigger / fonction attendus.
SELECT
  EXISTS(
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='private'
      AND p.proname='enforce_payment_allocation_integrity'
      AND p.prosecdef
  ) AS integrity_function_present,
  EXISTS(
    SELECT 1 FROM pg_trigger
    WHERE tgrelid='public.payment_allocations'::regclass
      AND tgname='trg_payment_allocation_integrity'
      AND NOT tgisinternal
  ) AS integrity_trigger_present;

-- 2. Le code du trigger doit couvrir les invariants principaux.
SELECT
  position('ALLOCATION_IMMUTABLE' in pg_get_functiondef(p.oid))>0 AS immutable_guard,
  position('ALLOCATION_EXCEEDS_TRANSACTION_AMOUNT' in pg_get_functiondef(p.oid))>0 AS tx_amount_guard,
  position('ALLOCATION_EXCEEDS_OBLIGATION_BALANCE' in pg_get_functiondef(p.oid))>0 AS obligation_balance_guard,
  position('ALLOCATION_STUDENT_MISMATCH' in pg_get_functiondef(p.oid))>0 AS student_guard,
  position('ALLOCATION_SCHOOL_YEAR_MISMATCH' in pg_get_functiondef(p.oid))>0 AS year_guard,
  position('ALLOCATION_CURRENCY_MISMATCH' in pg_get_functiondef(p.oid))>0 AS currency_guard,
  position('pg_advisory_xact_lock' in pg_get_functiondef(p.oid))>0 AS concurrency_guard
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='private'
  AND p.proname='enforce_payment_allocation_integrity';

-- 3. Préflight des données : tous les compteurs attendus = 0.
-- Aucune identité, aucun montant individuel n'est affiché.
WITH tx_bad AS (
  SELECT a.transaction_id
  FROM public.payment_allocations a
  JOIN public.payment_transactions t ON t.id=a.transaction_id
  GROUP BY a.transaction_id,t.amount
  HAVING sum(a.amount)>t.amount
),
ob_bad AS (
  SELECT a.obligation_id
  FROM public.payment_allocations a
  JOIN public.payment_transactions t ON t.id=a.transaction_id
  JOIN public.student_fee_obligations o ON o.id=a.obligation_id
  WHERE t.status='confirmed'
  GROUP BY a.obligation_id,o.amount_due
  HAVING sum(a.amount)>o.amount_due
),
mismatch AS (
  SELECT a.id
  FROM public.payment_allocations a
  JOIN public.payment_transactions t ON t.id=a.transaction_id
  JOIN public.student_fee_obligations o ON o.id=a.obligation_id
  WHERE t.sid IS DISTINCT FROM o.sid
     OR t.school_year IS DISTINCT FROM o.school_year
     OR t.currency IS DISTINCT FROM o.currency
)
SELECT
  (SELECT count(*) FROM tx_bad) AS transactions_overallocated,
  (SELECT count(*) FROM ob_bad) AS obligations_overallocated,
  (SELECT count(*) FROM mismatch) AS allocation_identity_mismatches;

-- 4. Etat du verrou direct.
-- Avant le fichier AFTER_FRONTEND, les droits peuvent encore être true.
-- Après application du lockdown : les trois doivent être false.
SELECT
  has_table_privilege('authenticated','public.payment_allocations','SELECT') AS authenticated_select,
  has_table_privilege('authenticated','public.payment_allocations','INSERT') AS authenticated_insert,
  has_table_privilege('authenticated','public.payment_allocations','UPDATE') AS authenticated_update,
  has_table_privilege('authenticated','public.payment_allocations','DELETE') AS authenticated_delete;

-- 5. Les anciennes policies de mutation doivent disparaître après lockdown.
SELECT p.policyname,p.cmd
FROM pg_policies p
WHERE p.schemaname='public'
  AND p.tablename='payment_allocations'
ORDER BY p.policyname;

-- 6. payment_transactions doit rester non modifiable directement par authenticated.
SELECT
  has_table_privilege('authenticated','public.payment_transactions','INSERT') AS tx_insert,
  has_table_privilege('authenticated','public.payment_transactions','UPDATE') AS tx_update,
  has_table_privilege('authenticated','public.payment_transactions','DELETE') AS tx_delete;
