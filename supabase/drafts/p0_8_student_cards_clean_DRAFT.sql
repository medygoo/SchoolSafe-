-- ============================================================================
-- SchoolSafe P0-8 — REGISTRE DES CARTES ÉLÈVES, VERSION PROPRE
-- DRAFT — NE PAS APPLIQUER EN PRODUCTION
-- Branche : chatgpt/p0-8-cartes-clean
-- Base : main courant, sans ancien durcissement Sortie.
-- ============================================================================

BEGIN;

-- --------------------------------------------------------------------------
-- 0. Configuration école : préfixe de numéro de carte paramétrable.
--    Pas de LS codé en dur dans les fonctions afin de réutiliser le modèle
--    pour une autre école plus tard.
-- --------------------------------------------------------------------------
ALTER TABLE public.settings
  ADD COLUMN IF NOT EXISTS student_card_prefix text;

UPDATE public.settings
SET student_card_prefix = COALESCE(NULLIF(upper(btrim(student_card_prefix)), ''), 'LS')
WHERE id = 'main';

ALTER TABLE public.settings
  ALTER COLUMN student_card_prefix SET DEFAULT 'LS';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.settings'::regclass
      AND conname='settings_student_card_prefix_check'
  ) THEN
    ALTER TABLE public.settings
      ADD CONSTRAINT settings_student_card_prefix_check
      CHECK (student_card_prefix IS NULL OR student_card_prefix ~ '^[A-Z0-9]{1,12}$');
  END IF;
END $$;

-- --------------------------------------------------------------------------
-- 1. Registre : une ligne = une carte physique émise.
--    Les colonnes identité/classe/QR sont figées à l'émission.
-- --------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.student_cards (
  id text PRIMARY KEY DEFAULT ('card_' || replace(gen_random_uuid()::text,'-','')),
  sid text NOT NULL REFERENCES public.students(id) ON DELETE RESTRICT,
  year text NOT NULL,
  card_no text NOT NULL UNIQUE,
  class_id text NOT NULL REFERENCES public.classes(id) ON DELETE RESTRICT,
  class_name text NOT NULL,
  student_name text NOT NULL,
  student_mat text NOT NULL,
  status text NOT NULL DEFAULT 'active',
  emission text NOT NULL,
  motif text,
  note text,
  photo text NOT NULL,
  qr_payload text NOT NULL UNIQUE,
  issued_by text NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  issued_by_name text NOT NULL,
  issued_at timestamptz NOT NULL DEFAULT now(),
  print_count integer NOT NULL DEFAULT 1,
  replaces text REFERENCES public.student_cards(id) ON DELETE RESTRICT,
  replaced_by text REFERENCES public.student_cards(id) ON DELETE RESTRICT,
  invalidated_at timestamptz,
  invalidated_by text REFERENCES public.users(id) ON DELETE RESTRICT,
  invalidated_by_name text,
  invalidated_reason text,
  updated_at timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT student_cards_year_check
    CHECK (year ~ '^[0-9]{4}-[0-9]{4}$'),
  CONSTRAINT student_cards_status_check
    CHECK (status IN ('active','remplacee','perdue','deterioree','revoquee')),
  CONSTRAINT student_cards_emission_check
    CHECK (emission IN ('initiale','renouvellement','duplicata_perte','duplicata_deterioration','correction')),
  CONSTRAINT student_cards_print_count_check
    CHECK (print_count >= 1),
  CONSTRAINT student_cards_required_motif_check
    CHECK (
      emission NOT IN ('duplicata_perte','duplicata_deterioration','correction')
      OR length(btrim(coalesce(motif,''))) >= 3
    ),
  CONSTRAINT student_cards_photo_ref_check
    CHECK (
      length(btrim(photo)) BETWEEN 1 AND 2048
      AND lower(btrim(photo)) NOT LIKE 'data:%'
      AND lower(btrim(photo)) NOT LIKE 'blob:%'
    ),
  CONSTRAINT student_cards_qr_format_check
    CHECK (qr_payload ~ '^schoolsafe://card/[^/]+/[0-9a-f]{8}$')
);

CREATE UNIQUE INDEX IF NOT EXISTS student_cards_one_active_per_student_year_idx
  ON public.student_cards(sid, year)
  WHERE status='active';

CREATE INDEX IF NOT EXISTS student_cards_sid_year_issued_idx
  ON public.student_cards(sid, year, issued_at DESC);

CREATE INDEX IF NOT EXISTS student_cards_status_year_idx
  ON public.student_cards(status, year);

ALTER TABLE public.student_cards ENABLE ROW LEVEL SECURITY;

-- Aucun accès table direct depuis le navigateur. Les lectures passent par RPC
-- afin que Parent/Enseignant ne puissent pas demander les colonnes admin/QR.
REVOKE ALL ON public.student_cards FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.student_cards TO service_role;

-- --------------------------------------------------------------------------
-- 2. Immutabilité du registre.
--    Une carte invalidée ne redevient jamais active et une ligne passée ne
--    peut pas être réécrite comme une nouvelle identité.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.guard_student_card_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
  IF NEW.id IS DISTINCT FROM OLD.id
     OR NEW.sid IS DISTINCT FROM OLD.sid
     OR NEW.year IS DISTINCT FROM OLD.year
     OR NEW.card_no IS DISTINCT FROM OLD.card_no
     OR NEW.class_id IS DISTINCT FROM OLD.class_id
     OR NEW.class_name IS DISTINCT FROM OLD.class_name
     OR NEW.student_name IS DISTINCT FROM OLD.student_name
     OR NEW.student_mat IS DISTINCT FROM OLD.student_mat
     OR NEW.emission IS DISTINCT FROM OLD.emission
     OR NEW.motif IS DISTINCT FROM OLD.motif
     OR NEW.note IS DISTINCT FROM OLD.note
     OR NEW.photo IS DISTINCT FROM OLD.photo
     OR NEW.qr_payload IS DISTINCT FROM OLD.qr_payload
     OR NEW.issued_by IS DISTINCT FROM OLD.issued_by
     OR NEW.issued_by_name IS DISTINCT FROM OLD.issued_by_name
     OR NEW.issued_at IS DISTINCT FROM OLD.issued_at
     OR NEW.replaces IS DISTINCT FROM OLD.replaces
  THEN
    RAISE EXCEPTION 'student_cards immutable identity fields cannot change'
      USING ERRCODE='23514';
  END IF;

  IF OLD.status <> 'active' AND NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'inactive student card status is immutable'
      USING ERRCODE='23514';
  END IF;

  IF OLD.status <> 'active' AND NEW.status='active' THEN
    RAISE EXCEPTION 'student card cannot be reactivated'
      USING ERRCODE='23514';
  END IF;

  IF NEW.print_count < OLD.print_count THEN
    RAISE EXCEPTION 'student card print_count cannot decrease'
      USING ERRCODE='23514';
  END IF;

  IF OLD.replaced_by IS NOT NULL AND NEW.replaced_by IS DISTINCT FROM OLD.replaced_by THEN
    RAISE EXCEPTION 'student card replaced_by cannot be rewritten'
      USING ERRCODE='23514';
  END IF;

  IF OLD.invalidated_at IS NOT NULL AND NEW.invalidated_at IS DISTINCT FROM OLD.invalidated_at THEN
    RAISE EXCEPTION 'student card invalidation cannot be rewritten'
      USING ERRCODE='23514';
  END IF;

  IF OLD.invalidated_by IS NOT NULL AND NEW.invalidated_by IS DISTINCT FROM OLD.invalidated_by THEN
    RAISE EXCEPTION 'student card invalidation actor cannot be rewritten'
      USING ERRCODE='23514';
  END IF;

  IF OLD.invalidated_reason IS NOT NULL AND NEW.invalidated_reason IS DISTINCT FROM OLD.invalidated_reason THEN
    RAISE EXCEPTION 'student card invalidation reason cannot be rewritten'
      USING ERRCODE='23514';
  END IF;

  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_guard_student_card_update ON public.student_cards;
CREATE TRIGGER trg_guard_student_card_update
BEFORE UPDATE ON public.student_cards
FOR EACH ROW EXECUTE FUNCTION private.guard_student_card_update();

CREATE OR REPLACE FUNCTION private.block_student_card_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
  RAISE EXCEPTION 'student_cards history cannot be deleted' USING ERRCODE='42501';
END;
$$;

DROP TRIGGER IF EXISTS trg_block_student_card_delete ON public.student_cards;
CREATE TRIGGER trg_block_student_card_delete
BEFORE DELETE ON public.student_cards
FOR EACH ROW EXECUTE FUNCTION private.block_student_card_delete();

REVOKE ALL ON FUNCTION private.guard_student_card_update() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.block_student_card_delete() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.guard_student_card_update() TO service_role;
GRANT EXECUTE ON FUNCTION private.block_student_card_delete() TO service_role;

-- --------------------------------------------------------------------------
-- 3. Helpers privés.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.can_manage_student_cards()
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT coalesce(private.current_app_role() IN ('direction','direction2'), false)
$$;

CREATE OR REPLACE FUNCTION private.can_verify_student_card()
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT coalesce(private.current_app_role() IN ('direction','direction2','enseignant','gardien'), false)
$$;

CREATE OR REPLACE FUNCTION private.next_student_card_no(p_year text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_n bigint;
  v_prefix text;
  v_key text;
BEGIN
  IF p_year IS NULL OR p_year !~ '^[0-9]{4}-[0-9]{4}$' THEN
    RAISE EXCEPTION 'Invalid school year';
  END IF;

  SELECT upper(btrim(coalesce(student_card_prefix,'LS')))
  INTO v_prefix
  FROM public.settings
  WHERE id='main';

  IF v_prefix IS NULL OR v_prefix !~ '^[A-Z0-9]{1,12}$' THEN
    RAISE EXCEPTION 'Invalid student card prefix';
  END IF;

  v_key := 'student_card:' || p_year;

  INSERT INTO private.school_counters(counter_key,counter_value,updated_at)
  VALUES (v_key,1,now())
  ON CONFLICT(counter_key) DO UPDATE
    SET counter_value=private.school_counters.counter_value+1,
        updated_at=now()
  RETURNING counter_value INTO v_n;

  RETURN v_prefix || '-' || p_year || '-' || lpad(v_n::text,4,'0');
END;
$$;

CREATE OR REPLACE FUNCTION private.student_card_qr_payload(p_card_no text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_secret bytea;
  v_sig text;
BEGIN
  SELECT secret INTO v_secret
  FROM private.qr_keys
  WHERE id='student_card_v1';

  IF v_secret IS NULL THEN RETURN NULL; END IF;

  v_sig := left(
    encode(
      extensions.hmac(convert_to('card:' || p_card_no,'UTF8'),v_secret,'sha256'),
      'hex'
    ),
    8
  );

  RETURN 'schoolsafe://card/' || p_card_no || '/' || v_sig;
END;
$$;

REVOKE ALL ON FUNCTION private.can_manage_student_cards() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.can_verify_student_card() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.next_student_card_no(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION private.student_card_qr_payload(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.can_manage_student_cards() TO service_role;
GRANT EXECUTE ON FUNCTION private.can_verify_student_card() TO service_role;
GRANT EXECUTE ON FUNCTION private.next_student_card_no(text) TO service_role;
GRANT EXECUTE ON FUNCTION private.student_card_qr_payload(text) TO service_role;

-- --------------------------------------------------------------------------
-- 4. Émission transactionnelle.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.issue_student_card(
  p_sid text,
  p_year text,
  p_emission text,
  p_motif text DEFAULT NULL,
  p_note text DEFAULT NULL,
  p_photo text DEFAULT NULL,
  p_class_id text DEFAULT NULL,
  p_replaces text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_actor_id text := private.current_app_user_id();
  v_actor_name text;
  v_year text;
  v_emission text := lower(btrim(coalesce(p_emission,'')));
  v_motif text := nullif(btrim(coalesce(p_motif,'')),'');
  v_note text := nullif(btrim(coalesce(p_note,'')),'');
  v_photo text := nullif(btrim(coalesce(p_photo,'')),'');
  v_student public.students%rowtype;
  v_class public.classes%rowtype;
  v_active public.student_cards%rowtype;
  v_previous public.student_cards%rowtype;
  v_new_id text := 'card_' || replace(gen_random_uuid()::text,'-','');
  v_card_no text;
  v_qr text;
  v_old_status text;
  v_total_prints numeric;
  v_issued_at timestamptz := now();
BEGIN
  IF NOT private.can_manage_student_cards() THEN
    RETURN jsonb_build_object('ok',false,'code','CARD_ROLE_DENIED');
  END IF;

  SELECT name INTO v_actor_name
  FROM public.users
  WHERE id=v_actor_id AND status='active';
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND');
  END IF;

  SELECT year INTO v_year FROM public.settings WHERE id='main';
  IF v_year IS NULL OR p_year IS DISTINCT FROM v_year THEN
    RETURN jsonb_build_object('ok',false,'code','CARD_YEAR_MISMATCH','expected_year',v_year);
  END IF;

  IF v_emission NOT IN ('initiale','renouvellement','duplicata_perte','duplicata_deterioration','correction') THEN
    RETURN jsonb_build_object('ok',false,'code','CARD_EMISSION_INVALID');
  END IF;

  IF v_emission IN ('duplicata_perte','duplicata_deterioration','correction')
     AND (v_motif IS NULL OR length(v_motif)<3) THEN
    RETURN jsonb_build_object('ok',false,'code','CARD_MOTIF_REQUIRED');
  END IF;

  SELECT * INTO v_student
  FROM public.students
  WHERE id=p_sid AND NOT coalesce(archived,false);
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'code','CARD_STUDENT_NOT_FOUND');
  END IF;

  IF p_class_id IS NOT NULL AND p_class_id IS DISTINCT FROM v_student.cid THEN
    RETURN jsonb_build_object('ok',false,'code','CARD_CLASS_MISMATCH');
  END IF;

  SELECT * INTO v_class FROM public.classes WHERE id=v_student.cid;

  IF v_photo IS NULL THEN
    v_photo := nullif(btrim(coalesce(v_student.photo,'')),'');
  END IF;

  IF nullif(btrim(coalesce(v_student.name,'')),'') IS NULL
     OR nullif(btrim(coalesce(v_student.mat,'')),'') IS NULL
     OR nullif(btrim(coalesce(v_student.dob,'')),'') IS NULL
     OR v_student.cid IS NULL
     OR v_class.id IS NULL
     OR nullif(btrim(coalesce(v_class.name,'')),'') IS NULL
     OR v_photo IS NULL
     OR length(v_photo)>2048
     OR lower(v_photo) LIKE 'data:%'
     OR lower(v_photo) LIKE 'blob:%'
  THEN
    RETURN jsonb_build_object('ok',false,'code','CARD_INCOMPLETE_FILE');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('student-card:' || v_student.id || ':' || v_year));

  SELECT * INTO v_active
  FROM public.student_cards
  WHERE sid=v_student.id AND year=v_year AND status='active'
  ORDER BY issued_at DESC LIMIT 1 FOR UPDATE;

  IF v_emission='initiale' THEN
    IF v_active.id IS NOT NULL
       OR EXISTS(SELECT 1 FROM public.student_cards c WHERE c.sid=v_student.id AND c.year=v_year) THEN
      RETURN jsonb_build_object('ok',false,'code','CARD_ALREADY_ACTIVE');
    END IF;
    IF nullif(btrim(coalesce(p_replaces,'')),'') IS NOT NULL THEN
      RETURN jsonb_build_object('ok',false,'code','CARD_PREVIOUS_INVALID');
    END IF;
  ELSE
    IF nullif(btrim(coalesce(p_replaces,'')),'') IS NOT NULL THEN
      SELECT * INTO v_previous
      FROM public.student_cards
      WHERE id=p_replaces AND sid=v_student.id
      FOR UPDATE;
      IF NOT FOUND THEN
        RETURN jsonb_build_object('ok',false,'code','CARD_PREVIOUS_INVALID');
      END IF;
    ELSIF v_active.id IS NOT NULL THEN
      v_previous := v_active;
    ELSE
      SELECT * INTO v_previous
      FROM public.student_cards
      WHERE sid=v_student.id
      ORDER BY issued_at DESC LIMIT 1 FOR UPDATE;
    END IF;

    IF v_previous.id IS NULL THEN
      RETURN jsonb_build_object('ok',false,'code','CARD_PREVIOUS_REQUIRED');
    END IF;

    IF v_previous.status='revoquee' THEN
      RETURN jsonb_build_object('ok',false,'code','CARD_PREVIOUS_INVALID');
    END IF;

    IF v_active.id IS NOT NULL AND v_previous.id<>v_active.id THEN
      RETURN jsonb_build_object('ok',false,'code','CARD_ALREADY_ACTIVE');
    END IF;

    IF v_previous.replaced_by IS NOT NULL THEN
      RETURN jsonb_build_object('ok',false,'code','CARD_ALREADY_REPLACED');
    END IF;
  END IF;

  v_card_no := private.next_student_card_no(v_year);
  v_qr := private.student_card_qr_payload(v_card_no);
  IF v_qr IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','CARD_QR_SECRET_MISSING');
  END IF;

  -- 1) invalider l'ancienne d'abord pour satisfaire l'index unique actif.
  --    Ne PAS poser replaced_by avant l'insertion : la FK est immédiate.
  IF v_previous.id IS NOT NULL AND v_previous.status='active' THEN
    v_old_status := CASE v_emission
      WHEN 'duplicata_perte' THEN 'perdue'
      WHEN 'duplicata_deterioration' THEN 'deterioree'
      ELSE 'remplacee'
    END;

    UPDATE public.student_cards
    SET status=v_old_status,
        invalidated_at=v_issued_at,
        invalidated_by=v_actor_id,
        invalidated_by_name=v_actor_name,
        invalidated_reason=coalesce(v_motif,
          CASE v_emission
            WHEN 'renouvellement' THEN 'Renouvellement annuel'
            WHEN 'correction' THEN 'Correction de carte'
            ELSE 'Remplacement de carte'
          END)
    WHERE id=v_previous.id;
  END IF;

  -- 2) insérer la nouvelle carte active.
  INSERT INTO public.student_cards(
    id,sid,year,card_no,class_id,class_name,student_name,student_mat,
    status,emission,motif,note,photo,qr_payload,
    issued_by,issued_by_name,issued_at,print_count,replaces
  ) VALUES (
    v_new_id,v_student.id,v_year,v_card_no,v_student.cid,v_class.name,v_student.name,v_student.mat,
    'active',v_emission,v_motif,left(v_note,500),v_photo,v_qr,
    v_actor_id,v_actor_name,v_issued_at,1,
    CASE WHEN v_previous.id IS NULL THEN NULL ELSE v_previous.id END
  );

  -- 3) seulement maintenant poser le lien inverse vers la nouvelle carte.
  IF v_previous.id IS NOT NULL THEN
    UPDATE public.student_cards
    SET replaced_by=v_new_id
    WHERE id=v_previous.id;
  END IF;

  SELECT coalesce(sum(print_count),0) INTO v_total_prints
  FROM public.student_cards WHERE sid=v_student.id;

  UPDATE public.students
  SET card_printed=true,
      card_print_date=to_char(timezone('Africa/Kinshasa',v_issued_at),'YYYY-MM-DD'),
      card_print_count=v_total_prints
  WHERE id=v_student.id;

  PERFORM private.write_audit_event(
    v_actor_id,v_actor_name,'student_card_issued',
    jsonb_build_object(
      'card_id',v_new_id,'card_no',v_card_no,'student_id',v_student.id,
      'year',v_year,'emission',v_emission,
      'replaces',CASE WHEN v_previous.id IS NULL THEN NULL ELSE v_previous.id END
    ),
    v_student.id
  );

  RETURN jsonb_build_object(
    'ok',true,'code','CARD_ISSUED',
    'data',jsonb_build_object(
      'id',v_new_id,'sid',v_student.id,'year',v_year,'card_no',v_card_no,
      'class_id',v_student.cid,'class_name',v_class.name,'status','active',
      'emission',v_emission,'motif',v_motif,'note',v_note,'photo',v_photo,
      'qr_payload',v_qr,'issued_by',v_actor_id,'issued_by_name',v_actor_name,
      'issued_at',v_issued_at,'print_count',1,
      'replaces',CASE WHEN v_previous.id IS NULL THEN NULL ELSE v_previous.id END
    )
  );
END;
$$;

-- --------------------------------------------------------------------------
-- 5. Perte / révocation / réimpression.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.declare_student_card_lost(p_card_id text,p_motif text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_actor_id text := private.current_app_user_id();
  v_actor_name text;
  v_motif text := nullif(btrim(coalesce(p_motif,'')),'');
  v_card public.student_cards%rowtype;
  v_year text;
BEGIN
  IF NOT private.can_manage_student_cards() THEN
    RETURN jsonb_build_object('ok',false,'code','CARD_ROLE_DENIED');
  END IF;
  IF v_motif IS NULL OR length(v_motif)<3 THEN
    RETURN jsonb_build_object('ok',false,'code','CARD_MOTIF_REQUIRED');
  END IF;

  SELECT name INTO v_actor_name FROM public.users WHERE id=v_actor_id AND status='active';
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); END IF;

  SELECT * INTO v_card FROM public.student_cards WHERE id=p_card_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','CARD_NOT_FOUND'); END IF;

  PERFORM pg_advisory_xact_lock(hashtext('student-card:' || v_card.sid || ':' || v_card.year));
  SELECT * INTO v_card FROM public.student_cards WHERE id=p_card_id FOR UPDATE;

  IF v_card.status<>'active' THEN
    RETURN jsonb_build_object('ok',false,'code','CARD_NOT_ACTIVE');
  END IF;

  UPDATE public.student_cards
  SET status='perdue',invalidated_at=now(),invalidated_by=v_actor_id,
      invalidated_by_name=v_actor_name,invalidated_reason=left(v_motif,500)
  WHERE id=v_card.id;

  SELECT year INTO v_year FROM public.settings WHERE id='main';
  UPDATE public.students s
  SET card_printed=EXISTS(
    SELECT 1 FROM public.student_cards c
    WHERE c.sid=s.id AND c.year=v_year AND c.status='active'
  )
  WHERE s.id=v_card.sid;

  PERFORM private.write_audit_event(v_actor_id,v_actor_name,'student_card_lost',
    jsonb_build_object('card_id',v_card.id,'card_no',v_card.card_no,'reason',v_motif),v_card.sid);

  RETURN jsonb_build_object('ok',true,'code','CARD_DECLARED_LOST',
    'data',jsonb_build_object('id',v_card.id,'card_no',v_card.card_no,'status','perdue'));
END;
$$;

CREATE OR REPLACE FUNCTION public.revoke_student_card(p_card_id text,p_motif text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_actor_id text := private.current_app_user_id();
  v_actor_name text;
  v_motif text := nullif(btrim(coalesce(p_motif,'')),'');
  v_card public.student_cards%rowtype;
  v_year text;
BEGIN
  IF NOT private.can_manage_student_cards() THEN
    RETURN jsonb_build_object('ok',false,'code','CARD_ROLE_DENIED');
  END IF;
  IF v_motif IS NULL OR length(v_motif)<3 THEN
    RETURN jsonb_build_object('ok',false,'code','CARD_MOTIF_REQUIRED');
  END IF;

  SELECT name INTO v_actor_name FROM public.users WHERE id=v_actor_id AND status='active';
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); END IF;

  SELECT * INTO v_card FROM public.student_cards WHERE id=p_card_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','CARD_NOT_FOUND'); END IF;

  PERFORM pg_advisory_xact_lock(hashtext('student-card:' || v_card.sid || ':' || v_card.year));
  SELECT * INTO v_card FROM public.student_cards WHERE id=p_card_id FOR UPDATE;

  IF v_card.status<>'active' THEN
    RETURN jsonb_build_object('ok',false,'code','CARD_NOT_ACTIVE');
  END IF;

  UPDATE public.student_cards
  SET status='revoquee',invalidated_at=now(),invalidated_by=v_actor_id,
      invalidated_by_name=v_actor_name,invalidated_reason=left(v_motif,500)
  WHERE id=v_card.id;

  SELECT year INTO v_year FROM public.settings WHERE id='main';
  UPDATE public.students s
  SET card_printed=EXISTS(
    SELECT 1 FROM public.student_cards c
    WHERE c.sid=s.id AND c.year=v_year AND c.status='active'
  )
  WHERE s.id=v_card.sid;

  PERFORM private.write_audit_event(v_actor_id,v_actor_name,'student_card_revoked',
    jsonb_build_object('card_id',v_card.id,'card_no',v_card.card_no,'reason',v_motif),v_card.sid);

  RETURN jsonb_build_object('ok',true,'code','CARD_REVOKED',
    'data',jsonb_build_object('id',v_card.id,'card_no',v_card.card_no,'status','revoquee'));
END;
$$;

CREATE OR REPLACE FUNCTION public.count_student_card_print(p_card_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_actor_id text := private.current_app_user_id();
  v_actor_name text;
  v_card public.student_cards%rowtype;
  v_total_prints numeric;
BEGIN
  IF NOT private.can_manage_student_cards() THEN
    RETURN jsonb_build_object('ok',false,'code','CARD_ROLE_DENIED');
  END IF;

  SELECT name INTO v_actor_name FROM public.users WHERE id=v_actor_id AND status='active';
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); END IF;

  UPDATE public.student_cards
  SET print_count=print_count+1
  WHERE id=p_card_id AND status='active'
  RETURNING * INTO v_card;

  IF NOT FOUND THEN
    IF EXISTS(SELECT 1 FROM public.student_cards WHERE id=p_card_id) THEN
      RETURN jsonb_build_object('ok',false,'code','CARD_NOT_ACTIVE');
    END IF;
    RETURN jsonb_build_object('ok',false,'code','CARD_NOT_FOUND');
  END IF;

  SELECT coalesce(sum(print_count),0) INTO v_total_prints
  FROM public.student_cards WHERE sid=v_card.sid;

  UPDATE public.students SET card_print_count=v_total_prints WHERE id=v_card.sid;

  PERFORM private.write_audit_event(v_actor_id,v_actor_name,'student_card_reprinted',
    jsonb_build_object('card_id',v_card.id,'card_no',v_card.card_no,'print_count',v_card.print_count),v_card.sid);

  RETURN jsonb_build_object('ok',true,'code','CARD_PRINT_COUNTED',
    'data',jsonb_build_object('id',v_card.id,'card_no',v_card.card_no,'print_count',v_card.print_count));
END;
$$;

-- --------------------------------------------------------------------------
-- 6. Lecture filtrée par rôle.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_student_card_center(
  p_sid text DEFAULT NULL,
  p_year text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_role text := private.current_app_role();
  v_cards jsonb;
BEGIN
  IF v_role IN ('direction','direction2') THEN
    SELECT coalesce(jsonb_agg(to_jsonb(c) ORDER BY c.issued_at DESC),'[]'::jsonb)
    INTO v_cards
    FROM public.student_cards c
    WHERE (p_sid IS NULL OR c.sid=p_sid)
      AND (p_year IS NULL OR c.year=p_year);

  ELSIF v_role='enseignant' THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id',c.id,'sid',c.sid,'year',c.year,'card_no',c.card_no,'status',c.status,
      'emission',c.emission,'issued_at',c.issued_at,'class_id',c.class_id
    ) ORDER BY c.issued_at DESC),'[]'::jsonb)
    INTO v_cards
    FROM public.student_cards c
    WHERE private.teaches_class(c.class_id)
      AND (p_sid IS NULL OR c.sid=p_sid)
      AND (p_year IS NULL OR c.year=p_year);

  ELSIF v_role='parent' THEN
    SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id',c.id,'sid',c.sid,'year',c.year,'card_no',c.card_no,'status',c.status,
      'issued_at',c.issued_at
    ) ORDER BY c.issued_at DESC),'[]'::jsonb)
    INTO v_cards
    FROM public.student_cards c
    WHERE private.owns_student(c.sid)
      AND (p_sid IS NULL OR c.sid=p_sid)
      AND (p_year IS NULL OR c.year=p_year);

  ELSE
    RETURN jsonb_build_object('ok',false,'code','CARD_ROLE_DENIED');
  END IF;

  RETURN jsonb_build_object('ok',true,'cards',v_cards);
END;
$$;

-- --------------------------------------------------------------------------
-- 7. Vérification QR permanent au portail.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.verify_student_card_qr(p_payload text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_match text[];
  v_card_no text;
  v_sig text;
  v_secret bytea;
  v_expected text;
  v_card public.student_cards%rowtype;
  v_student public.students%rowtype;
  v_year text;
  v_refusal text;
BEGIN
  IF NOT private.can_verify_student_card() THEN
    RETURN jsonb_build_object('ok',false,'valid',false,'refusal_code','CARD_ROLE_DENIED');
  END IF;

  v_match := regexp_match(coalesce(p_payload,''), '^schoolsafe://card/([^/]+)/([0-9A-Fa-f]{8})$');
  IF v_match IS NULL THEN
    RETURN jsonb_build_object('ok',true,'valid',false,'refusal_code','CARD_QR_FORMAT_INVALID');
  END IF;

  v_card_no := v_match[1];
  v_sig := lower(v_match[2]);

  SELECT secret INTO v_secret FROM private.qr_keys WHERE id='student_card_v1';
  IF v_secret IS NULL THEN
    RETURN jsonb_build_object('ok',false,'valid',false,'refusal_code','CARD_QR_SECRET_MISSING');
  END IF;

  v_expected := left(
    encode(extensions.hmac(convert_to('card:' || v_card_no,'UTF8'),v_secret,'sha256'),'hex'),
    8
  );

  IF v_sig<>lower(v_expected) THEN
    RETURN jsonb_build_object('ok',true,'valid',false,'refusal_code','CARD_QR_SIGNATURE_INVALID');
  END IF;

  SELECT * INTO v_card FROM public.student_cards WHERE card_no=v_card_no;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',true,'valid',false,'refusal_code','CARD_NOT_FOUND');
  END IF;

  IF v_card.status<>'active' THEN
    v_refusal := CASE v_card.status
      WHEN 'perdue' THEN 'CARD_LOST'
      WHEN 'remplacee' THEN 'CARD_REPLACED'
      WHEN 'deterioree' THEN 'CARD_DAMAGED'
      WHEN 'revoquee' THEN 'CARD_REVOKED'
      ELSE 'CARD_NOT_ACTIVE'
    END;
    RETURN jsonb_build_object(
      'ok',true,'valid',false,'refusal_code',v_refusal,
      'card',jsonb_build_object('card_no',v_card.card_no,'status',v_card.status)
    );
  END IF;

  SELECT year INTO v_year FROM public.settings WHERE id='main';
  IF v_card.year IS DISTINCT FROM v_year THEN
    RETURN jsonb_build_object(
      'ok',true,'valid',false,'refusal_code','CARD_WRONG_YEAR',
      'card',jsonb_build_object('card_no',v_card.card_no,'year',v_card.year,'status',v_card.status),
      'current_year',v_year
    );
  END IF;

  SELECT * INTO v_student FROM public.students WHERE id=v_card.sid;
  IF NOT FOUND OR coalesce(v_student.archived,false) THEN
    RETURN jsonb_build_object('ok',true,'valid',false,'refusal_code','CARD_STUDENT_ARCHIVED');
  END IF;

  RETURN jsonb_build_object(
    'ok',true,'valid',true,'refusal_code',NULL,
    'card',jsonb_build_object(
      'id',v_card.id,'card_no',v_card.card_no,'year',v_card.year,'status',v_card.status
    ),
    'student',jsonb_build_object(
      'id',v_student.id,'name',v_student.name,'mat',v_student.mat,
      'photo',v_card.photo,'class_name',v_card.class_name
    )
  );
END;
$$;

-- --------------------------------------------------------------------------
-- 8. Permissions RPC.
-- --------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.issue_student_card(text,text,text,text,text,text,text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.declare_student_card_lost(text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.revoke_student_card(text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.count_student_card_print(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_student_card_center(text,text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.verify_student_card_qr(text) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.issue_student_card(text,text,text,text,text,text,text,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.declare_student_card_lost(text,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.revoke_student_card(text,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.count_student_card_print(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_student_card_center(text,text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.verify_student_card_qr(text) TO authenticated, service_role;

-- DRAFT : aucune modification conservée si ce fichier est exécuté tel quel.
ROLLBACK;
