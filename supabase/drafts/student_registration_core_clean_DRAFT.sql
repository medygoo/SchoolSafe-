-- ============================================================================
-- SchoolSafe — INSCRIPTION ELEVE : CONTRAT SERVEUR PROPRE
-- DRAFT DE TRAVAIL — NE PAS APPLIQUER EN PRODUCTION
-- Issue #89 / branche chatgpt/student-registration-clean
-- ROLLBACK final volontaire.
-- ============================================================================

BEGIN;

-- --------------------------------------------------------------------------
-- 1. Référence permanente de la photo R2
-- --------------------------------------------------------------------------
ALTER TABLE public.students
  ADD COLUMN IF NOT EXISTS photo_file_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.students'::regclass
      AND conname='students_photo_file_id_fkey'
  ) THEN
    ALTER TABLE public.students
      ADD CONSTRAINT students_photo_file_id_fkey
      FOREIGN KEY (photo_file_id)
      REFERENCES public.school_files(id)
      ON DELETE RESTRICT;
  END IF;
END $$;

-- --------------------------------------------------------------------------
-- 2. Intégrité relationnelle et unicité
--    Les checks préalables du futur déploiement doivent confirmer 0 orphelin
--    et 0 doublon avant d'ajouter ces contraintes.
-- --------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.students'::regclass
      AND conname='students_cid_fkey'
  ) THEN
    ALTER TABLE public.students
      ADD CONSTRAINT students_cid_fkey
      FOREIGN KEY (cid) REFERENCES public.classes(id) ON DELETE RESTRICT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.students'::regclass
      AND conname='students_pid_fkey'
  ) THEN
    ALTER TABLE public.students
      ADD CONSTRAINT students_pid_fkey
      FOREIGN KEY (pid) REFERENCES public.users(id) ON DELETE RESTRICT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.students'::regclass
      AND conname='students_created_by_fkey'
  ) THEN
    ALTER TABLE public.students
      ADD CONSTRAINT students_created_by_fkey
      FOREIGN KEY (created_by) REFERENCES public.users(id) ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid='public.students'::regclass
      AND conname='students_leave_alone_authorized_by_fkey'
  ) THEN
    ALTER TABLE public.students
      ADD CONSTRAINT students_leave_alone_authorized_by_fkey
      FOREIGN KEY (leave_alone_authorized_by) REFERENCES public.users(id) ON DELETE SET NULL;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_students_mat_normalized
ON public.students (lower(btrim(mat)))
WHERE mat IS NOT NULL AND btrim(mat)<>'';

CREATE UNIQUE INDEX IF NOT EXISTS uq_students_num_inscription_normalized
ON public.students (lower(btrim(num_inscription)))
WHERE num_inscription IS NOT NULL AND btrim(num_inscription)<>'';

-- --------------------------------------------------------------------------
-- 3. Générateur serveur commun pour l'identité scolaire
--    Utilise la même clé de compteur que validate_preinscription_email().
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.next_student_identity(p_school_year text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_year text := btrim(COALESCE(p_school_year,''));
  v_counter bigint;
BEGIN
  IF v_year !~ '^\d{4}-\d{4}$' THEN
    RAISE EXCEPTION 'Invalid school year' USING errcode='22023';
  END IF;

  INSERT INTO private.school_counters(counter_key,counter_value,updated_at)
  VALUES ('student_mat:'||v_year,1,now())
  ON CONFLICT (counter_key)
  DO UPDATE SET
    counter_value=private.school_counters.counter_value+1,
    updated_at=now()
  RETURNING counter_value INTO v_counter;

  RETURN jsonb_build_object(
    'student_id','student_'||replace(gen_random_uuid()::text,'-',''),
    'mat','LS-'||v_year||'-'||lpad(v_counter::text,6,'0'),
    'num_inscription','INS-'||v_year||'-'||lpad(v_counter::text,6,'0'),
    'sequence',v_counter,
    'school_year',v_year
  );
END;
$$;

REVOKE ALL ON FUNCTION private.next_student_identity(text)
FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.next_student_identity(text) TO service_role;

-- --------------------------------------------------------------------------
-- 4. Création idempotente des obligations financières configurées
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.ensure_student_fee_obligations(
  p_sid text,
  p_school_year text,
  p_actor_id text
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_count integer := 0;
BEGIN
  IF p_sid IS NULL OR p_school_year IS NULL THEN
    RAISE EXCEPTION 'Student and school year are required' USING errcode='22023';
  END IF;

  INSERT INTO public.student_fee_obligations(
    sid,fee_type_id,school_year,label,installment_no,amount_due,currency,
    due_date,active,created_by
  )
  SELECT
    p_sid,
    ft.id,
    p_school_year,
    COALESCE(NULLIF(btrim(ft.label),''),ft.id),
    CASE upper(COALESCE(ft.trimestre,''))
      WHEN 'T1' THEN 1
      WHEN 'T2' THEN 2
      WHEN 'T3' THEN 3
      ELSE 1
    END,
    ft.montant_defaut,
    'USD',
    NULL,
    true,
    p_actor_id
  FROM public.fee_types ft
  WHERE COALESCE(ft.active,true)
    AND COALESCE(ft.montant_defaut,0)>0
  ON CONFLICT (sid,fee_type_id,school_year,installment_no) DO NOTHING;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION private.ensure_student_fee_obligations(text,text,text)
FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION private.ensure_student_fee_obligations(text,text,text)
TO service_role;

-- --------------------------------------------------------------------------
-- 5. save_student_profile v2
--    - création : ID/matricule/numéro d'inscription générés serveur ;
--    - modification : ID existant obligatoire ;
--    - parent principal changé par RPC dédiée après création ;
--    - photo changée par RPC dédiée R2 ;
--    - clés absentes = valeur serveur conservée.
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.save_student_profile(p_student jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_role text := private.current_app_role();
  v_actor_id text := private.current_app_user_id();
  v_actor_name text;
  v_input_id text;
  v_create boolean := false;
  v_existing public.students%rowtype;
  v_saved public.students%rowtype;
  v_identity jsonb;
  v_school_year text;
  v_sid text;
  v_mat text;
  v_num_inscription text;
  v_name text;
  v_cid text;
  v_pid text;
  v_dob text;
  v_adresse text;
  v_nom_papa text;
  v_nom_maman text;
  v_lieu_naissance text;
  v_sexe text;
  v_ecole_provenance text;
  v_tutelle_principale text;
  v_fee_count integer := 0;
  v_fee_configured boolean := false;
BEGIN
  IF p_student IS NULL OR jsonb_typeof(p_student)<>'object' THEN
    RETURN jsonb_build_object('ok',false,'code','INVALID_PAYLOAD');
  END IF;

  IF v_role NOT IN ('direction','direction2') OR v_actor_id IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','FORBIDDEN');
  END IF;

  SELECT u.name INTO v_actor_name
  FROM public.users u
  WHERE u.id=v_actor_id AND u.status='active'
  LIMIT 1;
  IF NOT FOUND OR NULLIF(btrim(COALESCE(v_actor_name,'')),'') IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND');
  END IF;

  v_input_id := NULLIF(btrim(COALESCE(p_student->>'id','')),'');

  IF v_input_id IS NULL THEN
    v_create := true;
  ELSE
    SELECT * INTO v_existing
    FROM public.students s
    WHERE s.id=v_input_id
    FOR UPDATE;

    IF NOT FOUND THEN
      -- Le navigateur ne crée plus sa propre identité d'élève.
      RETURN jsonb_build_object(
        'ok',false,
        'code','SERVER_ASSIGNED_STUDENT_ID_REQUIRED',
        'field','id'
      );
    END IF;
  END IF;

  -- Valeurs : création exige nom+classe ; modification conserve les clés absentes.
  v_name := CASE
    WHEN p_student ? 'name' THEN NULLIF(btrim(COALESCE(p_student->>'name','')),'')
    WHEN NOT v_create THEN v_existing.name
    ELSE NULL
  END;
  v_cid := CASE
    WHEN p_student ? 'cid' THEN NULLIF(btrim(COALESCE(p_student->>'cid','')),'')
    WHEN NOT v_create THEN v_existing.cid
    ELSE NULL
  END;

  IF v_name IS NULL OR length(v_name)>200 THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','name');
  END IF;
  IF v_cid IS NULL OR length(v_cid)>160 THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','cid');
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.classes c WHERE c.id=v_cid) THEN
    RETURN jsonb_build_object('ok',false,'code','CLASS_NOT_FOUND');
  END IF;

  -- Matricule / numéro d'inscription : lecture compatible, jamais autorité navigateur.
  IF NOT v_create THEN
    IF p_student ? 'mat'
       AND NULLIF(btrim(COALESCE(p_student->>'mat','')),'') IS DISTINCT FROM v_existing.mat THEN
      RETURN jsonb_build_object('ok',false,'code','IMMUTABLE_STUDENT_NUMBER','field','mat');
    END IF;
    IF p_student ? 'num_inscription'
       AND NULLIF(btrim(COALESCE(p_student->>'num_inscription','')),'') IS DISTINCT FROM v_existing.num_inscription THEN
      RETURN jsonb_build_object('ok',false,'code','IMMUTABLE_STUDENT_NUMBER','field','num_inscription');
    END IF;
  END IF;

  -- Parent principal : autorisé dans la création ; changement ultérieur via RPC dédiée.
  v_pid := CASE
    WHEN p_student ? 'pid' THEN NULLIF(btrim(COALESCE(p_student->>'pid','')),'')
    WHEN NOT v_create THEN v_existing.pid
    ELSE NULL
  END;

  IF NOT v_create AND v_pid IS DISTINCT FROM v_existing.pid THEN
    RETURN jsonb_build_object('ok',false,'code','PRIMARY_PARENT_RPC_REQUIRED','field','pid');
  END IF;

  IF v_pid IS NOT NULL AND NOT EXISTS(
    SELECT 1 FROM public.users u
    WHERE u.id=v_pid AND u.role='parent' AND u.status='active'
  ) THEN
    RETURN jsonb_build_object('ok',false,'code','PARENT_NOT_FOUND');
  END IF;

  -- Photo : une nouvelle valeur ne passe plus par le profil générique.
  IF p_student ? 'photo' THEN
    IF v_create AND NULLIF(btrim(COALESCE(p_student->>'photo','')),'') IS NOT NULL THEN
      RETURN jsonb_build_object('ok',false,'code','PHOTO_FILE_UPLOAD_REQUIRED','field','photo');
    END IF;
    IF NOT v_create
       AND NULLIF(btrim(COALESCE(p_student->>'photo','')),'') IS DISTINCT FROM v_existing.photo THEN
      RETURN jsonb_build_object('ok',false,'code','PHOTO_FILE_UPLOAD_REQUIRED','field','photo');
    END IF;
  END IF;

  -- États sensibles : gardés hors du formulaire générique.
  IF NOT v_create AND p_student ? 'access_parent'
     AND (p_student->>'access_parent')::boolean IS DISTINCT FROM v_existing.access_parent THEN
    RETURN jsonb_build_object('ok',false,'code','DEDICATED_STUDENT_STATE_RPC_REQUIRED','field','access_parent');
  END IF;
  IF NOT v_create AND p_student ? 'may_leave_alone'
     AND (p_student->>'may_leave_alone')::boolean IS DISTINCT FROM v_existing.may_leave_alone THEN
    RETURN jsonb_build_object('ok',false,'code','DEDICATED_STUDENT_STATE_RPC_REQUIRED','field','may_leave_alone');
  END IF;
  IF NOT v_create AND p_student ? 'leave_alone_until'
     AND NULLIF(btrim(COALESCE(p_student->>'leave_alone_until','')),'')::date
         IS DISTINCT FROM v_existing.leave_alone_until THEN
    RETURN jsonb_build_object('ok',false,'code','DEDICATED_STUDENT_STATE_RPC_REQUIRED','field','leave_alone_until');
  END IF;

  v_dob := CASE
    WHEN p_student ? 'dob' THEN NULLIF(btrim(COALESCE(p_student->>'dob','')),'')
    WHEN NOT v_create THEN v_existing.dob
    ELSE NULL
  END;
  IF v_dob IS NOT NULL THEN
    BEGIN
      v_dob := to_char(v_dob::date,'YYYY-MM-DD');
    EXCEPTION WHEN invalid_datetime_format OR datetime_field_overflow THEN
      RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','dob');
    END;
  END IF;

  v_adresse := CASE WHEN p_student ? 'adresse' THEN NULLIF(btrim(COALESCE(p_student->>'adresse','')),'') WHEN NOT v_create THEN v_existing.adresse ELSE NULL END;
  v_nom_papa := CASE WHEN p_student ? 'nom_papa' THEN NULLIF(btrim(COALESCE(p_student->>'nom_papa','')),'') WHEN NOT v_create THEN v_existing.nom_papa ELSE NULL END;
  v_nom_maman := CASE WHEN p_student ? 'nom_maman' THEN NULLIF(btrim(COALESCE(p_student->>'nom_maman','')),'') WHEN NOT v_create THEN v_existing.nom_maman ELSE NULL END;
  v_lieu_naissance := CASE WHEN p_student ? 'lieu_naissance' THEN NULLIF(btrim(COALESCE(p_student->>'lieu_naissance','')),'') WHEN NOT v_create THEN v_existing.lieu_naissance ELSE NULL END;
  v_sexe := CASE WHEN p_student ? 'sexe' THEN NULLIF(btrim(COALESCE(p_student->>'sexe','')),'') WHEN NOT v_create THEN v_existing.sexe ELSE NULL END;
  v_ecole_provenance := CASE WHEN p_student ? 'ecole_provenance' THEN NULLIF(btrim(COALESCE(p_student->>'ecole_provenance','')),'') WHEN NOT v_create THEN v_existing.ecole_provenance ELSE NULL END;
  v_tutelle_principale := CASE WHEN p_student ? 'tutelle_principale' THEN NULLIF(btrim(COALESCE(p_student->>'tutelle_principale','')),'') WHEN NOT v_create THEN v_existing.tutelle_principale ELSE NULL END;

  IF length(COALESCE(v_adresse,''))>500 THEN RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','adresse'); END IF;
  IF length(COALESCE(v_nom_papa,''))>200 THEN RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','nom_papa'); END IF;
  IF length(COALESCE(v_nom_maman,''))>200 THEN RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','nom_maman'); END IF;
  IF length(COALESCE(v_lieu_naissance,''))>200 THEN RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','lieu_naissance'); END IF;
  IF v_sexe IS NOT NULL AND (length(v_sexe)<1 OR length(v_sexe)>30) THEN RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','sexe'); END IF;
  IF length(COALESCE(v_ecole_provenance,''))>300 THEN RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','ecole_provenance'); END IF;
  IF length(COALESCE(v_tutelle_principale,''))>300 THEN RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','tutelle_principale'); END IF;

  IF v_create THEN
    v_school_year := private.current_school_year();
    v_identity := private.next_student_identity(v_school_year);
    v_sid := v_identity->>'student_id';
    v_mat := v_identity->>'mat';
    v_num_inscription := v_identity->>'num_inscription';

    INSERT INTO public.students(
      id,name,mat,cid,pid,dob,photo,photo_file_id,adresse,nom_papa,nom_maman,
      created_by,created_by_name,access_parent,archived,created_at,
      lieu_naissance,num_inscription,may_leave_alone,leave_alone_until,
      leave_alone_authorized_by,leave_alone_authorized_at,
      sexe,ecole_provenance,tutelle_principale
    ) VALUES (
      v_sid,v_name,v_mat,v_cid,v_pid,v_dob,NULL,NULL,v_adresse,v_nom_papa,v_nom_maman,
      v_actor_id,v_actor_name,true,false,
      to_char(timezone('Africa/Kinshasa',now()),'YYYY-MM-DD"T"HH24:MI:SS'),
      v_lieu_naissance,v_num_inscription,false,NULL,NULL,NULL,
      v_sexe,v_ecole_provenance,v_tutelle_principale
    )
    RETURNING * INTO v_saved;

    v_fee_count := private.ensure_student_fee_obligations(v_sid,v_school_year,v_actor_id);
    SELECT EXISTS(
      SELECT 1 FROM public.fee_types ft
      WHERE COALESCE(ft.active,true) AND COALESCE(ft.montant_defaut,0)>0
    ) INTO v_fee_configured;

    PERFORM private.write_audit_event(
      v_actor_id,v_actor_name,'student_created',
      jsonb_build_object(
        'student_id',v_sid,
        'class_id',v_cid,
        'has_primary_parent',v_pid IS NOT NULL,
        'fee_obligations_created',v_fee_count,
        'school_year',v_school_year
      ),
      v_sid
    );

    RETURN jsonb_strip_nulls(jsonb_build_object(
      'ok',true,
      'code','STUDENT_CREATED',
      'student',to_jsonb(v_saved),
      'fee_obligations_created',v_fee_count,
      'warning',CASE WHEN NOT v_fee_configured THEN 'FEES_NOT_CONFIGURED' ELSE NULL END
    ));
  END IF;

  -- Modification : aucune modification des numéros, parent principal, photo ou états sensibles.
  UPDATE public.students s
  SET name=v_name,
      cid=v_cid,
      dob=v_dob,
      adresse=v_adresse,
      nom_papa=v_nom_papa,
      nom_maman=v_nom_maman,
      lieu_naissance=v_lieu_naissance,
      sexe=v_sexe,
      ecole_provenance=v_ecole_provenance,
      tutelle_principale=v_tutelle_principale
  WHERE s.id=v_existing.id
  RETURNING * INTO v_saved;

  PERFORM private.write_audit_event(
    v_actor_id,v_actor_name,'student_updated',
    jsonb_build_object('student_id',v_saved.id,'class_id',v_saved.cid),
    v_saved.id
  );

  RETURN jsonb_build_object(
    'ok',true,
    'code','STUDENT_UPDATED',
    'student',to_jsonb(v_saved)
  );

EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('ok',false,'code','STUDENT_NUMBER_CONFLICT');
  WHEN foreign_key_violation THEN
    RETURN jsonb_build_object('ok',false,'code','REFERENCE_NOT_FOUND');
  WHEN invalid_text_representation THEN
    RETURN jsonb_build_object('ok',false,'code','VALIDATION_ERROR');
END;
$$;

REVOKE ALL ON FUNCTION public.save_student_profile(jsonb) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.save_student_profile(jsonb) TO authenticated,service_role;

-- --------------------------------------------------------------------------
-- 6. Liaison photo permanente
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_student_photo_file(
  p_sid text,
  p_file_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_role text := private.current_app_role();
  v_uid text := private.current_app_user_id();
  v_name text;
  v_file public.school_files%rowtype;
  v_student public.students%rowtype;
BEGIN
  IF v_role NOT IN ('direction','direction2') OR v_uid IS NULL THEN
    RETURN jsonb_build_object('ok',false,'code','FORBIDDEN');
  END IF;

  SELECT u.name INTO v_name
  FROM public.users u
  WHERE u.id=v_uid AND u.status='active';
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); END IF;

  SELECT * INTO v_student
  FROM public.students s
  WHERE s.id=p_sid
  FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','STUDENT_NOT_FOUND'); END IF;
  IF COALESCE(v_student.archived,false) THEN RETURN jsonb_build_object('ok',false,'code','STUDENT_ARCHIVED'); END IF;

  SELECT * INTO v_file
  FROM public.school_files f
  WHERE f.id=p_file_id
    AND f.archived_at IS NULL
    AND f.deleted_at IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'code','FILE_NOT_FOUND'); END IF;

  IF v_file.owner_type<>'student' OR v_file.owner_id<>p_sid THEN
    RETURN jsonb_build_object('ok',false,'code','FILE_OWNER_MISMATCH');
  END IF;
  IF v_file.category<>'photo' OR v_file.mime_type NOT IN ('image/jpeg','image/png','image/webp') THEN
    RETURN jsonb_build_object('ok',false,'code','FILE_CATEGORY_INVALID');
  END IF;

  UPDATE public.students
  SET photo_file_id=p_file_id,
      photo=NULL
  WHERE id=p_sid
  RETURNING * INTO v_student;

  PERFORM private.write_audit_event(
    v_uid,v_name,'student_photo_linked',
    jsonb_build_object('student_id',p_sid,'file_id',p_file_id),
    p_sid
  );

  RETURN jsonb_build_object(
    'ok',true,
    'code','STUDENT_PHOTO_LINKED',
    'student',to_jsonb(v_student),
    'photo_file_id',p_file_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.set_student_photo_file(text,uuid) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.set_student_photo_file(text,uuid) TO authenticated,service_role;

ROLLBACK;

-- Le ROLLBACK est volontaire. Cette proposition doit d'abord converger avec
-- le frontend Claude, puis être testée sur une base jetable avant toute
-- migration réelle.
