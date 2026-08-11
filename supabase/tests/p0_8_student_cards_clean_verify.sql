-- P0-8 — vérification lecture seule après application sur base jetable/cible.
-- Ne retourne jamais la valeur du secret HMAC.

WITH checks AS (
  SELECT 'student_cards_exists' AS check_name,
         to_regclass('public.student_cards') IS NOT NULL AS ok
  UNION ALL
  SELECT 'student_card_prefix_exists',
         EXISTS (
           SELECT 1 FROM information_schema.columns
           WHERE table_schema='public' AND table_name='settings'
             AND column_name='student_card_prefix'
         )
  UNION ALL
  SELECT 'student_cards_rls_enabled',
         COALESCE((SELECT relrowsecurity FROM pg_class WHERE oid='public.student_cards'::regclass),false)
  UNION ALL
  SELECT 'authenticated_has_no_direct_select',
         NOT has_table_privilege('authenticated','public.student_cards','SELECT')
  UNION ALL
  SELECT 'anon_has_no_direct_select',
         NOT has_table_privilege('anon','public.student_cards','SELECT')
  UNION ALL
  SELECT 'one_active_index_exists',
         EXISTS (
           SELECT 1 FROM pg_indexes
           WHERE schemaname='public' AND tablename='student_cards'
             AND indexname='student_cards_one_active_per_student_year_idx'
         )
  UNION ALL
  SELECT 'update_guard_trigger_exists',
         EXISTS (
           SELECT 1 FROM pg_trigger
           WHERE tgrelid='public.student_cards'::regclass
             AND tgname='trg_guard_student_card_update' AND NOT tgisinternal
         )
  UNION ALL
  SELECT 'delete_guard_trigger_exists',
         EXISTS (
           SELECT 1 FROM pg_trigger
           WHERE tgrelid='public.student_cards'::regclass
             AND tgname='trg_block_student_card_delete' AND NOT tgisinternal
         )
  UNION ALL
  SELECT 'issue_rpc_exists',
         to_regprocedure('public.issue_student_card(text,text,text,text,text,text,text,text)') IS NOT NULL
  UNION ALL
  SELECT 'lost_rpc_exists',
         to_regprocedure('public.declare_student_card_lost(text,text)') IS NOT NULL
  UNION ALL
  SELECT 'revoke_rpc_exists',
         to_regprocedure('public.revoke_student_card(text,text)') IS NOT NULL
  UNION ALL
  SELECT 'print_rpc_exists',
         to_regprocedure('public.count_student_card_print(text)') IS NOT NULL
  UNION ALL
  SELECT 'center_rpc_exists',
         to_regprocedure('public.get_student_card_center(text,text)') IS NOT NULL
  UNION ALL
  SELECT 'verify_rpc_exists',
         to_regprocedure('public.verify_student_card_qr(text)') IS NOT NULL
  UNION ALL
  SELECT 'authenticated_can_issue_rpc',
         has_function_privilege('authenticated','public.issue_student_card(text,text,text,text,text,text,text,text)','EXECUTE')
  UNION ALL
  SELECT 'authenticated_can_read_center_rpc',
         has_function_privilege('authenticated','public.get_student_card_center(text,text)','EXECUTE')
  UNION ALL
  SELECT 'authenticated_can_verify_rpc',
         has_function_privilege('authenticated','public.verify_student_card_qr(text)','EXECUTE')
  UNION ALL
  SELECT 'anon_cannot_verify_rpc',
         NOT has_function_privilege('anon','public.verify_student_card_qr(text)','EXECUTE')
  UNION ALL
  SELECT 'qr_key_present',
         EXISTS(SELECT 1 FROM private.qr_keys WHERE id='student_card_v1')
  UNION ALL
  SELECT 'qr_key_32_bytes',
         COALESCE((SELECT octet_length(secret)=32 FROM private.qr_keys WHERE id='student_card_v1'),false)
  UNION ALL
  SELECT 'no_multiple_active_cards',
         NOT EXISTS (
           SELECT 1 FROM public.student_cards
           WHERE status='active'
           GROUP BY sid,year HAVING count(*)>1
         )
)
SELECT check_name, ok
FROM checks
ORDER BY check_name;

-- Résumé compact : doit retourner 0 après une installation valide.
WITH checks AS (
  SELECT to_regclass('public.student_cards') IS NOT NULL AS ok
  UNION ALL SELECT EXISTS(SELECT 1 FROM private.qr_keys WHERE id='student_card_v1')
  UNION ALL SELECT NOT has_table_privilege('authenticated','public.student_cards','SELECT')
  UNION ALL SELECT to_regprocedure('public.issue_student_card(text,text,text,text,text,text,text,text)') IS NOT NULL
  UNION ALL SELECT to_regprocedure('public.verify_student_card_qr(text)') IS NOT NULL
)
SELECT count(*) FILTER (WHERE NOT ok) AS failed_core_checks
FROM checks;
