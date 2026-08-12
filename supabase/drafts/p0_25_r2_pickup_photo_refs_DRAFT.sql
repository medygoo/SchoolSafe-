-- ============================================================================
-- SchoolSafe P0-25 — R2 PICKUP PHOTO REFERENCES
-- DRAFT ONLY — NE PAS APPLIQUER EN PRODUCTION
-- ROLLBACK final volontaire.
-- ============================================================================

BEGIN;

-- --------------------------------------------------------------------------
-- 1. Références permanentes R2. Les anciens champs URL restent en place pour
--    la compatibilité historique.
-- --------------------------------------------------------------------------

ALTER TABLE public.aps
  ADD COLUMN IF NOT EXISTS photo_file_id uuid,
  ADD COLUMN IF NOT EXISTS photo_full_body_file_id uuid;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS photo_file_id uuid,
  ADD COLUMN IF NOT EXISTS identity_full_body_photo_file_id uuid;

ALTER TABLE public.student_exit_events
  ADD COLUMN IF NOT EXISTS escort_photo_portrait_file_id_snapshot uuid,
  ADD COLUMN IF NOT EXISTS escort_photo_full_body_file_id_snapshot uuid;

ALTER TABLE public.scan_log
  ADD COLUMN IF NOT EXISTS escort_photo_portrait_file_id uuid,
  ADD COLUMN IF NOT EXISTS escort_photo_full_body_file_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.aps'::regclass AND conname='aps_photo_file_id_fkey'
  ) THEN
    ALTER TABLE public.aps
      ADD CONSTRAINT aps_photo_file_id_fkey
      FOREIGN KEY(photo_file_id) REFERENCES public.school_files(id) ON DELETE RESTRICT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.aps'::regclass AND conname='aps_photo_full_body_file_id_fkey'
  ) THEN
    ALTER TABLE public.aps
      ADD CONSTRAINT aps_photo_full_body_file_id_fkey
      FOREIGN KEY(photo_full_body_file_id) REFERENCES public.school_files(id) ON DELETE RESTRICT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.users'::regclass AND conname='users_photo_file_id_fkey'
  ) THEN
    ALTER TABLE public.users
      ADD CONSTRAINT users_photo_file_id_fkey
      FOREIGN KEY(photo_file_id) REFERENCES public.school_files(id) ON DELETE RESTRICT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.users'::regclass AND conname='users_identity_full_body_photo_file_id_fkey'
  ) THEN
    ALTER TABLE public.users
      ADD CONSTRAINT users_identity_full_body_photo_file_id_fkey
      FOREIGN KEY(identity_full_body_photo_file_id) REFERENCES public.school_files(id) ON DELETE RESTRICT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.student_exit_events'::regclass AND conname='student_exit_events_escort_portrait_file_fkey'
  ) THEN
    ALTER TABLE public.student_exit_events
      ADD CONSTRAINT student_exit_events_escort_portrait_file_fkey
      FOREIGN KEY(escort_photo_portrait_file_id_snapshot) REFERENCES public.school_files(id) ON DELETE RESTRICT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.student_exit_events'::regclass AND conname='student_exit_events_escort_full_body_file_fkey'
  ) THEN
    ALTER TABLE public.student_exit_events
      ADD CONSTRAINT student_exit_events_escort_full_body_file_fkey
      FOREIGN KEY(escort_photo_full_body_file_id_snapshot) REFERENCES public.school_files(id) ON DELETE RESTRICT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.scan_log'::regclass AND conname='scan_log_escort_portrait_file_fkey'
  ) THEN
    ALTER TABLE public.scan_log
      ADD CONSTRAINT scan_log_escort_portrait_file_fkey
      FOREIGN KEY(escort_photo_portrait_file_id) REFERENCES public.school_files(id) ON DELETE RESTRICT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.scan_log'::regclass AND conname='scan_log_escort_full_body_file_fkey'
  ) THEN
    ALTER TABLE public.scan_log
      ADD CONSTRAINT scan_log_escort_full_body_file_fkey
      FOREIGN KEY(escort_photo_full_body_file_id) REFERENCES public.school_files(id) ON DELETE RESTRICT;
  END IF;
END $$;

-- L'ancienne contrainte exigeait absolument les deux champs texte. Une personne
-- active peut maintenant porter soit l'ancienne URL, soit le nouveau file_id.
ALTER TABLE public.aps DROP CONSTRAINT IF EXISTS aps_active_requires_approval_check;
ALTER TABLE public.aps
  ADD CONSTRAINT aps_active_requires_approval_check
  CHECK (
    NOT active OR (
      approval_status='approved'
      AND (photo_file_id IS NOT NULL OR length(btrim(coalesce(photo,'')))>0)
      AND (photo_full_body_file_id IS NOT NULL OR length(btrim(coalesce(photo_full_body,'')))>0)
      AND length(btrim(coalesce(id_doc_type,'')))>0
      AND length(btrim(coalesce(id_doc_last4,''))) BETWEEN 2 AND 12
    )
  );

CREATE INDEX IF NOT EXISTS idx_aps_photo_file_id ON public.aps(photo_file_id) WHERE photo_file_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_aps_photo_full_body_file_id ON public.aps(photo_full_body_file_id) WHERE photo_full_body_file_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_users_photo_file_id ON public.users(photo_file_id) WHERE photo_file_id IS NOT NULL;

-- --------------------------------------------------------------------------
-- 2. Validation centralisée d'une référence R2.
-- --------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.pickup_photo_file_status(
  p_file_id uuid,
  p_owner_type text,
  p_owner_id text
)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  f public.school_files%rowtype;
BEGIN
  IF p_file_id IS NULL THEN RETURN 'PHOTO_FILE_NOT_FOUND'; END IF;

  SELECT * INTO f FROM public.school_files WHERE id=p_file_id;
  IF NOT FOUND THEN RETURN 'PHOTO_FILE_NOT_FOUND'; END IF;

  IF f.archived_at IS NOT NULL OR f.deleted_at IS NOT NULL THEN
    RETURN 'PHOTO_FILE_UNAVAILABLE';
  END IF;

  IF f.owner_type IS DISTINCT FROM p_owner_type OR f.owner_id IS DISTINCT FROM p_owner_id THEN
    RETURN 'PHOTO_FILE_OWNER_MISMATCH';
  END IF;

  IF f.category<>'photo' OR f.mime_type NOT IN ('image/jpeg','image/png','image/webp') THEN
    RETURN 'PHOTO_FILE_INVALID_TYPE';
  END IF;

  RETURN 'OK';
END;
$$;

REVOKE ALL ON FUNCTION private.pickup_photo_file_status(uuid,text,text)
FROM PUBLIC, anon, authenticated;

-- --------------------------------------------------------------------------
-- 3. Réservation d'une nouvelle personne AVANT les uploads.
--    La ligne reste pending + inactive : elle ne permet aucune sortie.
-- --------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.reserve_authorized_pickup_person(p_person jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_role text:=private.current_app_role();
  v_actor_id text:=private.current_app_user_id();
  v_actor_name text;
  v_id text:=nullif(btrim(coalesce(p_person->>'id','')),'');
  v_sid text:=nullif(btrim(coalesce(p_person->>'sid','')),'');
  v_name text:=nullif(btrim(coalesce(p_person->>'name','')),'');
  v_relation text:=nullif(btrim(coalesce(p_person->>'relation','')),'');
  v_phone text:=private.normalize_phone_e164(p_person->>'phone');
  v_doc_type text:=nullif(btrim(coalesce(p_person->>'id_doc_type','')),'');
  v_doc_last4 text:=nullif(btrim(coalesce(p_person->>'id_doc_last4','')),'');
  v_valid_from date;
  v_valid_until date;
  v_count integer;
  v_existing public.aps%rowtype;
  v_reused boolean:=false;
BEGIN
  IF p_person IS NULL OR jsonb_typeof(p_person)<>'object' THEN
    RETURN jsonb_build_object('ok',false,'code','INVALID_PAYLOAD');
  END IF;
  IF v_role NOT IN ('direction','direction2') THEN
    RETURN jsonb_build_object('ok',false,'code','FORBIDDEN');
  END IF;

  SELECT name INTO v_actor_name FROM public.users
  WHERE id=v_actor_id AND status='active' LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); END IF;

  IF v_sid IS NULL OR NOT EXISTS(
    SELECT 1 FROM public.students s WHERE s.id=v_sid AND NOT coalesce(s.archived,false)
  ) THEN RETURN jsonb_build_object('ok',false,'code','STUDENT_NOT_FOUND'); END IF;

  IF v_name IS NULL OR length(v_name)<3 OR length(v_name)>200 THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','name');
  END IF;
  IF v_relation IS NULL OR length(v_relation)<2 OR length(v_relation)>100 THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','relation');
  END IF;
  IF v_phone IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','phone');
  END IF;
  IF v_doc_type IS NULL OR length(v_doc_type)>80 THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','id_doc_type');
  END IF;
  IF v_doc_last4 IS NULL OR length(v_doc_last4) NOT BETWEEN 2 AND 12 THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','id_doc_last4');
  END IF;

  BEGIN
    v_valid_from:=coalesce(
      nullif(btrim(coalesce(p_person->>'valid_from','')),'')::date,
      timezone('Africa/Kinshasa',now())::date
    );
    v_valid_until:=nullif(btrim(coalesce(p_person->>'valid_until','')),'')::date;
  EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','validity');
  END;

  IF v_valid_until IS NOT NULL AND v_valid_until<v_valid_from THEN
    RETURN jsonb_build_object('ok',false,'code','INVALID_VALIDITY_PERIOD');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('aps:'||v_sid));

  SELECT count(*) INTO v_count FROM public.aps a
  WHERE a.sid=v_sid AND a.active AND a.approval_status='approved'
    AND (a.valid_until IS NULL OR a.valid_until>=timezone('Africa/Kinshasa',now())::date)
    AND (v_id IS NULL OR a.id<>v_id);
  IF v_count>=3 THEN
    RETURN jsonb_build_object('ok',false,'code','MAX_THREE_AUTHORIZED');
  END IF;

  IF v_id IS NOT NULL THEN
    SELECT * INTO v_existing FROM public.aps WHERE id=v_id FOR UPDATE;
    IF FOUND THEN
      IF v_existing.sid<>v_sid THEN
        RETURN jsonb_build_object('ok',false,'code','STUDENT_CHANGE_FORBIDDEN');
      END IF;
      IF v_existing.active OR v_existing.approval_status='approved' THEN
        RETURN jsonb_build_object('ok',false,'code','AUTHORIZED_PERSON_ALREADY_ACTIVE');
      END IF;
      v_reused:=true;
    END IF;
  ELSE
    SELECT * INTO v_existing
    FROM public.aps a
    WHERE a.sid=v_sid
      AND a.phone=v_phone
      AND NOT a.active
      AND a.approval_status='pending'
      AND a.proposed_by=v_actor_id
      AND a.proposed_at>=now()-interval '24 hours'
    ORDER BY a.proposed_at DESC
    LIMIT 1
    FOR UPDATE;

    IF FOUND THEN
      v_id:=v_existing.id;
      v_reused:=true;
    ELSE
      v_id:='aps_'||replace(gen_random_uuid()::text,'-','');
    END IF;
  END IF;

  INSERT INTO public.aps(
    id,sid,name,relation,photo,photo_full_body,photo_file_id,photo_full_body_file_id,
    active,phone,approval_status,proposed_by,proposed_at,approved_by,approved_at,
    rejection_reason,id_doc_type,id_doc_last4,valid_from,valid_until,
    created_by,created_by_name,updated_at,suspended_by,suspended_at,status_note
  ) VALUES (
    v_id,v_sid,v_name,v_relation,NULL,NULL,NULL,NULL,
    false,v_phone,'pending',v_actor_id,now(),NULL,NULL,
    NULL,v_doc_type,v_doc_last4,v_valid_from,v_valid_until,
    v_actor_id,v_actor_name,now(),NULL,NULL,'IDENTITY_UPLOAD_PENDING'
  )
  ON CONFLICT(id) DO UPDATE SET
    name=excluded.name,
    relation=excluded.relation,
    phone=excluded.phone,
    id_doc_type=excluded.id_doc_type,
    id_doc_last4=excluded.id_doc_last4,
    valid_from=excluded.valid_from,
    valid_until=excluded.valid_until,
    proposed_by=v_actor_id,
    proposed_at=now(),
    status_note='IDENTITY_UPLOAD_PENDING',
    updated_at=now()
  WHERE public.aps.sid=excluded.sid
    AND public.aps.active=false
    AND public.aps.approval_status='pending';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok',false,'code','RESERVATION_STATE_CONFLICT');
  END IF;

  PERFORM private.write_audit_event(
    v_actor_id,v_actor_name,
    CASE WHEN v_reused THEN 'authorized_pickup_upload_reservation_reused'
         ELSE 'authorized_pickup_upload_reserved' END,
    jsonb_build_object('student_id',v_sid,'person_id',v_id,'relation',v_relation),
    v_sid
  );

  RETURN jsonb_build_object(
    'ok',true,
    'code',CASE WHEN v_reused THEN 'AUTHORIZED_PERSON_UPLOAD_RESERVATION_REUSED'
                ELSE 'AUTHORIZED_PERSON_UPLOAD_RESERVED' END,
    'person_id',v_id,
    'upload',jsonb_build_object(
      'owner_type','authorized_person',
      'owner_id',v_id,
      'category','photo'
    )
  );
END;
$$;

REVOKE ALL ON FUNCTION public.reserve_authorized_pickup_person(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reserve_authorized_pickup_person(jsonb) TO authenticated;

-- --------------------------------------------------------------------------
-- 4. save_authorized_pickup_person conserve son nom RPC mais accepte désormais
--    les UUID R2 dédiés. Les anciennes URL restent un repli de compatibilité.
-- --------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.save_authorized_pickup_person(p_person jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_role text:=private.current_app_role();
  v_actor_id text:=private.current_app_user_id();
  v_actor_name text;
  v_id text:=nullif(btrim(coalesce(p_person->>'id','')),'');
  v_sid text:=nullif(btrim(coalesce(p_person->>'sid','')),'');
  v_name text:=nullif(btrim(coalesce(p_person->>'name','')),'');
  v_relation text:=nullif(btrim(coalesce(p_person->>'relation','')),'');
  v_phone text:=private.normalize_phone_e164(p_person->>'phone');
  v_photo text:=nullif(btrim(coalesce(p_person->>'photo_portrait',p_person->>'photo','')),'');
  v_photo_full text:=nullif(btrim(coalesce(p_person->>'photo_full_body','')),'');
  v_photo_file_text text:=nullif(btrim(coalesce(p_person->>'photo_portrait_file_id','')),'');
  v_full_file_text text:=nullif(btrim(coalesce(p_person->>'photo_full_body_file_id','')),'');
  v_photo_file uuid;
  v_full_file uuid;
  v_photo_status text;
  v_full_status text;
  v_doc_type text:=nullif(btrim(coalesce(p_person->>'id_doc_type','')),'');
  v_doc_last4 text:=nullif(btrim(coalesce(p_person->>'id_doc_last4','')),'');
  v_valid_from date;
  v_valid_until date;
  v_existing public.aps%rowtype;
  v_saved public.aps%rowtype;
  v_count integer;
BEGIN
  IF p_person IS NULL OR jsonb_typeof(p_person)<>'object' THEN
    RETURN jsonb_build_object('ok',false,'code','INVALID_PAYLOAD');
  END IF;
  IF v_role NOT IN ('direction','direction2') THEN
    RETURN jsonb_build_object('ok',false,'code','FORBIDDEN');
  END IF;

  SELECT name INTO v_actor_name FROM public.users
  WHERE id=v_actor_id AND status='active' LIMIT 1;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); END IF;

  IF v_sid IS NULL OR NOT EXISTS(
    SELECT 1 FROM public.students s WHERE s.id=v_sid AND NOT coalesce(s.archived,false)
  ) THEN RETURN jsonb_build_object('ok',false,'code','STUDENT_NOT_FOUND'); END IF;

  IF v_id IS NULL THEN
    -- Une nouvelle personne R2 doit d'abord avoir un owner_id serveur.
    IF v_photo_file_text IS NOT NULL OR v_full_file_text IS NOT NULL THEN
      RETURN jsonb_build_object('ok',false,'code','UPLOAD_RESERVATION_REQUIRED');
    END IF;
    v_id:='aps_'||replace(gen_random_uuid()::text,'-','');
  END IF;

  IF v_name IS NULL OR length(v_name)<3 OR length(v_name)>200 THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','name');
  END IF;
  IF v_relation IS NULL OR length(v_relation)<2 OR length(v_relation)>100 THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','relation');
  END IF;
  IF v_phone IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','phone');
  END IF;
  IF v_doc_type IS NULL OR length(v_doc_type)>80 THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','id_doc_type');
  END IF;
  IF v_doc_last4 IS NULL OR length(v_doc_last4) NOT BETWEEN 2 AND 12 THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','id_doc_last4');
  END IF;

  BEGIN
    v_valid_from:=coalesce(
      nullif(btrim(coalesce(p_person->>'valid_from','')),'')::date,
      timezone('Africa/Kinshasa',now())::date
    );
    v_valid_until:=nullif(btrim(coalesce(p_person->>'valid_until','')),'')::date;
  EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','validity');
  END;
  IF v_valid_until IS NOT NULL AND v_valid_until<v_valid_from THEN
    RETURN jsonb_build_object('ok',false,'code','INVALID_VALIDITY_PERIOD');
  END IF;

  IF v_photo_file_text IS NOT NULL THEN
    BEGIN v_photo_file:=v_photo_file_text::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
      RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','photo_portrait_file_id');
    END;
    v_photo_status:=private.pickup_photo_file_status(v_photo_file,'authorized_person',v_id);
    IF v_photo_status<>'OK' THEN RETURN jsonb_build_object('ok',false,'code',v_photo_status,'field','photo_portrait_file_id'); END IF;
  ELSIF v_photo IS NULL OR lower(v_photo) LIKE 'data:%' OR length(v_photo)>2048 THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','photo_portrait');
  END IF;

  IF v_full_file_text IS NOT NULL THEN
    BEGIN v_full_file:=v_full_file_text::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
      RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','photo_full_body_file_id');
    END;
    v_full_status:=private.pickup_photo_file_status(v_full_file,'authorized_person',v_id);
    IF v_full_status<>'OK' THEN RETURN jsonb_build_object('ok',false,'code',v_full_status,'field','photo_full_body_file_id'); END IF;
  ELSIF v_photo_full IS NULL OR lower(v_photo_full) LIKE 'data:%' OR length(v_photo_full)>2048 THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','photo_full_body');
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('aps:'||v_sid));

  SELECT * INTO v_existing FROM public.aps WHERE id=v_id FOR UPDATE;
  IF FOUND AND v_existing.sid<>v_sid THEN
    RETURN jsonb_build_object('ok',false,'code','STUDENT_CHANGE_FORBIDDEN');
  END IF;

  SELECT count(*) INTO v_count FROM public.aps a
  WHERE a.sid=v_sid AND a.id<>v_id AND a.active AND a.approval_status='approved'
    AND (a.valid_until IS NULL OR a.valid_until>=timezone('Africa/Kinshasa',now())::date);
  IF v_count>=3 THEN RETURN jsonb_build_object('ok',false,'code','MAX_THREE_AUTHORIZED'); END IF;

  INSERT INTO public.aps(
    id,sid,name,relation,photo,photo_full_body,photo_file_id,photo_full_body_file_id,
    active,phone,approval_status,proposed_by,proposed_at,approved_by,approved_at,
    rejection_reason,id_doc_type,id_doc_last4,valid_from,valid_until,
    created_by,created_by_name,updated_at,suspended_by,suspended_at,status_note
  ) VALUES (
    v_id,v_sid,v_name,v_relation,v_photo,v_photo_full,v_photo_file,v_full_file,
    true,v_phone,'approved',v_actor_id,now(),v_actor_id,now(),NULL,
    v_doc_type,v_doc_last4,v_valid_from,v_valid_until,v_actor_id,v_actor_name,
    now(),NULL,NULL,NULL
  )
  ON CONFLICT(id) DO UPDATE SET
    name=excluded.name,
    relation=excluded.relation,
    photo=excluded.photo,
    photo_full_body=excluded.photo_full_body,
    photo_file_id=excluded.photo_file_id,
    photo_full_body_file_id=excluded.photo_full_body_file_id,
    phone=excluded.phone,
    approval_status='approved',
    active=true,
    approved_by=v_actor_id,
    approved_at=now(),
    rejection_reason=NULL,
    id_doc_type=excluded.id_doc_type,
    id_doc_last4=excluded.id_doc_last4,
    valid_from=excluded.valid_from,
    valid_until=excluded.valid_until,
    updated_at=now(),
    suspended_by=NULL,
    suspended_at=NULL,
    status_note=NULL
  RETURNING * INTO v_saved;

  PERFORM private.write_audit_event(
    v_actor_id,v_actor_name,
    CASE WHEN v_existing.id IS NULL THEN 'authorized_pickup_person_created'
         ELSE 'authorized_pickup_person_updated' END,
    jsonb_build_object(
      'student_id',v_sid,'person_id',v_saved.id,'relation',v_relation,
      'valid_until',v_valid_until,
      'portrait_storage',CASE WHEN v_saved.photo_file_id IS NOT NULL THEN 'r2' ELSE 'legacy' END,
      'full_body_storage',CASE WHEN v_saved.photo_full_body_file_id IS NOT NULL THEN 'r2' ELSE 'legacy' END
    ),
    v_sid
  );

  RETURN jsonb_build_object(
    'ok',true,
    'code',CASE WHEN v_existing.id IS NULL THEN 'AUTHORIZED_PERSON_CREATED'
                ELSE 'AUTHORIZED_PERSON_UPDATED' END,
    'person',to_jsonb(v_saved)
  );
EXCEPTION
  WHEN check_violation THEN RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR');
  WHEN foreign_key_violation THEN RETURN jsonb_build_object('ok',false,'code','REFERENCE_NOT_FOUND');
END;
$$;

-- --------------------------------------------------------------------------
-- 5. Parent principal : la signature frontend reste identique. Si un paramètre
--    photo est un UUID, il est validé comme school_files.id du parent.
-- --------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.save_primary_parent_pickup_identity(
  p_parent_id text,
  p_photo_portrait text,
  p_photo_full_body text,
  p_id_doc_type text,
  p_id_doc_last4 text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_role text:=private.current_app_role();
  v_actor_id text:=private.current_app_user_id();
  v_actor_name text;
  v_parent public.users%rowtype;
  v_portrait text:=nullif(btrim(coalesce(p_photo_portrait,'')),'');
  v_full text:=nullif(btrim(coalesce(p_photo_full_body,'')),'');
  v_portrait_file uuid;
  v_full_file uuid;
  v_portrait_is_uuid boolean:=false;
  v_full_is_uuid boolean:=false;
  v_status text;
  v_doc_type text:=nullif(btrim(coalesce(p_id_doc_type,'')),'');
  v_doc_last4 text:=nullif(btrim(coalesce(p_id_doc_last4,'')),'');
BEGIN
  IF v_role NOT IN ('direction','direction2') THEN RETURN jsonb_build_object('ok',false,'code','FORBIDDEN'); END IF;
  SELECT name INTO v_actor_name FROM public.users WHERE id=v_actor_id AND status='active';
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); END IF;

  SELECT * INTO v_parent FROM public.users WHERE id=p_parent_id AND role='parent' FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','PARENT_NOT_FOUND'); END IF;

  IF v_doc_type IS NULL OR length(v_doc_type)>80 THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','id_doc_type');
  END IF;
  IF v_doc_last4 IS NULL OR length(v_doc_last4) NOT BETWEEN 2 AND 12 THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','id_doc_last4');
  END IF;

  IF v_portrait IS NULL OR lower(v_portrait) LIKE 'data:%' OR length(v_portrait)>2048 THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','photo_portrait');
  END IF;
  BEGIN
    v_portrait_file:=v_portrait::uuid;
    v_portrait_is_uuid:=true;
  EXCEPTION WHEN invalid_text_representation THEN
    v_portrait_is_uuid:=false;
  END;
  IF v_portrait_is_uuid THEN
    v_status:=private.pickup_photo_file_status(v_portrait_file,'user',v_parent.id);
    IF v_status<>'OK' THEN RETURN jsonb_build_object('ok',false,'code',v_status,'field','photo_portrait'); END IF;
  END IF;

  IF v_full IS NULL OR lower(v_full) LIKE 'data:%' OR length(v_full)>2048 THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','photo_full_body');
  END IF;
  BEGIN
    v_full_file:=v_full::uuid;
    v_full_is_uuid:=true;
  EXCEPTION WHEN invalid_text_representation THEN
    v_full_is_uuid:=false;
  END;
  IF v_full_is_uuid THEN
    v_status:=private.pickup_photo_file_status(v_full_file,'user',v_parent.id);
    IF v_status<>'OK' THEN RETURN jsonb_build_object('ok',false,'code',v_status,'field','photo_full_body'); END IF;
  END IF;

  UPDATE public.users SET
    photo_url=CASE WHEN v_portrait_is_uuid THEN NULL ELSE v_portrait END,
    identity_full_body_photo_url=CASE WHEN v_full_is_uuid THEN NULL ELSE v_full END,
    photo_file_id=CASE WHEN v_portrait_is_uuid THEN v_portrait_file ELSE NULL END,
    identity_full_body_photo_file_id=CASE WHEN v_full_is_uuid THEN v_full_file ELSE NULL END,
    identity_document_type=v_doc_type,
    identity_document_last4=v_doc_last4,
    updated_at=now()
  WHERE id=v_parent.id
  RETURNING * INTO v_parent;

  PERFORM private.write_audit_event(
    v_actor_id,v_actor_name,'primary_parent_pickup_identity_updated',
    jsonb_build_object(
      'parent_id',v_parent.id,
      'has_portrait',true,'has_full_body',true,
      'portrait_storage',CASE WHEN v_parent.photo_file_id IS NOT NULL THEN 'r2' ELSE 'legacy' END,
      'full_body_storage',CASE WHEN v_parent.identity_full_body_photo_file_id IS NOT NULL THEN 'r2' ELSE 'legacy' END
    ),v_parent.id
  );

  RETURN jsonb_build_object('ok',true,'code','PRIMARY_PARENT_IDENTITY_SAVED','parent',to_jsonb(v_parent));
END;
$$;

-- --------------------------------------------------------------------------
-- 6. Le contexte de sortie expose les UUID permanents, jamais une URL signée.
-- --------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.get_student_pickup_context(p_sid text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_role text:=private.current_app_role();
  v_student public.students%rowtype;
  v_parent public.users%rowtype;
  v_people jsonb;
  v_full_phone boolean;
BEGIN
  IF NOT (private.can_scan() OR private.owns_student(p_sid)) THEN
    RAISE EXCEPTION 'Accès refusé' USING errcode='42501';
  END IF;

  SELECT * INTO v_student FROM public.students
  WHERE id=p_sid AND NOT coalesce(archived,false);
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','STUDENT_NOT_FOUND'); END IF;

  IF v_student.pid IS NOT NULL THEN
    SELECT * INTO v_parent FROM public.users WHERE id=v_student.pid AND role='parent';
  END IF;
  v_full_phone:=v_role IN ('direction','direction2','gardien');

  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'id',a.id,
    'kind','accredited',
    'name',a.name,
    'relation',a.relation,
    'phone',CASE WHEN v_full_phone THEN a.phone ELSE regexp_replace(a.phone,'^(\\+[0-9]{3})[0-9]+([0-9]{2})$','\\1••••••\\2') END,
    'photo_portrait',a.photo,
    'photo_full_body',a.photo_full_body,
    'photo_portrait_file_id',a.photo_file_id,
    'photo_full_body_file_id',a.photo_full_body_file_id,
    'id_doc_type',a.id_doc_type,
    'id_doc_last4',a.id_doc_last4,
    'valid_from',a.valid_from,
    'valid_until',a.valid_until
  ) ORDER BY a.name),'[]'::jsonb)
  INTO v_people
  FROM public.aps a
  WHERE a.sid=p_sid
    AND a.active
    AND a.approval_status='approved'
    AND a.valid_from<=timezone('Africa/Kinshasa',now())::date
    AND (a.valid_until IS NULL OR a.valid_until>=timezone('Africa/Kinshasa',now())::date);

  RETURN jsonb_build_object(
    'ok',true,
    'student',jsonb_build_object(
      'id',v_student.id,'name',v_student.name,'photo',v_student.photo,'class_id',v_student.cid
    ),
    'primary_parent',CASE WHEN v_parent.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id',v_parent.id,
      'kind','primary',
      'name',v_parent.name,
      'relation','Parent principal',
      'phone',CASE WHEN v_full_phone THEN v_parent.phone ELSE NULL END,
      'photo_portrait',v_parent.photo_url,
      'photo_full_body',v_parent.identity_full_body_photo_url,
      'photo_portrait_file_id',v_parent.photo_file_id,
      'photo_full_body_file_id',v_parent.identity_full_body_photo_file_id,
      'id_doc_type',v_parent.identity_document_type,
      'id_doc_last4',v_parent.identity_document_last4,
      'ready_for_pickup',v_parent.status='active'
        AND (v_parent.photo_url IS NOT NULL OR v_parent.photo_file_id IS NOT NULL)
        AND (v_parent.identity_full_body_photo_url IS NOT NULL OR v_parent.identity_full_body_photo_file_id IS NOT NULL)
    ) END,
    'authorized_people',v_people,
    'authorized_count',jsonb_array_length(v_people)
  );
END;
$$;

-- --------------------------------------------------------------------------
-- 7. Snapshots permanents : les fonctions existantes de sortie restent
--    inchangées ; les triggers ajoutent les file_id à côté des champs texte.
-- --------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION private.snapshot_exit_pickup_photo_file_ids()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
  IF NEW.escort_kind='primary' AND NEW.escort_id_snapshot IS NOT NULL THEN
    SELECT u.photo_file_id,u.identity_full_body_photo_file_id
    INTO NEW.escort_photo_portrait_file_id_snapshot,NEW.escort_photo_full_body_file_id_snapshot
    FROM public.users u
    WHERE u.id=NEW.escort_id_snapshot AND u.role='parent';
  ELSIF NEW.escort_kind='accredited' AND NEW.escort_id_snapshot IS NOT NULL THEN
    SELECT a.photo_file_id,a.photo_full_body_file_id
    INTO NEW.escort_photo_portrait_file_id_snapshot,NEW.escort_photo_full_body_file_id_snapshot
    FROM public.aps a
    WHERE a.id=NEW.escort_id_snapshot AND a.sid=NEW.sid;
  ELSE
    NEW.escort_photo_portrait_file_id_snapshot:=NULL;
    NEW.escort_photo_full_body_file_id_snapshot:=NULL;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_snapshot_exit_pickup_photo_file_ids ON public.student_exit_events;
CREATE TRIGGER trg_snapshot_exit_pickup_photo_file_ids
BEFORE INSERT OR UPDATE OF escort_kind,escort_id_snapshot ON public.student_exit_events
FOR EACH ROW EXECUTE FUNCTION private.snapshot_exit_pickup_photo_file_ids();

CREATE OR REPLACE FUNCTION private.snapshot_scan_log_pickup_photo_file_ids()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
BEGIN
  IF NEW.exit_event_id IS NOT NULL THEN
    SELECT e.escort_photo_portrait_file_id_snapshot,e.escort_photo_full_body_file_id_snapshot
    INTO NEW.escort_photo_portrait_file_id,NEW.escort_photo_full_body_file_id
    FROM public.student_exit_events e
    WHERE e.id=NEW.exit_event_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_snapshot_scan_log_pickup_photo_file_ids ON public.scan_log;
CREATE TRIGGER trg_snapshot_scan_log_pickup_photo_file_ids
BEFORE INSERT ON public.scan_log
FOR EACH ROW EXECUTE FUNCTION private.snapshot_scan_log_pickup_photo_file_ids();

ROLLBACK;
