-- ==========================================================================
-- SchoolSafe P0-9 — INTEGRITE COMPLEMENTAIRE
-- DRAFT — NE PAS APPLIQUER EN PRODUCTION
-- À exécuter après les autres drafts P0-9 sur une base de test.
-- ROLLBACK final volontaire.
-- ==========================================================================

BEGIN;

-- Le registre réel de référence est vide au moment de la préparation de ce
-- draft. Les relations sont néanmoins additives et tolèrent les NULL legacy.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.rattrapages'::regclass
      AND conname='rattrapages_sid_fkey'
  ) THEN
    ALTER TABLE public.rattrapages
      ADD CONSTRAINT rattrapages_sid_fkey
      FOREIGN KEY (sid) REFERENCES public.students(id) ON DELETE RESTRICT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.rattrapages'::regclass
      AND conname='rattrapages_teacher_id_fkey'
  ) THEN
    ALTER TABLE public.rattrapages
      ADD CONSTRAINT rattrapages_teacher_id_fkey
      FOREIGN KEY (teacher_id) REFERENCES public.users(id) ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.rattrapages'::regclass
      AND conname='rattrapages_session_time_check'
  ) THEN
    ALTER TABLE public.rattrapages
      ADD CONSTRAINT rattrapages_session_time_check
      CHECK (
        session_time IS NULL
        OR btrim(session_time)=''
        OR btrim(session_time) ~ '^([01][0-9]|2[0-3]):[0-5][0-9]$'
      );
  END IF;
END $$;

ROLLBACK;
