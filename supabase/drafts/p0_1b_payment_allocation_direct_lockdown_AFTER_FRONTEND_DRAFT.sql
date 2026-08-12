-- ============================================================================
-- SchoolSafe P0-1b — VERROUILLAGE ECRITURES DIRECTES payment_allocations
-- DRAFT — APRES INVENTAIRE/RACCORDEMENT FRONTEND CLAUDE UNIQUEMENT
-- ROLLBACK final volontaire.
-- ============================================================================

BEGIN;

-- Les lectures autorisées restent inchangées. Seules les mutations directes
-- sont retirées : le ledger passe par les RPC SECURITY DEFINER.
REVOKE INSERT,UPDATE,DELETE
ON TABLE public.payment_allocations
FROM PUBLIC,anon,authenticated;

DROP POLICY IF EXISTS pal_insert ON public.payment_allocations;
DROP POLICY IF EXISTS pal_update ON public.payment_allocations;
DROP POLICY IF EXISTS pal_delete ON public.payment_allocations;

-- Ne pas toucher à pal_read : D1/Caisse/Parent continuent à lire uniquement
-- ce que leur politique autorise, notamment via les résumés serveur.

ROLLBACK;
