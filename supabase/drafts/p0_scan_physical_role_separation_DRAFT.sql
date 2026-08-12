-- ============================================================================
-- SchoolSafe P0-Scan — SEPARATION SCAN PHYSIQUE / SCAN FINANCIER
-- DRAFT — NE PAS APPLIQUER EN PRODUCTION
-- ROLLBACK final volontaire.
--
-- La Caisse garde le contrat QR/finance existant tant que Claude n'a pas fini
-- l'inventaire, mais ne peut plus enregistrer une entrée, un incident physique
-- ni charger la liste APS via les RPC protégées ci-dessous.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION private.can_physical_scan()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT COALESCE(
    private.current_app_role() IN ('direction','direction2','enseignant','gardien'),
    false
  )
$$;

REVOKE ALL ON FUNCTION private.can_physical_scan()
FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.can_physical_scan()
TO service_role;

-- --------------------------------------------------------------------------
-- 1. Entrée physique : wrapper temporaire pour la revue.
-- La migration finale devra squasher le garde directement dans la fonction.
-- --------------------------------------------------------------------------
ALTER FUNCTION public.record_entry_scan(text,text,text,boolean)
  RENAME TO record_entry_scan_impl_draft;

REVOKE ALL ON FUNCTION public.record_entry_scan_impl_draft(text,text,text,boolean)
FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.record_entry_scan_impl_draft(text,text,text,boolean)
TO service_role;

CREATE OR REPLACE FUNCTION public.record_entry_scan(
  p_sid text,
  p_status text,
  p_arr_time text,
  p_manual boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
  IF NOT private.can_physical_scan() THEN
    RAISE EXCEPTION 'Accès refusé — scanner physique'
      USING ERRCODE='42501';
  END IF;

  RETURN public.record_entry_scan_impl_draft(
    p_sid,p_status,p_arr_time,p_manual
  );
END;
$$;

REVOKE ALL ON FUNCTION public.record_entry_scan(text,text,text,boolean)
FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.record_entry_scan(text,text,text,boolean)
TO authenticated,service_role;

-- --------------------------------------------------------------------------
-- 2. Incident physique : même séparation.
-- --------------------------------------------------------------------------
ALTER FUNCTION public.record_scan_incident(text,text,text,text,boolean)
  RENAME TO record_scan_incident_impl_draft;

REVOKE ALL ON FUNCTION public.record_scan_incident_impl_draft(text,text,text,text,boolean)
FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.record_scan_incident_impl_draft(text,text,text,text,boolean)
TO service_role;

CREATE OR REPLACE FUNCTION public.record_scan_incident(
  p_sid text,
  p_type text,
  p_code text,
  p_note text,
  p_manual boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
  IF NOT private.can_physical_scan() THEN
    RAISE EXCEPTION 'Accès refusé — incident scanner physique'
      USING ERRCODE='42501';
  END IF;

  RETURN public.record_scan_incident_impl_draft(
    p_sid,p_type,p_code,p_note,p_manual
  );
END;
$$;

REVOKE ALL ON FUNCTION public.record_scan_incident(text,text,text,text,boolean)
FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.record_scan_incident(text,text,text,text,boolean)
TO authenticated,service_role;

-- --------------------------------------------------------------------------
-- 3. Personnes autorisées : aucune raison financière de charger la liste APS.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_scanner_aps()
RETURNS TABLE(
  id text,
  sid text,
  name text,
  relation text,
  photo text,
  phone text,
  valid_until date,
  approval_status text,
  active boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_role text := private.current_app_role();
BEGIN
  IF NOT private.can_physical_scan() THEN
    RAISE EXCEPTION 'Accès refusé — personnes autorisées'
      USING ERRCODE='42501';
  END IF;

  RETURN QUERY
  SELECT
    a.id,
    a.sid,
    a.name,
    a.relation,
    a.photo,
    CASE WHEN v_role IN ('direction','gardien') THEN a.phone ELSE NULL END,
    a.valid_until,
    a.approval_status,
    a.active
  FROM public.aps a
  WHERE a.approval_status='approved'
    AND a.active
    AND (
      a.valid_until IS NULL
      OR a.valid_until>=pg_catalog.timezone('Africa/Kinshasa',pg_catalog.now())::date
    );
END;
$$;

-- Les grants existants de get_scanner_aps() sont conservés par CREATE OR REPLACE.
-- verify_student_qr/get_scanner_students/issue_student_qr restent volontairement
-- inchangés jusqu'au retour frontend Claude #94.

ROLLBACK;
