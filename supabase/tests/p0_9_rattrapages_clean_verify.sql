-- ==========================================================================
-- SchoolSafe P0-9 — VERIFICATION APRES APPLICATION SUR BASE DE TEST
-- LECTURE SEULE. Ne modifie aucune donnée et n'affiche aucun secret.
-- ==========================================================================

-- 1. Colonnes attendues
SELECT
  'columns' AS check_group,
  count(*) FILTER (WHERE table_name='settings' AND column_name IN ('rattrapage_threshold','rattrapage_min_notes','rattrapage_share_teacher')) = 3 AS settings_ok,
  count(*) FILTER (WHERE table_name='rattrapages' AND column_name IN (
    'class_id','class_name_snapshot','school_year','period_month','grade_count','detected_at',
    'teacher_share_pct','teacher_share_amount','school_share_amount','currency',
    'fee_obligation_id','financial_terms_set_at','financial_terms_set_by',
    'payment_completed_at','payment_confirmed_amount','validated_by_name',
    'archived_at','archived_by','archive_reason'
  )) = 19 AS rattrapages_ok,
  count(*) FILTER (WHERE table_name='student_fee_obligations' AND column_name='manual_allocation_only') = 1 AS manual_allocation_ok,
  count(*) FILTER (WHERE table_name='convocations' AND column_name IN ('period_month','school_year')) = 2 AS convocations_ok
FROM information_schema.columns
WHERE table_schema='public'
  AND table_name IN ('settings','rattrapages','student_fee_obligations','convocations');

-- 2. Index d'unicité mensuelle / obligation : chacun doit réellement exister.
SELECT wanted.indexname,
       EXISTS(
         SELECT 1 FROM pg_indexes p
         WHERE p.schemaname='public' AND p.indexname=wanted.indexname
       ) AS exists
FROM (VALUES
  ('uq_rattrapages_auto_sid_subject_month'),
  ('uq_convocations_auto_rattrapage_sid_month'),
  ('uq_rattrapages_fee_obligation')
) AS wanted(indexname)
ORDER BY wanted.indexname;

-- 3. Intégrité référentielle ajoutée au registre.
SELECT wanted.conname,
       EXISTS(
         SELECT 1 FROM pg_constraint c
         WHERE c.conrelid='public.rattrapages'::regclass
           AND c.conname=wanted.conname
       ) AS exists
FROM (VALUES
  ('rattrapages_sid_fkey'),
  ('rattrapages_teacher_id_fkey'),
  ('rattrapages_class_id_fkey'),
  ('rattrapages_fee_obligation_fkey')
) AS wanted(conname)
ORDER BY wanted.conname;

-- 4. RPC publiques attendues : signatures exactes
SELECT
  p.proname,
  pg_get_function_identity_arguments(p.oid) AS args,
  p.prosecdef AS security_definer
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.proname IN (
    'get_rattrapage_settings','set_rattrapage_settings',
    'run_monthly_rattrapage_detection','validate_rattrapage',
    'assign_rattrapage_teacher','schedule_rattrapage_session',
    'mark_rattrapage_done','archive_rattrapage',
    'set_rattrapage_financial_terms','get_rattrapage_center',
    'record_payment_transaction','reverse_payment_transaction'
  )
ORDER BY p.proname,pg_get_function_identity_arguments(p.oid);

-- 5. Fonction interne de détection : service_role uniquement pour l'automatisation.
SELECT
  p.proname,
  has_function_privilege('service_role',p.oid,'EXECUTE') AS service_role_execute,
  has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='private'
  AND p.proname='detect_monthly_rattrapages';

-- 6. Le registre rattrapages ne doit plus être directement mutable/lisible
--    par authenticated après raccordement frontend. Les RPC font foi.
SELECT
  has_table_privilege('authenticated','public.rattrapages','SELECT') AS authenticated_select,
  has_table_privilege('authenticated','public.rattrapages','INSERT') AS authenticated_insert,
  has_table_privilege('authenticated','public.rattrapages','UPDATE') AS authenticated_update,
  has_table_privilege('authenticated','public.rattrapages','DELETE') AS authenticated_delete,
  has_table_privilege('service_role','public.rattrapages','SELECT,INSERT,UPDATE,DELETE') AS service_role_all;

-- 7. Le paiement général doit ignorer les obligations manual-only en auto-allocation.
SELECT
  position('manual_allocation_only' in pg_get_functiondef(p.oid)) > 0 AS manual_only_guard_present,
  position('Allocation supérieure au solde' in pg_get_functiondef(p.oid)) > 0 AS explicit_overallocation_guard_present
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.proname='record_payment_transaction'
  AND pg_get_function_identity_arguments(p.oid)=
      'p_sid text, p_amount numeric, p_currency text, p_payment_method text, p_external_reference text, p_note text, p_payment_date date, p_allocations jsonb';

-- 8. Réconciliation paiement / contrepassation
SELECT tgname,pg_get_triggerdef(oid) AS definition
FROM pg_trigger
WHERE NOT tgisinternal
  AND tgname IN ('trg_rattrapage_reconcile_allocation','trg_rattrapage_reconcile_transaction')
ORDER BY tgname;

-- 9. Notifications : la déduplication et la file Push doivent déjà exister.
SELECT
  EXISTS(SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='notifs' AND indexname='uq_notifs_recipient_dedupe') AS notification_dedupe,
  EXISTS(SELECT 1 FROM pg_trigger WHERE tgrelid='public.notifs'::regclass AND tgname='notifs_queue_push' AND NOT tgisinternal) AS notification_push_trigger;

-- 10. Le mois courant/futur doit être refusé dans la fonction de détection.
SELECT position('PERIOD_NOT_COMPLETE' in pg_get_functiondef(p.oid)) > 0 AS current_month_guard_present
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='private' AND p.proname='detect_monthly_rattrapages';

-- Aucun test ci-dessus ne révèle montant réel, nom d'enfant, token Push ou secret.
