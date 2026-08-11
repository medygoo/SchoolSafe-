-- ============================================================================
-- SchoolSafe P0-Scan — VERIFICATION LECTURE SEULE
-- À lancer APRES application du draft sur une base de test.
-- Ne modifie aucune donnée.
-- ============================================================================

-- 1. Le helper physique doit exister et ne pas contenir direction3.
SELECT
  p.prosecdef AS security_definer,
  position('direction3' in lower(pg_get_functiondef(p.oid)))=0 AS cashier_excluded,
  position('direction' in lower(pg_get_functiondef(p.oid)))>0 AS direction_present,
  position('direction2' in lower(pg_get_functiondef(p.oid)))>0 AS direction2_present,
  position('enseignant' in lower(pg_get_functiondef(p.oid)))>0 AS teacher_present,
  position('gardien' in lower(pg_get_functiondef(p.oid)))>0 AS guard_present
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='private'
  AND p.proname='can_physical_scan';

-- 2. Les deux écritures physiques doivent utiliser le nouveau garde.
SELECT
  p.proname,
  pg_get_function_identity_arguments(p.oid) AS args,
  position('can_physical_scan' in pg_get_functiondef(p.oid))>0 AS physical_guard_present,
  p.prosecdef AS security_definer
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.proname IN ('record_entry_scan','record_scan_incident')
ORDER BY p.proname;

-- 3. La liste APS du scanner doit elle aussi utiliser le garde physique.
SELECT
  position('can_physical_scan' in pg_get_functiondef(p.oid))>0 AS aps_physical_guard_present,
  position("('direction','gardien')" in replace(pg_get_functiondef(p.oid),' ',''))>0 AS phone_restricted_to_direction_guard
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.proname='get_scanner_aps';

-- 4. Les fonctions QR/lookup restent volontairement sur le contrat historique
-- tant que Claude #94 n'a pas confirmé le parcours Caisse.
SELECT p.proname,pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.proname IN ('verify_student_qr','issue_student_qr','get_scanner_students','get_gate_access_status')
ORDER BY p.proname;
