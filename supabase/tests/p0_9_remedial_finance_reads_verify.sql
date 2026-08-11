-- P0-9 rattrapages — vérification LECTURE SEULE après application sur une base de test.
-- Ne crée ni élève, ni paiement, ni rattrapage.

-- 1. Colonnes indispensables.
select
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='student_fee_obligations' and column_name='manual_allocation_only') as has_manual_allocation_only,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='rattrapages' and column_name='fee_obligation_id') as has_fee_obligation_id,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='rattrapages' and column_name='currency') as has_rattrapage_currency,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='rattrapages' and column_name='teacher_share_pct') as has_teacher_share_pct,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='rattrapages' and column_name='teacher_share_amount') as has_teacher_share_amount,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='rattrapages' and column_name='payment_completed_at') as has_payment_completed_at;

-- 2. Type de frais et unicité existante : un élève peut avoir plusieurs
-- rattrapages grâce à des installment_no différents.
select
  exists(select 1 from public.fee_types where id='ft_rattrapage' and category='rattrapage') as remedial_fee_type_present,
  exists(
    select 1 from pg_constraint
    where conrelid='public.student_fee_obligations'::regclass
      and conname='student_fee_obligations_sid_fee_type_id_school_year_install_key'
  ) as original_obligation_uniqueness_present;

-- 3. Fonctions publiques attendues.
select
  to_regprocedure('public.set_rattrapage_financial_terms(text,numeric,text,date)') is not null as has_set_financial_terms,
  to_regprocedure('public.get_rattrapage_center(text,date)') is not null as has_role_filtered_center,
  to_regprocedure('public.get_rattrapage_settings()') is not null as has_rattrapage_settings,
  to_regprocedure('private.reconcile_rattrapage_obligation(text)') is not null as has_reconcile_function;

-- 4. Les deux protections qui ont motivé v2/v3 doivent se trouver dans les
-- définitions effectives : pas d'auto-allocation du rattrapage et séquence sûre.
select
  position('manual_allocation_only' in pg_get_functiondef('public.record_payment_transaction(text,numeric,text,text,text,text,date,jsonb)'::regprocedure)) > 0
    as payment_auto_allocation_excludes_manual_only,
  position('pg_advisory_xact_lock' in pg_get_functiondef('public.set_rattrapage_financial_terms(text,numeric,text,date)'::regprocedure)) > 0
    as remedial_installment_uses_advisory_lock,
  position('max(o.installment_no)' in pg_get_functiondef('public.set_rattrapage_financial_terms(text,numeric,text,date)'::regprocedure)) > 0
    as remedial_installment_is_sequential;

-- 5. Réconciliation : allocation + contrepassation.
select
  exists(select 1 from pg_trigger where tgrelid='public.payment_allocations'::regclass and tgname='trg_rattrapage_reconcile_allocation' and not tgisinternal)
    as allocation_reconcile_trigger,
  exists(select 1 from pg_trigger where tgrelid='public.payment_transactions'::regclass and tgname='trg_rattrapage_reconcile_transaction' and not tgisinternal)
    as reversal_reconcile_trigger;

-- 6. Permissions RPC : jamais anon.
select
  has_function_privilege('anon','public.set_rattrapage_financial_terms(text,numeric,text,date)','EXECUTE') as anon_can_set_financial_terms,
  has_function_privilege('authenticated','public.set_rattrapage_financial_terms(text,numeric,text,date)','EXECUTE') as authenticated_can_call_guarded_setter,
  has_function_privilege('anon','public.get_rattrapage_center(text,date)','EXECUTE') as anon_can_read_rattrapages,
  has_function_privilege('authenticated','public.get_rattrapage_center(text,date)','EXECUTE') as authenticated_can_call_guarded_center;

-- Attendu : anon_can_* = false ; authenticated_can_* = true.

-- 7. La table garde sa politique directe historique Direction1 seulement.
-- Les autres rôles passent par la RPC filtrée, pas par un SELECT direct ajouté.
select policyname,cmd,roles,qual,with_check
from pg_policies
where schemaname='public' and tablename='rattrapages'
order by policyname;

-- 8. Contrôle sans valeurs sensibles : compte des obligations rattrapage.
select
  count(*) as remedial_obligations_total,
  count(*) filter(where manual_allocation_only) as remedial_manual_only_total,
  count(distinct sid) as students_with_remedial_obligation
from public.student_fee_obligations
where fee_type_id='ft_rattrapage';
