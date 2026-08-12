-- ============================================================================
-- SchoolSafe — INSCRIPTION ELEVE : VERROUILLAGE DES ECRITURES DIRECTES
-- DRAFT PHASE 2 — NE PAS APPLIQUER AVANT RETOUR CLAUDE DANS #89
-- ROLLBACK final volontaire.
-- ============================================================================
--
-- Préconditions OBLIGATOIRES avant une future migration réelle :
--
-- 1. Claude a publié l'inventaire complet :
--      node tools/audit-schema.mjs --table students --verbose
-- 2. Chaque INSERT/UPDATE/DELETE navigateur sur students possède une RPC.
-- 3. save_student_profile est la version SECURITY DEFINER validée.
-- 4. set_student_primary_parent est servi et raccordé.
-- 5. la photo passe par set_student_photo_file.
-- 6. les autres transitions sensibles (archivage, accès parent,
--    autorisation sortie seule, blocages) sont raccordées à leurs RPC.
--
-- Tant qu'une seule précondition manque : NE PAS convertir ce fichier en
-- migration et NE PAS l'exécuter sur la production.
-- ============================================================================

BEGIN;

-- Les lectures restent accordées et continuent d'être filtrées par
-- students_read / private.can_view_student(id).
REVOKE INSERT, UPDATE, DELETE ON public.students FROM authenticated;

-- La policy ALL historique devient inutile et dangereuse une fois les RPC
-- en place : elle permettrait de contourner les validations métier si les
-- privilèges revenaient par erreur.
DROP POLICY IF EXISTS students_direction_write ON public.students;

-- Service role reste l'acteur technique des fonctions Edge/maintenance.
GRANT SELECT, INSERT, UPDATE, DELETE ON public.students TO service_role;

-- Les RPC nécessaires doivent rester appelables par les sessions connectées.
GRANT EXECUTE ON FUNCTION public.save_student_profile(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_student_primary_parent(text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_student_photo_file(text,uuid) TO authenticated;

-- Porte de vérification : ce draft doit produire false/false/false pour les
-- écritures directes authenticated et true pour SELECT.
DO $$
BEGIN
  IF has_table_privilege('authenticated','public.students','INSERT')
     OR has_table_privilege('authenticated','public.students','UPDATE')
     OR has_table_privilege('authenticated','public.students','DELETE') THEN
    RAISE EXCEPTION 'students direct write privileges are still present';
  END IF;

  IF NOT has_table_privilege('authenticated','public.students','SELECT') THEN
    RAISE EXCEPTION 'students SELECT privilege must remain available';
  END IF;
END $$;

ROLLBACK;
