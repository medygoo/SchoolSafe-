-- SchoolSafe #89 — vérification lecture seule des états sensibles élève.

SELECT
  p.proname,
  pg_get_function_identity_arguments(p.oid) AS args,
  p.prosecdef AS security_definer,
  has_function_privilege('authenticated',p.oid,'EXECUTE') AS authenticated_execute
FROM pg_proc p
JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public'
  AND p.proname IN (
    'set_student_parent_access',
    'set_student_self_exit_authorization',
    'set_student_primary_parent',
    'set_student_photo_file'
  )
ORDER BY p.proname;

-- Les fonctions de lecture métier existantes doivent toujours dépendre des
-- champs que ces RPC protègent.
SELECT
  EXISTS(
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='private' AND p.proname='owns_student'
      AND position('access_parent' in pg_get_functiondef(p.oid))>0
  ) AS parent_access_consumed_by_ownership,
  EXISTS(
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname='scan_student_exit_at_gate'
      AND position('may_leave_alone' in pg_get_functiondef(p.oid))>0
      AND position('leave_alone_until' in pg_get_functiondef(p.oid))>0
  ) AS self_exit_consumed_at_gate;
