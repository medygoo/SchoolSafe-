-- ==========================================================================
-- SchoolSafe P0-9 — RATTRAPAGES MENSUELS, COEUR PEDAGOGIQUE
-- DRAFT — NE PAS APPLIQUER EN PRODUCTION
-- Branche : chatgpt/p0-9-rattrapages-clean
-- ROLLBACK final volontaire.
-- ==========================================================================

BEGIN;

-- --------------------------------------------------------------------------
-- 1. Réglages persistants
-- --------------------------------------------------------------------------
ALTER TABLE public.settings
  ADD COLUMN IF NOT EXISTS rattrapage_min_notes integer,
  ADD COLUMN IF NOT EXISTS rattrapage_share_teacher numeric(5,2);

UPDATE public.settings
SET rattrapage_threshold = COALESCE(rattrapage_threshold, 50),
    rattrapage_min_notes = COALESCE(rattrapage_min_notes, 2),
    rattrapage_share_teacher = COALESCE(rattrapage_share_teacher, 60)
WHERE id='main';

ALTER TABLE public.settings
  ALTER COLUMN rattrapage_threshold SET DEFAULT 50,
  ALTER COLUMN rattrapage_min_notes SET DEFAULT 2,
  ALTER COLUMN rattrapage_share_teacher SET DEFAULT 60;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.settings'::regclass
      AND conname='settings_rattrapage_threshold_check'
  ) THEN
    ALTER TABLE public.settings
      ADD CONSTRAINT settings_rattrapage_threshold_check
      CHECK (rattrapage_threshold IS NULL OR rattrapage_threshold BETWEEN 0 AND 100);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.settings'::regclass
      AND conname='settings_rattrapage_min_notes_check'
  ) THEN
    ALTER TABLE public.settings
      ADD CONSTRAINT settings_rattrapage_min_notes_check
      CHECK (rattrapage_min_notes IS NULL OR rattrapage_min_notes BETWEEN 2 AND 50);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.settings'::regclass
      AND conname='settings_rattrapage_share_teacher_check'
  ) THEN
    ALTER TABLE public.settings
      ADD CONSTRAINT settings_rattrapage_share_teacher_check
      CHECK (rattrapage_share_teacher IS NULL OR rattrapage_share_teacher BETWEEN 0 AND 100);
  END IF;
END $$;

-- --------------------------------------------------------------------------
-- 2. Colonnes mensuelles / snapshots
-- --------------------------------------------------------------------------
ALTER TABLE public.rattrapages
  ADD COLUMN IF NOT EXISTS class_id text,
  ADD COLUMN IF NOT EXISTS class_name_snapshot text,
  ADD COLUMN IF NOT EXISTS school_year text,
  ADD COLUMN IF NOT EXISTS period_month date,
  ADD COLUMN IF NOT EXISTS grade_count integer,
  ADD COLUMN IF NOT EXISTS detected_at timestamptz;

ALTER TABLE public.convocations
  ADD COLUMN IF NOT EXISTS period_month date,
  ADD COLUMN IF NOT EXISTS school_year text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.rattrapages'::regclass
      AND conname='rattrapages_class_id_fkey'
  ) THEN
    ALTER TABLE public.rattrapages
      ADD CONSTRAINT rattrapages_class_id_fkey
      FOREIGN KEY (class_id) REFERENCES public.classes(id) ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.rattrapages'::regclass
      AND conname='rattrapages_period_month_first_day_check'
  ) THEN
    ALTER TABLE public.rattrapages
      ADD CONSTRAINT rattrapages_period_month_first_day_check
      CHECK (period_month IS NULL OR period_month = pg_catalog.date_trunc('month',period_month)::date);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.rattrapages'::regclass
      AND conname='rattrapages_grade_count_check'
  ) THEN
    ALTER TABLE public.rattrapages
      ADD CONSTRAINT rattrapages_grade_count_check
      CHECK (grade_count IS NULL OR grade_count >= 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.convocations'::regclass
      AND conname='convocations_period_month_first_day_check'
  ) THEN
    ALTER TABLE public.convocations
      ADD CONSTRAINT convocations_period_month_first_day_check
      CHECK (period_month IS NULL OR period_month = pg_catalog.date_trunc('month',period_month)::date);
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_rattrapages_auto_sid_subject_month
ON public.rattrapages (sid, lower(btrim(matiere)), period_month)
WHERE auto_triggered IS TRUE
  AND sid IS NOT NULL
  AND matiere IS NOT NULL
  AND period_month IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_convocations_auto_rattrapage_sid_month
ON public.convocations (sid, period_month)
WHERE auto_generated IS TRUE
  AND convoc_type='rattrapage'
  AND sid IS NOT NULL
  AND period_month IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_grades_monthly_rattrapage
ON public.grades (sid,cid,matiere,date);

CREATE INDEX IF NOT EXISTS idx_rattrapages_period_student
ON public.rattrapages (period_month,sid);

-- --------------------------------------------------------------------------
-- 3. Réglages : lecture filtrée + écriture Direction 1
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_rattrapage_settings()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_role text := private.current_app_role();
  s public.settings%rowtype;
BEGIN
  IF v_role NOT IN ('direction','direction2','enseignant') THEN
    RETURN jsonb_build_object('ok',false,'code','FORBIDDEN');
  END IF;

  SELECT * INTO s FROM public.settings WHERE id='main';
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'code','SETTINGS_NOT_FOUND');
  END IF;

  RETURN jsonb_strip_nulls(jsonb_build_object(
    'ok',true,
    'code','RATTRAPAGE_SETTINGS_READY',
    'threshold',COALESCE(s.rattrapage_threshold,50),
    'min_notes',COALESCE(s.rattrapage_min_notes,2),
    'teacher_share_pct',CASE WHEN v_role='direction'
      THEN COALESCE(s.rattrapage_share_teacher,60) ELSE NULL END
  ));
END;
$$;

CREATE OR REPLACE FUNCTION public.set_rattrapage_settings(
  p_threshold numeric,
  p_min_notes integer,
  p_teacher_share numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_row public.settings%rowtype;
BEGIN
  IF private.current_app_role() IS DISTINCT FROM 'direction' THEN
    RETURN jsonb_build_object('ok',false,'code','DIRECTION1_REQUIRED');
  END IF;

  IF p_threshold IS NULL OR p_threshold < 0 OR p_threshold > 100 THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','rattrapage_threshold');
  END IF;
  IF p_min_notes IS NULL OR p_min_notes < 2 OR p_min_notes > 50 THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','rattrapage_min_notes');
  END IF;
  IF p_teacher_share IS NULL OR p_teacher_share < 0 OR p_teacher_share > 100 THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','rattrapage_share_teacher');
  END IF;

  UPDATE public.settings
  SET rattrapage_threshold=p_threshold,
      rattrapage_min_notes=p_min_notes,
      rattrapage_share_teacher=p_teacher_share
  WHERE id='main'
  RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'code','SETTINGS_NOT_FOUND');
  END IF;

  RETURN jsonb_build_object(
    'ok',true,
    'code','RATTRAPAGE_SETTINGS_UPDATED',
    'threshold',v_row.rattrapage_threshold,
    'min_notes',v_row.rattrapage_min_notes,
    'teacher_share_pct',v_row.rattrapage_share_teacher
  );
END;
$$;

REVOKE ALL ON FUNCTION public.get_rattrapage_settings() FROM PUBLIC,anon;
REVOKE ALL ON FUNCTION public.set_rattrapage_settings(numeric,integer,numeric) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_rattrapage_settings() TO authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.set_rattrapage_settings(numeric,integer,numeric) TO authenticated,service_role;

-- --------------------------------------------------------------------------
-- 4. Détection mensuelle interne
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.detect_monthly_rattrapages(
  p_period_month date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_today date := pg_catalog.timezone('Africa/Kinshasa',pg_catalog.now())::date;
  v_current_month date := pg_catalog.date_trunc('month',v_today)::date;
  v_period date;
  v_month_key text;
  v_threshold numeric;
  v_min_notes integer;
  v_school_year text;
  v_current_trim text;
  v_created integer := 0;
  v_convocations integer := 0;
  v_parent_notifs integer := 0;
  v_direction_notifs integer := 0;
  c record;
  srow record;
  u record;
  v_rat_id text;
  v_convoc_id text;
  v_parent_id text;
  v_student_name text;
  v_weak_mats text;
BEGIN
  v_period := pg_catalog.date_trunc(
    'month',
    COALESCE(p_period_month,(v_current_month - interval '1 month')::date)
  )::date;

  IF v_period >= v_current_month THEN
    RETURN jsonb_build_object(
      'ok',false,'code','PERIOD_NOT_COMPLETE','period_month',v_period
    );
  END IF;

  v_month_key := pg_catalog.to_char(v_period,'YYYY-MM');

  SELECT COALESCE(rattrapage_threshold,50),
         COALESCE(rattrapage_min_notes,2),
         year,
         currenttrimestre
  INTO v_threshold,v_min_notes,v_school_year,v_current_trim
  FROM public.settings
  WHERE id='main';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'code','SETTINGS_NOT_FOUND');
  END IF;

  -- Sérialise deux exécutions concurrentes du même mois.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtext('schoolsafe:rattrapage:'||v_month_key)
  );

  FOR c IN
    WITH raw AS (
      SELECT
        g.sid,
        COALESCE(s.cid,g.cid) AS class_id,
        lower(btrim(g.matiere)) AS subject_key,
        btrim(g.matiere) AS subject_label,
        NULLIF(btrim(COALESCE(g."by",'')),'') AS grade_teacher_id,
        NULLIF(btrim(COALESCE(g.trimestre,g.trimester,'')),'') AS grade_trim,
        NULLIF(btrim(COALESCE(g.year,'')),'') AS grade_year,
        CASE
          WHEN g.pct IS NOT NULL THEN g.pct
          WHEN g.note IS NOT NULL AND g.max IS NOT NULL AND g.max > 0
            THEN (g.note/g.max)*100
          ELSE NULL
        END AS pct,
        CASE WHEN COALESCE(g.weight,1)>0 THEN COALESCE(g.weight,1) ELSE 1 END AS weight
      FROM public.grades g
      JOIN public.students s ON s.id=g.sid
      WHERE g.sid IS NOT NULL
        AND NULLIF(btrim(COALESCE(g.matiere,'')),'') IS NOT NULL
        AND NOT COALESCE(s.archived,false)
        AND left(COALESCE(g.date,''),7)=v_month_key
    ), grouped AS (
      SELECT
        sid,class_id,subject_key,
        min(subject_label) AS subject_label,
        count(*) FILTER (WHERE pct IS NOT NULL) AS grade_count,
        round(
          sum(pct*weight) FILTER (WHERE pct IS NOT NULL)
          / NULLIF(sum(weight) FILTER (WHERE pct IS NOT NULL),0),
          2
        ) AS avg_pct,
        mode() WITHIN GROUP (ORDER BY grade_teacher_id)
          FILTER (WHERE grade_teacher_id IS NOT NULL) AS grade_teacher_id,
        mode() WITHIN GROUP (ORDER BY grade_trim)
          FILTER (WHERE grade_trim IS NOT NULL) AS grade_trim,
        mode() WITHIN GROUP (ORDER BY grade_year)
          FILTER (WHERE grade_year IS NOT NULL) AS grade_year
      FROM raw
      GROUP BY sid,class_id,subject_key
    )
    SELECT
      g.sid,
      g.class_id,
      g.subject_key,
      g.subject_label,
      g.grade_count,
      g.avg_pct,
      COALESCE(
        g.grade_teacher_id,
        (
          SELECT t.teacher_id
          FROM public.timetables t
          WHERE t.cid=g.class_id
            AND lower(btrim(COALESCE(t.matiere,'')))=g.subject_key
            AND t.teacher_id IS NOT NULL
          ORDER BY t.period NULLS LAST
          LIMIT 1
        ),
        cl.titulaire_id,
        cl.teacher_id,
        cl.teacher_id_en
      ) AS teacher_id,
      cl.name AS class_name,
      COALESCE(g.grade_trim,v_current_trim) AS trimestre,
      COALESCE(g.grade_year,v_school_year) AS school_year
    FROM grouped g
    LEFT JOIN public.classes cl ON cl.id=g.class_id
    WHERE g.grade_count>=v_min_notes
      AND g.avg_pct IS NOT NULL
      AND g.avg_pct<v_threshold
      AND NOT EXISTS (
        SELECT 1
        FROM public.rattrapages r
        WHERE r.sid=g.sid
          AND lower(btrim(COALESCE(r.matiere,'')))=g.subject_key
          AND r.period_month=v_period
          AND r.auto_triggered IS TRUE
      )
  LOOP
    v_rat_id := 'rat_'||replace(pg_catalog.gen_random_uuid()::text,'-','');

    INSERT INTO public.rattrapages(
      id,sid,teacher_id,matiere,motif,date,"time",status,
      amount,paid,score,auto_triggered,trimestre,archived,
      class_id,class_name_snapshot,school_year,period_month,grade_count,detected_at
    ) VALUES (
      v_rat_id,c.sid,c.teacher_id,c.subject_label,
      format('Moyenne de %s : %s%% sur %s note(s) — seuil %s%%',
        v_month_key,c.avg_pct,c.grade_count,v_threshold),
      pg_catalog.to_char(v_today,'YYYY-MM-DD'),
      pg_catalog.to_char(pg_catalog.timezone('Africa/Kinshasa',pg_catalog.now()),'HH24:MI'),
      'pending',0,false,c.avg_pct,true,c.trimestre,false,
      c.class_id,c.class_name,c.school_year,v_period,c.grade_count,pg_catalog.now()
    )
    ON CONFLICT DO NOTHING;

    IF FOUND THEN v_created := v_created+1; END IF;
  END LOOP;

  -- Une seule convocation familiale par enfant/mois, regroupant les matières.
  FOR srow IN
    SELECT
      r.sid,
      min(r.score) AS min_score,
      string_agg(
        format('%s (%s%%)',r.matiere,trim(pg_catalog.to_char(r.score,'FM999990D00'))),
        ', ' ORDER BY lower(r.matiere)
      ) AS weak_mats,
      mode() WITHIN GROUP (ORDER BY r.trimestre)
        FILTER (WHERE r.trimestre IS NOT NULL) AS trimestre,
      mode() WITHIN GROUP (ORDER BY r.school_year)
        FILTER (WHERE r.school_year IS NOT NULL) AS school_year
    FROM public.rattrapages r
    WHERE r.auto_triggered IS TRUE
      AND r.period_month=v_period
      AND NOT COALESCE(r.archived,false)
    GROUP BY r.sid
  LOOP
    SELECT s.name,
           CASE WHEN p.id IS NOT NULL THEN p.id ELSE NULL END
    INTO v_student_name,v_parent_id
    FROM public.students s
    LEFT JOIN public.users p
      ON p.id=s.pid AND p.role='parent' AND p.status='active'
    WHERE s.id=srow.sid
      AND NOT COALESCE(s.archived,false);

    IF NOT FOUND THEN CONTINUE; END IF;

    v_weak_mats := srow.weak_mats;
    v_convoc_id := 'cv_'||replace(pg_catalog.gen_random_uuid()::text,'-','');

    INSERT INTO public.convocations(
      id,sid,date,reason,body,status,score,trimestre,
      auto_generated,weak_mats,"by",convoc_type,period_month,school_year
    ) VALUES (
      v_convoc_id,srow.sid,pg_catalog.to_char(v_today,'YYYY-MM-DD'),
      'Cours de rattrapage',
      format(
        'Les résultats de %s pour le mois de %s sont inférieurs au seuil de %s%% dans : %s. La Direction vous invite à l''école afin d''organiser le cours de rattrapage.',
        v_student_name,v_month_key,v_threshold,v_weak_mats
      ),
      'pending',srow.min_score,srow.trimestre,true,v_weak_mats,NULL,
      'rattrapage',v_period,srow.school_year
    )
    ON CONFLICT DO NOTHING;

    IF FOUND THEN
      v_convocations := v_convocations+1;
    ELSE
      SELECT id INTO v_convoc_id
      FROM public.convocations
      WHERE sid=srow.sid
        AND period_month=v_period
        AND auto_generated IS TRUE
        AND convoc_type='rattrapage'
      LIMIT 1;
    END IF;

    IF v_parent_id IS NOT NULL THEN
      INSERT INTO public.notifs(
        id,uid,"from",msg,type,date,"time",read,status,to_role,
        category,title,student_id,action_url,priority,privacy_level,
        requires_ack,created_by_name,created_by_role,source_type,source_id,
        dedupe_key,data,push_requested
      ) VALUES (
        'notif_'||replace(pg_catalog.gen_random_uuid()::text,'-',''),
        v_parent_id,'SchoolSafe',
        format('%s : résultats du mois %s insuffisants en %s. Une convocation de rattrapage est disponible.',
          v_student_name,v_month_key,v_weak_mats),
        'warning',pg_catalog.to_char(v_today,'YYYY-MM-DD'),
        pg_catalog.to_char(pg_catalog.timezone('Africa/Kinshasa',pg_catalog.now()),'HH24:MI'),
        false,'convocation','parent','convocation','SchoolSafe — Convocation',
        srow.sid,'/?page=notifications','high','sensitive',true,
        'SchoolSafe','system','rattrapage_monthly',v_convoc_id,
        format('rattrapage:%s:%s:parent',srow.sid,v_month_key),
        jsonb_build_object('period_month',v_month_key,'convocation_id',v_convoc_id,'weak_subjects',v_weak_mats),
        true
      )
      ON CONFLICT (uid,dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

      IF FOUND THEN v_parent_notifs:=v_parent_notifs+1; END IF;
    END IF;
  END LOOP;

  -- Résumé pédagogique Direction 1 + Direction 2, sans aucun montant.
  IF EXISTS(
    SELECT 1 FROM public.rattrapages
    WHERE auto_triggered IS TRUE AND period_month=v_period
  ) THEN
    FOR u IN
      SELECT id,role
      FROM public.users
      WHERE status='active'
        AND role IN ('direction','direction2','direction_pedagogique')
    LOOP
      INSERT INTO public.notifs(
        id,uid,"from",msg,type,date,"time",read,status,to_role,
        category,title,action_url,priority,privacy_level,requires_ack,
        created_by_name,created_by_role,source_type,dedupe_key,data,push_requested
      ) VALUES (
        'notif_'||replace(pg_catalog.gen_random_uuid()::text,'-',''),
        u.id,'SchoolSafe',
        format('Rattrapages du mois %s : %s dossier(s), %s famille(s) convoquée(s).',
          v_month_key,
          (SELECT count(*) FROM public.rattrapages r WHERE r.auto_triggered IS TRUE AND r.period_month=v_period),
          (SELECT count(*) FROM public.convocations c WHERE c.auto_generated IS TRUE AND c.convoc_type='rattrapage' AND c.period_month=v_period)
        ),
        'info',pg_catalog.to_char(v_today,'YYYY-MM-DD'),
        pg_catalog.to_char(pg_catalog.timezone('Africa/Kinshasa',pg_catalog.now()),'HH24:MI'),
        false,'information',CASE WHEN u.role='direction_pedagogique' THEN 'direction2' ELSE u.role END,
        'information','SchoolSafe — Rattrapages mensuels','/?page=rattrapages',
        'normal','normal',false,'SchoolSafe','system','rattrapage_monthly_summary',
        format('rattrapage:%s:%s:summary',v_month_key,u.id),
        jsonb_build_object('period_month',v_month_key),true
      )
      ON CONFLICT (uid,dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING;

      IF FOUND THEN v_direction_notifs:=v_direction_notifs+1; END IF;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'ok',true,
    'code','MONTHLY_RATTRAPAGE_DETECTION_COMPLETE',
    'period_month',v_month_key,
    'threshold',v_threshold,
    'min_notes',v_min_notes,
    'created_rattrapages',v_created,
    'created_convocations',v_convocations,
    'created_parent_notifications',v_parent_notifs,
    'created_direction_notifications',v_direction_notifs
  );
END;
$$;

REVOKE ALL ON FUNCTION private.detect_monthly_rattrapages(date) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.detect_monthly_rattrapages(date) TO service_role;

CREATE OR REPLACE FUNCTION public.run_monthly_rattrapage_detection(
  p_period_month date DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
  IF private.current_app_role() IS DISTINCT FROM 'direction' THEN
    RETURN jsonb_build_object('ok',false,'code','DIRECTION1_REQUIRED');
  END IF;
  RETURN private.detect_monthly_rattrapages(p_period_month);
END;
$$;

REVOKE ALL ON FUNCTION public.run_monthly_rattrapage_detection(date) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.run_monthly_rattrapage_detection(date) TO authenticated,service_role;

ROLLBACK;
