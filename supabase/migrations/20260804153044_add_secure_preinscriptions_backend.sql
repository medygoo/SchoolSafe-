-- P0-6 — préinscriptions publiques, validation atomique Direction 1.
-- Version appliquée dans Supabase : 20260804153044.

create table if not exists private.school_counters (
  counter_key text primary key,
  counter_value bigint not null default 0 check (counter_value >= 0),
  updated_at timestamptz not null default now()
);
revoke all on table private.school_counters from public, anon, authenticated;

alter table public.students
  add column if not exists sexe text,
  add column if not exists ecole_provenance text,
  add column if not exists tutelle_principale text;

create table if not exists public.preinscriptions (
  id text primary key default ('pre_' || replace(gen_random_uuid()::text, '-', '')),
  statut text not null default 'nouvelle' check (statut in ('nouvelle', 'validee', 'refusee')),
  created_at timestamptz not null default now(),
  expire_le date not null default ((timezone('Africa/Kinshasa', now()))::date + 30),
  nom text not null,
  sexe text not null,
  dob date not null,
  lieu_naissance text,
  classe text not null,
  ecole_provenance text,
  nom_papa text,
  nom_maman text,
  telephone text not null,
  telephone2 text,
  adresse text,
  email text,
  blood_group text,
  urgence text,
  medical_notes text,
  tutelle text not null,
  autorisees jsonb not null default '[]'::jsonb,
  motif_refus text,
  traite_par text references public.users(id) on delete set null,
  traite_par_nom text,
  traite_le timestamptz,
  student_id text references public.students(id) on delete set null,
  parent_id text references public.users(id) on delete set null,
  constraint preinscriptions_nom_check check (length(btrim(nom)) between 2 and 200),
  constraint preinscriptions_sexe_check check (length(btrim(sexe)) between 1 and 30),
  constraint preinscriptions_classe_check check (length(btrim(classe)) between 1 and 160),
  constraint preinscriptions_telephone_check check (length(regexp_replace(telephone, '[^0-9]+', '', 'g')) >= 8),
  constraint preinscriptions_tutelle_check check (length(btrim(tutelle)) between 3 and 300),
  constraint preinscriptions_autorisees_check check (jsonb_typeof(autorisees) = 'array' and jsonb_array_length(autorisees) <= 3),
  constraint preinscriptions_email_check check (email is null or (length(email) <= 320 and email ~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$')),
  constraint preinscriptions_refusal_check check (statut <> 'refusee' or length(btrim(coalesce(motif_refus, ''))) >= 3)
);

create index if not exists preinscriptions_status_created_idx on public.preinscriptions (statut, created_at desc);
create index if not exists preinscriptions_expiry_idx on public.preinscriptions (expire_le) where statut = 'nouvelle';
create index if not exists preinscriptions_identity_idx on public.preinscriptions (lower(btrim(nom)), dob);
create index if not exists preinscriptions_phone_idx on public.preinscriptions ((right(regexp_replace(telephone, '[^0-9]+', '', 'g'), 8)));

alter table public.preinscriptions enable row level security;
revoke all on table public.preinscriptions from public, anon, authenticated;
grant select on table public.preinscriptions to authenticated;
drop policy if exists preinscriptions_direction_read on public.preinscriptions;
create policy preinscriptions_direction_read on public.preinscriptions
  for select to authenticated
  using ((select private.current_app_role()) = 'direction');

create or replace function private.normalize_school_phone(p_phone text)
returns text language sql immutable security invoker set search_path = ''
as $$ select nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9]+', '', 'g'), ''); $$;
revoke all on function private.normalize_school_phone(text) from public, anon, authenticated;

-- Les photos se prennent à l'école. Une personne pending peut donc exister sans
-- photo, mais une personne active doit obligatoirement être approved et avoir
-- une photo.
alter table public.aps drop constraint if exists aps_required_identity_check;
alter table public.aps add constraint aps_required_identity_check check (
  length(btrim(coalesce(name, ''))) >= 3
  and length(btrim(coalesce(phone, ''))) >= 6
  and (approval_status = 'pending' or length(btrim(coalesce(photo, ''))) > 0)
);
alter table public.aps drop constraint if exists aps_active_requires_approval_check;
alter table public.aps add constraint aps_active_requires_approval_check check (
  not coalesce(active, false)
  or (approval_status = 'approved' and length(btrim(coalesce(photo, ''))) > 0)
);

create or replace function public.submit_preinscription(p_request jsonb)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_nom text; v_sexe text; v_dob date; v_lieu_naissance text; v_classe text;
  v_ecole_provenance text; v_nom_papa text; v_nom_maman text; v_telephone text;
  v_telephone_norm text; v_telephone2 text; v_adresse text; v_email text;
  v_blood_group text; v_urgence text; v_medical_notes text; v_tutelle text;
  v_autorisees jsonb := '[]'::jsonb; v_item jsonb; v_name text; v_relation text;
  v_phone text; v_phone_norm text; v_i integer; v_count integer; v_existing_id text;
  v_saved public.preinscriptions%rowtype;
begin
  if p_request is null or jsonb_typeof(p_request) <> 'object' then
    return jsonb_build_object('ok', false, 'code', 'INVALID_PAYLOAD');
  end if;

  if length(btrim(coalesce(p_request->>'website', ''))) > 0
     or length(btrim(coalesce(p_request->>'company', ''))) > 0
     or length(btrim(coalesce(p_request->>'url', ''))) > 0 then
    return jsonb_build_object('ok', false, 'code', 'INVALID_SUBMISSION');
  end if;

  v_nom := nullif(btrim(coalesce(p_request->>'nom', '')), '');
  v_sexe := nullif(btrim(coalesce(p_request->>'sexe', '')), '');
  v_lieu_naissance := nullif(btrim(coalesce(p_request->>'lieu_naissance', '')), '');
  v_classe := nullif(btrim(coalesce(p_request->>'classe', '')), '');
  v_ecole_provenance := nullif(btrim(coalesce(p_request->>'ecole_provenance', '')), '');
  v_nom_papa := nullif(btrim(coalesce(p_request->>'nom_papa', '')), '');
  v_nom_maman := nullif(btrim(coalesce(p_request->>'nom_maman', '')), '');
  v_telephone := nullif(btrim(coalesce(p_request->>'telephone', '')), '');
  v_telephone2 := nullif(btrim(coalesce(p_request->>'telephone2', '')), '');
  v_adresse := nullif(btrim(coalesce(p_request->>'adresse', '')), '');
  v_email := nullif(lower(btrim(coalesce(p_request->>'email', ''))), '');
  v_blood_group := nullif(btrim(coalesce(p_request->>'blood_group', '')), '');
  v_urgence := nullif(btrim(coalesce(p_request->>'urgence', '')), '');
  v_medical_notes := nullif(btrim(coalesce(p_request->>'medical_notes', '')), '');
  v_tutelle := nullif(btrim(coalesce(p_request->>'tutelle', '')), '');

  if v_nom is null or length(v_nom) > 200 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'nom'); end if;
  if v_sexe is null or length(v_sexe) > 30 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'sexe'); end if;
  if v_classe is null or length(v_classe) > 160 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'classe'); end if;
  if v_telephone is null then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'telephone'); end if;
  v_telephone_norm := private.normalize_school_phone(v_telephone);
  if v_telephone_norm is null or length(v_telephone_norm) < 8 or length(v_telephone_norm) > 20 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'telephone'); end if;
  if v_tutelle is null or length(v_tutelle) > 300 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'tutelle'); end if;

  begin
    v_dob := (p_request->>'dob')::date;
  exception when invalid_datetime_format or datetime_field_overflow then
    return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'dob');
  end;
  if v_dob is null or v_dob > (timezone('Africa/Kinshasa', now()))::date then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'dob'); end if;

  if length(coalesce(v_lieu_naissance, '')) > 200
     or length(coalesce(v_ecole_provenance, '')) > 200
     or length(coalesce(v_nom_papa, '')) > 200
     or length(coalesce(v_nom_maman, '')) > 200
     or length(coalesce(v_telephone2, '')) > 50
     or length(coalesce(v_adresse, '')) > 500
     or length(coalesce(v_blood_group, '')) > 20
     or length(coalesce(v_urgence, '')) > 300
     or length(coalesce(v_medical_notes, '')) > 2000 then
    return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR');
  end if;
  if v_email is not null and (length(v_email) > 320 or v_email !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') then
    return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'email');
  end if;

  if p_request ? 'autorisees' then
    if jsonb_typeof(p_request->'autorisees') <> 'array' or jsonb_array_length(p_request->'autorisees') > 3 then
      return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'autorisees');
    end if;
    for v_item in select value from jsonb_array_elements(p_request->'autorisees') loop
      if jsonb_typeof(v_item) <> 'object' then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'autorisees'); end if;
      v_name := nullif(btrim(coalesce(v_item->>'nom', '')), '');
      v_relation := nullif(btrim(coalesce(v_item->>'relation', '')), '');
      v_phone := nullif(btrim(coalesce(v_item->>'telephone', '')), '');
      if v_name is null and v_relation is null and v_phone is null then continue; end if;
      v_phone_norm := private.normalize_school_phone(v_phone);
      if v_name is null or length(v_name) > 200 or v_relation is null or length(v_relation) > 100 or v_phone_norm is null or length(v_phone_norm) < 8 or length(v_phone_norm) > 20 then
        return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'autorisees');
      end if;
      v_autorisees := v_autorisees || jsonb_build_array(jsonb_build_object('nom', v_name, 'relation', v_relation, 'telephone', v_phone));
    end loop;
  else
    for v_i in 1..3 loop
      v_name := nullif(btrim(coalesce(p_request->>('a' || v_i || '_nom'), '')), '');
      v_relation := nullif(btrim(coalesce(p_request->>('a' || v_i || '_relation'), '')), '');
      v_phone := nullif(btrim(coalesce(p_request->>('a' || v_i || '_telephone'), '')), '');
      if v_name is null and v_relation is null and v_phone is null then continue; end if;
      v_phone_norm := private.normalize_school_phone(v_phone);
      if v_name is null or length(v_name) > 200 or v_relation is null or length(v_relation) > 100 or v_phone_norm is null or length(v_phone_norm) < 8 or length(v_phone_norm) > 20 then
        return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'a' || v_i);
      end if;
      v_autorisees := v_autorisees || jsonb_build_array(jsonb_build_object('nom', v_name, 'relation', v_relation, 'telephone', v_phone));
    end loop;
  end if;

  select p.id into v_existing_id
  from public.preinscriptions p
  where p.created_at >= now() - interval '24 hours'
    and lower(btrim(p.nom)) = lower(v_nom)
    and p.dob = v_dob
    and right(private.normalize_school_phone(p.telephone), 8) = right(v_telephone_norm, 8)
  order by p.created_at desc limit 1;
  if found then return jsonb_build_object('ok', true, 'code', 'ALREADY_SUBMITTED', 'request_id', v_existing_id); end if;

  select count(*) into v_count
  from public.preinscriptions p
  where p.created_at >= now() - interval '24 hours'
    and right(private.normalize_school_phone(p.telephone), 8) = right(v_telephone_norm, 8);
  if v_count >= 3 then return jsonb_build_object('ok', false, 'code', 'RATE_LIMITED'); end if;

  insert into public.preinscriptions (
    nom, sexe, dob, lieu_naissance, classe, ecole_provenance,
    nom_papa, nom_maman, telephone, telephone2, adresse, email,
    blood_group, urgence, medical_notes, tutelle, autorisees
  ) values (
    v_nom, v_sexe, v_dob, v_lieu_naissance, v_classe, v_ecole_provenance,
    v_nom_papa, v_nom_maman, v_telephone, v_telephone2, v_adresse, v_email,
    v_blood_group, v_urgence, v_medical_notes, v_tutelle, v_autorisees
  ) returning * into v_saved;

  return jsonb_build_object(
    'ok', true, 'code', 'PREINSCRIPTION_CREATED', 'request_id', v_saved.id,
    'created_at', v_saved.created_at, 'expire_le', v_saved.expire_le
  );
exception when check_violation then
  return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR');
end;
$$;
revoke all on function public.submit_preinscription(jsonb) from public;
grant execute on function public.submit_preinscription(jsonb) to anon, authenticated;

create or replace function public.validate_preinscription(p_id text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_actor_id text := private.current_app_user_id();
  v_actor_role text := private.current_app_role();
  v_actor_name text; v_request public.preinscriptions%rowtype;
  v_class_id text; v_class_count integer; v_parent_id text; v_parent_count integer;
  v_parent_reused boolean := false; v_parent_name text; v_phone_norm text;
  v_year text; v_counter bigint; v_student_id text; v_mat text; v_num_inscription text;
  v_authorized_count integer := 0; v_obligation_count integer := 0;
  v_item jsonb; v_medical_notes text;
begin
  if auth.uid() is null or v_actor_role <> 'direction' then return jsonb_build_object('ok', false, 'code', 'FORBIDDEN'); end if;
  select u.name into v_actor_name from public.users u
  where u.id = v_actor_id and u.status = 'active' and u.role = 'direction' limit 1;
  if not found then return jsonb_build_object('ok', false, 'code', 'ACTOR_NOT_FOUND'); end if;

  select * into v_request from public.preinscriptions p where p.id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'code', 'PREINSCRIPTION_NOT_FOUND'); end if;
  if v_request.statut = 'validee' then
    return jsonb_build_object('ok', true, 'code', 'ALREADY_VALIDATED', 'student_id', v_request.student_id, 'parent_id', v_request.parent_id);
  end if;
  if v_request.statut <> 'nouvelle' then return jsonb_build_object('ok', false, 'code', 'PREINSCRIPTION_NOT_OPEN'); end if;
  if v_request.expire_le < (timezone('Africa/Kinshasa', now()))::date then return jsonb_build_object('ok', false, 'code', 'PREINSCRIPTION_EXPIRED'); end if;

  select count(*), min(c.id) into v_class_count, v_class_id
  from public.classes c
  where c.id = v_request.classe or lower(btrim(coalesce(c.name, ''))) = lower(btrim(v_request.classe));
  if v_class_count = 0 then return jsonb_build_object('ok', false, 'code', 'CLASS_NOT_FOUND', 'requested_class', v_request.classe); end if;
  if v_class_count > 1 then return jsonb_build_object('ok', false, 'code', 'CLASS_AMBIGUOUS', 'requested_class', v_request.classe); end if;

  if exists (
    select 1 from public.students s
    where lower(btrim(coalesce(s.name, ''))) = lower(btrim(v_request.nom))
      and nullif(btrim(coalesce(s.dob, '')), '') = to_char(v_request.dob, 'YYYY-MM-DD')
      and not coalesce(s.archived, false)
  ) then return jsonb_build_object('ok', false, 'code', 'STUDENT_ALREADY_EXISTS'); end if;

  v_phone_norm := private.normalize_school_phone(v_request.telephone);
  select count(*), min(u.id) into v_parent_count, v_parent_id
  from public.users u
  where u.role = 'parent' and u.status = 'active'
    and right(private.normalize_school_phone(u.phone), 8) = right(v_phone_norm, 8);
  if v_parent_count > 1 then return jsonb_build_object('ok', false, 'code', 'PARENT_PHONE_AMBIGUOUS'); end if;

  if v_parent_count = 1 then
    v_parent_reused := true;
  else
    if v_request.email is not null and exists (
      select 1 from public.users u
      where u.email is not null and lower(btrim(u.email)) = lower(btrim(v_request.email))
    ) then return jsonb_build_object('ok', false, 'code', 'PARENT_EMAIL_IN_USE'); end if;

    v_parent_id := 'parent_' || replace(gen_random_uuid()::text, '-', '');
    v_parent_name := nullif(btrim(split_part(v_request.tutelle, ',', 1)), '');
    v_parent_name := coalesce(v_parent_name, v_request.nom_papa, v_request.nom_maman, 'Tuteur de ' || v_request.nom);
    insert into public.users (id, name, role, phone, email, status)
    values (v_parent_id, v_parent_name, 'parent', v_request.telephone, v_request.email, 'active');
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
  on conflict (counter_key) do update
    set counter_value = private.school_counters.counter_value + 1, updated_at = now()
  returning counter_value into v_counter;

  v_student_id := 'student_' || replace(gen_random_uuid()::text, '-', '');
  v_mat := 'LS-' || v_year || '-' || lpad(v_counter::text, 6, '0');
  v_num_inscription := 'INS-' || v_year || '-' || lpad(v_counter::text, 6, '0');

  insert into public.students (
    id, name, mat, cid, pid, dob, photo, adresse, nom_papa, nom_maman,
    created_by, created_by_name, access_parent, archived, created_at,
    lieu_naissance, num_inscription, may_leave_alone, sexe,
    ecole_provenance, tutelle_principale
  ) values (
    v_student_id, v_request.nom, v_mat, v_class_id, v_parent_id,
    to_char(v_request.dob, 'YYYY-MM-DD'), null, v_request.adresse,
    v_request.nom_papa, v_request.nom_maman, v_actor_id, v_actor_name,
    true, false, to_char(timezone('Africa/Kinshasa', now()), 'YYYY-MM-DD"T"HH24:MI:SS'),
    v_request.lieu_naissance, v_num_inscription, false, v_request.sexe,
    v_request.ecole_provenance, v_request.tutelle
  );

  if v_request.blood_group is not null or v_request.medical_notes is not null or v_request.urgence is not null then
    v_medical_notes := concat_ws(E'\n', nullif(v_request.medical_notes, ''),
      case when v_request.urgence is not null then 'À prévenir en urgence : ' || v_request.urgence else null end);
    insert into public.medical (id, sid, blood_type, medical_notes, updated)
    values ('medical_' || replace(gen_random_uuid()::text, '-', ''), v_student_id,
      v_request.blood_group, nullif(v_medical_notes, ''),
      to_char(timezone('Africa/Kinshasa', now()), 'YYYY-MM-DD"T"HH24:MI:SS'));
  end if;

  for v_item in select value from jsonb_array_elements(coalesce(v_request.autorisees, '[]'::jsonb)) loop
    insert into public.aps (
      id, sid, name, relation, photo, active, phone, approval_status,
      proposed_by, proposed_at, approved_by, approved_at, rejection_reason, valid_until
    ) values (
      'aps_' || replace(gen_random_uuid()::text, '-', ''), v_student_id,
      btrim(v_item->>'nom'), btrim(v_item->>'relation'), null, false,
      btrim(v_item->>'telephone'), 'pending', v_parent_id, now(), null, null, null, null
    );
    v_authorized_count := v_authorized_count + 1;
  end loop;

  insert into public.student_fee_obligations (
    sid, fee_type_id, school_year, label, installment_no,
    amount_due, currency, due_date, active, created_by
  )
  select v_student_id, ft.id, v_year, coalesce(nullif(btrim(ft.label), ''), ft.id),
    case upper(coalesce(ft.trimestre, '')) when 'T1' then 1 when 'T2' then 2 when 'T3' then 3 else 1 end,
    ft.montant_defaut, 'USD', null, true, v_actor_id
  from public.fee_types ft
  where coalesce(ft.active, true) and coalesce(ft.montant_defaut, 0) > 0
  on conflict (sid, fee_type_id, school_year, installment_no) do nothing;
  get diagnostics v_obligation_count = row_count;

  update public.preinscriptions
  set statut = 'validee', traite_par = v_actor_id, traite_par_nom = v_actor_name,
      traite_le = now(), student_id = v_student_id, parent_id = v_parent_id,
      motif_refus = null
  where id = p_id;

  perform private.write_audit_event(
    v_actor_id, v_actor_name, 'preinscription_validee',
    jsonb_build_object(
      'preinscription_id', p_id, 'student_id', v_student_id,
      'parent_id', v_parent_id, 'parent_reused', v_parent_reused,
      'matricule', v_mat, 'authorized_pending', v_authorized_count,
      'obligations_created', v_obligation_count
    ), v_student_id
  );

  return jsonb_build_object(
    'ok', true, 'code', 'PREINSCRIPTION_VALIDATED',
    'student_id', v_student_id, 'parent_id', v_parent_id,
    'parent_reused', v_parent_reused, 'matricule', v_mat,
    'num_inscription', v_num_inscription,
    'authorized_pending', v_authorized_count,
    'obligations_created', v_obligation_count,
    'warning', case when v_obligation_count = 0 then 'FEES_NOT_CONFIGURED' else null end
  );
exception
  when unique_violation then return jsonb_build_object('ok', false, 'code', 'DUPLICATE_RECORD');
  when foreign_key_violation then return jsonb_build_object('ok', false, 'code', 'REFERENCE_NOT_FOUND');
  when check_violation then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR');
end;
$$;
revoke all on function public.validate_preinscription(text) from public, anon;
grant execute on function public.validate_preinscription(text) to authenticated;

create or replace function public.refuse_preinscription(p_id text, p_motif text)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_actor_id text := private.current_app_user_id();
  v_actor_role text := private.current_app_role();
  v_actor_name text;
  v_motif text := nullif(btrim(coalesce(p_motif, '')), '');
  v_request public.preinscriptions%rowtype;
begin
  if auth.uid() is null or v_actor_role <> 'direction' then return jsonb_build_object('ok', false, 'code', 'FORBIDDEN'); end if;
  if v_motif is null or length(v_motif) < 3 or length(v_motif) > 300 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'motif'); end if;

  select u.name into v_actor_name from public.users u
  where u.id = v_actor_id and u.status = 'active' and u.role = 'direction' limit 1;
  if not found then return jsonb_build_object('ok', false, 'code', 'ACTOR_NOT_FOUND'); end if;

  select * into v_request from public.preinscriptions p where p.id = p_id for update;
  if not found then return jsonb_build_object('ok', false, 'code', 'PREINSCRIPTION_NOT_FOUND'); end if;
  if v_request.statut = 'refusee' then return jsonb_build_object('ok', true, 'code', 'ALREADY_REFUSED'); end if;
  if v_request.statut <> 'nouvelle' then return jsonb_build_object('ok', false, 'code', 'PREINSCRIPTION_NOT_OPEN'); end if;

  update public.preinscriptions
  set statut = 'refusee', motif_refus = v_motif, traite_par = v_actor_id,
      traite_par_nom = v_actor_name, traite_le = now()
  where id = p_id;

  perform private.write_audit_event(
    v_actor_id, v_actor_name, 'preinscription_refusee',
    jsonb_build_object('preinscription_id', p_id, 'motif', v_motif), p_id
  );
  return jsonb_build_object('ok', true, 'code', 'PREINSCRIPTION_REFUSED', 'request_id', p_id);
end;
$$;
revoke all on function public.refuse_preinscription(text, text) from public, anon;
grant execute on function public.refuse_preinscription(text, text) to authenticated;

comment on table public.preinscriptions is
'Public pre-registration requests. Anonymous callers submit only through submit_preinscription; only Direction 1 can read and process requests.';
comment on function public.submit_preinscription(jsonb) is
'Public write-only pre-registration endpoint with validation, duplicate suppression, honeypot fields and per-phone throttling.';
comment on function public.validate_preinscription(text) is
'Direction 1-only atomic conversion into a parent/tutor account, student, pending authorized people, matricule, medical record and configured fee obligations.';
comment on function public.refuse_preinscription(text, text) is
'Direction 1-only refusal that retains the request, reason, actor and processing time.';
