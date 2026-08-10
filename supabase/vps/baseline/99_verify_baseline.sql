-- SchoolSafe VPS baseline - 99 structural verification
-- Run AFTER baseline installation, before Auth user migration and before frontend cutover.

DO $$
DECLARE
  v bigint;
BEGIN
  SELECT count(*) INTO v FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p');
  IF v<>66 THEN RAISE EXCEPTION 'SchoolSafe verify failed: public tables %, expected 66',v; END IF;

  SELECT count(*) INTO v FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='private' AND c.relkind IN ('r','p');
  IF v<>8 THEN RAISE EXCEPTION 'SchoolSafe verify failed: private tables %, expected 8',v; END IF;

  SELECT count(*) INTO v FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.prokind='f';
  IF v<>72 THEN RAISE EXCEPTION 'SchoolSafe verify failed: public functions %, expected 72',v; END IF;

  SELECT count(*) INTO v FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.prokind='f';
  IF v<>58 THEN RAISE EXCEPTION 'SchoolSafe verify failed: private functions %, expected 58',v; END IF;

  SELECT count(*) INTO v FROM pg_constraint con JOIN pg_class c ON c.oid=con.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private') AND con.contype='c';
  IF v<>103 THEN RAISE EXCEPTION 'SchoolSafe verify failed: CHECK constraints %, expected 103',v; END IF;

  SELECT count(*) INTO v FROM pg_constraint con JOIN pg_class c ON c.oid=con.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private') AND con.contype='f';
  IF v<>61 THEN RAISE EXCEPTION 'SchoolSafe verify failed: foreign keys %, expected 61',v; END IF;

  SELECT count(*) INTO v FROM pg_constraint con JOIN pg_class c ON c.oid=con.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private') AND con.contype='p';
  IF v<>74 THEN RAISE EXCEPTION 'SchoolSafe verify failed: primary keys %, expected 74',v; END IF;

  SELECT count(*) INTO v FROM pg_constraint con JOIN pg_class c ON c.oid=con.conrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname IN ('public','private') AND con.contype='u';
  IF v<>11 THEN RAISE EXCEPTION 'SchoolSafe verify failed: unique constraints %, expected 11',v; END IF;

  SELECT count(*) INTO v FROM pg_index i JOIN pg_class idx ON idx.oid=i.indexrelid JOIN pg_class tbl ON tbl.oid=i.indrelid JOIN pg_namespace ns ON ns.oid=tbl.relnamespace LEFT JOIN pg_constraint con ON con.conindid=i.indexrelid WHERE ns.nspname IN ('public','private') AND con.oid IS NULL;
  IF v<>102 THEN RAISE EXCEPTION 'SchoolSafe verify failed: non-constraint indexes %, expected 102',v; END IF;

  SELECT count(*) INTO v FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace WHERE NOT t.tgisinternal AND n.nspname IN ('public','private');
  IF v<>28 THEN RAISE EXCEPTION 'SchoolSafe verify failed: app triggers %, expected 28',v; END IF;

  SELECT count(*) INTO v FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace JOIN pg_proc p ON p.oid=t.tgfoid JOIN pg_namespace fn ON fn.oid=p.pronamespace WHERE NOT t.tgisinternal AND n.nspname='auth' AND fn.nspname='private';
  IF v<>2 THEN RAISE EXCEPTION 'SchoolSafe verify failed: auth SchoolSafe triggers %, expected 2',v; END IF;

  SELECT count(*) INTO v FROM pg_policies WHERE schemaname='public';
  IF v<>126 THEN RAISE EXCEPTION 'SchoolSafe verify failed: public policies %, expected 126',v; END IF;

  SELECT count(*) INTO v FROM pg_policies WHERE schemaname='private';
  IF v<>1 THEN RAISE EXCEPTION 'SchoolSafe verify failed: private policies %, expected 1',v; END IF;

  SELECT count(*) INTO v FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname='public' AND c.relkind IN ('r','p') AND c.relrowsecurity;
  IF v<>66 THEN RAISE EXCEPTION 'SchoolSafe verify failed: public RLS tables %, expected 66',v; END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname='pgcrypto') THEN
    RAISE EXCEPTION 'SchoolSafe verify failed: pgcrypto is not installed';
  END IF;

  IF to_regclass('auth.users') IS NULL THEN RAISE EXCEPTION 'SchoolSafe verify failed: auth.users missing'; END IF;
  IF to_regclass('storage.objects') IS NULL THEN RAISE EXCEPTION 'SchoolSafe verify failed: storage.objects missing'; END IF;
  IF NOT EXISTS (SELECT 1 FROM private.qr_keys WHERE id='student_daily_v1' AND octet_length(secret)>=32) THEN
    RAISE EXCEPTION 'SchoolSafe verify failed: runtime QR key missing';
  END IF;
END $$;

SELECT jsonb_build_object(
  'ok',true,
  'service','schoolsafe-vps-baseline',
  'public_tables',66,
  'private_tables',8,
  'public_functions',72,
  'private_functions',58,
  'checks',103,
  'foreign_keys',61,
  'primary_keys',74,
  'unique_constraints',11,
  'nonconstraint_indexes',102,
  'app_triggers',28,
  'auth_schoolsafe_triggers',2,
  'public_policies',126,
  'private_policies',1,
  'public_rls_enabled',66,
  'verified_at',now()
) AS schoolsafe_baseline_verification;
