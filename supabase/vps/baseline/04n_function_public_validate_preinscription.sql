-- SchoolSafe VPS baseline - 04n final pre-registration validation

BEGIN;

CREATE OR REPLACE FUNCTION public.validate_preinscription_email(p_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_id text := private.current_app_user_id(); v_actor_role text := private.current_app_role(); v_actor_name text;
  v_request public.preinscriptions%rowtype; v_class_id text; v_class_count integer; v_parent_id text; v_parent_count integer;
  v_parent_reused boolean := false; v_parent_name text; v_phone_norm text; v_year text; v_counter bigint;
  v_student_id text; v_mat text; v_num_inscription text; v_authorized_count integer := 0; v_obligation_count integer := 0;
  v_item jsonb; v_medical_notes text;
begin
  if auth.uid() is null or v_actor_role <> 'direction' then return jsonb_build_object('ok', false, 'code', 'FORBIDDEN'); end if;
  select u.name into v_actor_name from public.users u where u.id = v_actor_id and u.status = 'active' and u.role = 'direction' limit 1;
  if not found then return jsonb_build_object('ok', false, 'code', 'ACTOR_NOT_FOUND'); end if;
  select * into v_request from public.preinscriptions p where p.id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'code', 'PREINSCRIPTION_NOT_FOUND'); end if;
  if v_request.statut = 'validee' then return jsonb_build_object('ok', true, 'code', 'ALREADY_VALIDATED', 'student_id', v_request.student_id, 'parent_id', v_request.parent_id); end if;
  if v_request.statut <> 'nouvelle' then return jsonb_build_object('ok', false, 'code', 'PREINSCRIPTION_NOT_OPEN'); end if;
  if v_request.expire_le < (timezone('Africa/Kinshasa', now()))::date then return jsonb_build_object('ok', false, 'code', 'PREINSCRIPTION_EXPIRED'); end if;

  select count(*), min(c.id) into v_class_count, v_class_id from public.classes c
  where c.id = v_request.classe or lower(btrim(coalesce(c.name, ''))) = lower(btrim(v_request.classe));
  if v_class_count = 0 then return jsonb_build_object('ok', false, 'code', 'CLASS_NOT_FOUND', 'requested_class', v_request.classe);
  elsif v_class_count > 1 then return jsonb_build_object('ok', false, 'code', 'CLASS_AMBIGUOUS', 'requested_class', v_request.classe); end if;

  if exists (select 1 from public.students s where lower(btrim(coalesce(s.name, ''))) = lower(btrim(v_request.nom)) and nullif(btrim(coalesce(s.dob, '')), '') = to_char(v_request.dob, 'YYYY-MM-DD') and not coalesce(s.archived, false)) then
    return jsonb_build_object('ok', false, 'code', 'STUDENT_ALREADY_EXISTS');
  end if;

  v_phone_norm := private.normalize_phone_e164(v_request.telephone);
  if v_phone_norm is null then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'telephone'); end if;
  select count(*), min(u.id) into v_parent_count, v_parent_id from public.users u where u.role = 'parent' and u.status = 'active' and u.phone = v_phone_norm;
  if v_parent_count > 1 then return jsonb_build_object('ok', false, 'code', 'PARENT_PHONE_AMBIGUOUS'); end if;
  if v_parent_count = 1 then
    v_parent_reused := true;
  else
    if v_request.email is not null and exists (select 1 from public.users u where u.email is not null and lower(btrim(u.email)) = lower(btrim(v_request.email))) then
      return jsonb_build_object('ok', false, 'code', 'PARENT_EMAIL_IN_USE');
    end if;
    v_parent_id := 'parent_' || replace(gen_random_uuid()::text, '-', '');
    v_parent_name := nullif(btrim(split_part(v_request.tutelle, ',', 1)), '');
    v_parent_name := coalesce(v_parent_name, v_request.nom_papa, v_request.nom_maman, 'Tuteur de ' || v_request.nom);
    insert into public.users (id, name, role, phone, email, status, access_channel)
    values (v_parent_id, v_parent_name, 'parent', v_phone_norm, v_request.email, 'active', case when v_request.email is null then 'phone_whatsapp' else 'email' end);
  end if;

  select nullif(btrim(s.year), '') into v_year from public.settings s where s.id = 'main' limit 1;
  if v_year is null then
    if extract(month from timezone('Africa/Kinshasa', now())) >= 9 then
      v_year := extract(year from timezone('Africa/Kinshasa', now()))::integer::text || '-' || (extract(year from timezone('Africa/Kinshasa', now()))::integer + 1)::text;
    else
      v_year := (extract(year from timezone('Africa/Kinshasa', now()))::integer - 1)::text || '-' || extract(year from timezone('Africa/Kinshasa', now()))::integer::text;
    end if;
  end if;

  insert into private.school_counters (counter_key, counter_value, updated_at)
  values ('student_mat:' || v_year, 1, now())
  on conflict (counter_key) do update set counter_value = private.school_counters.counter_value + 1, updated_at = now()
  returning counter_value into v_counter;

  v_student_id := 'student_' || replace(gen_random_uuid()::text, '-', '');
  v_mat := 'LS-' || v_year || '-' || lpad(v_counter::text, 6, '0');
  v_num_inscription := 'INS-' || v_year || '-' || lpad(v_counter::text, 6, '0');

  insert into public.students (
    id, name, mat, cid, pid, dob, photo, adresse, nom_papa, nom_maman, created_by, created_by_name,
    access_parent, archived, created_at, lieu_naissance, num_inscription, may_leave_alone, sexe, ecole_provenance, tutelle_principale
  ) values (
    v_student_id, v_request.nom, v_mat, v_class_id, v_parent_id, to_char(v_request.dob, 'YYYY-MM-DD'), null,
    v_request.adresse, v_request.nom_papa, v_request.nom_maman, v_actor_id, v_actor_name, true, false,
    to_char(timezone('Africa/Kinshasa', now()), 'YYYY-MM-DD"T"HH24:MI:SS'), v_request.lieu_naissance,
    v_num_inscription, false, v_request.sexe, v_request.ecole_provenance, v_request.tutelle
  );

  if v_request.blood_group is not null or v_request.medical_notes is not null or v_request.urgence is not null then
    v_medical_notes := concat_ws(E'\n', nullif(v_request.medical_notes, ''), case when v_request.urgence is not null then 'À prévenir en urgence : ' || v_request.urgence else null end);
    insert into public.medical (id, sid, blood_type, medical_notes, updated)
    values ('medical_' || replace(gen_random_uuid()::text, '-', ''), v_student_id, v_request.blood_group,
      nullif(v_medical_notes, ''), to_char(timezone('Africa/Kinshasa', now()), 'YYYY-MM-DD"T"HH24:MI:SS'));
  end if;

  for v_item in select value from jsonb_array_elements(coalesce(v_request.autorisees, '[]'::jsonb)) loop
    insert into public.aps (id, sid, name, relation, photo, active, phone, approval_status, proposed_by, proposed_at, approved_by, approved_at, rejection_reason, valid_until)
    values ('aps_' || replace(gen_random_uuid()::text, '-', ''), v_student_id, btrim(v_item->>'nom'), btrim(v_item->>'relation'), null, false,
      private.normalize_phone_e164(v_item->>'telephone'), 'pending', v_parent_id, now(), null, null, null, null);
    v_authorized_count := v_authorized_count + 1;
  end loop;

  insert into public.student_fee_obligations (sid, fee_type_id, school_year, label, installment_no, amount_due, currency, due_date, active, created_by)
  select v_student_id, ft.id, v_year, coalesce(nullif(btrim(ft.label), ''), ft.id),
    case upper(coalesce(ft.trimestre, '')) when 'T1' then 1 when 'T2' then 2 when 'T3' then 3 else 1 end,
    ft.montant_defaut, 'USD', null, true, v_actor_id
  from public.fee_types ft
  where coalesce(ft.active, true) and coalesce(ft.montant_defaut, 0) > 0
  on conflict (sid, fee_type_id, school_year, installment_no) do nothing;
  get diagnostics v_obligation_count = row_count;

  update public.preinscriptions
  set statut = 'validee', traite_par = v_actor_id, traite_par_nom = v_actor_name, traite_le = now(),
      student_id = v_student_id, parent_id = v_parent_id, motif_refus = null
  where id = p_id;

  perform private.write_audit_event(v_actor_id, v_actor_name, 'preinscription_validee',
    jsonb_build_object('preinscription_id', p_id, 'student_id', v_student_id, 'parent_id', v_parent_id,
      'parent_reused', v_parent_reused, 'matricule', v_mat, 'authorized_pending', v_authorized_count,
      'obligations_created', v_obligation_count), v_student_id);

  return jsonb_build_object('ok', true, 'code', 'PREINSCRIPTION_VALIDATED', 'student_id', v_student_id,
    'parent_id', v_parent_id, 'parent_reused', v_parent_reused, 'matricule', v_mat,
    'num_inscription', v_num_inscription, 'authorized_pending', v_authorized_count,
    'obligations_created', v_obligation_count,
    'requires_phone_provisioning', (not v_parent_reused and v_request.email is null),
    'warning', case when v_obligation_count = 0 then 'FEES_NOT_CONFIGURED' else null end);
exception
  when unique_violation then return jsonb_build_object('ok', false, 'code', 'DUPLICATE_RECORD');
  when foreign_key_violation then return jsonb_build_object('ok', false, 'code', 'REFERENCE_NOT_FOUND');
  when check_violation then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR');
end;
$function$;

COMMIT;
