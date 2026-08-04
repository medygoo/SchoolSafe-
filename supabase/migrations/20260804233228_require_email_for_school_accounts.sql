-- SchoolSafe: every application account must have one recoverable e-mail address.

update public.users
set email = lower(btrim(email))
where email is not null
  and email is distinct from lower(btrim(email));

alter table public.users
  alter column email set not null;

alter table public.users
  add constraint users_email_normalized_check
  check (
    email = lower(btrim(email))
    and length(email) <= 320
    and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  );

alter table public.users
  add constraint users_email_key unique (email);

-- Public pre-registration must also carry the future Parent account e-mail.
-- This CHECK, rather than a nullable convention, also protects direct writes.
alter table public.preinscriptions
  add constraint preinscriptions_email_required_check
  check (
    email is not null
    and email = lower(btrim(email))
    and length(email) <= 320
    and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  );

create or replace function public.save_school_user_profile(p_user jsonb)
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare
  v_actor_id text := private.current_app_user_id();
  v_actor_role text := private.current_app_role();
  v_id text := btrim(coalesce(p_user->>'id', ''));
  v_exists boolean;
  v_current public.users%rowtype;
  v_saved public.users%rowtype;
  v_name text;
  v_role text;
  v_current_role_normalized text;
  v_initials text;
  v_phone text;
  v_photo_url text;
  v_email text;
  v_status text;
begin
  if p_user is null or jsonb_typeof(p_user) <> 'object' then
    return jsonb_build_object('ok', false, 'code', 'INVALID_PAYLOAD');
  end if;

  if v_actor_role <> 'direction' then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN');
  end if;

  if v_id = '' or length(v_id) > 160 then
    return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'id');
  end if;

  select exists(select 1 from public.users where id = v_id) into v_exists;
  if v_exists then
    select * into v_current from public.users where id = v_id;
  end if;

  v_name := case
    when p_user ? 'name' then nullif(btrim(coalesce(p_user->>'name', '')), '')
    when v_exists then v_current.name
    else null
  end;

  v_role := case
    when p_user ? 'role' then nullif(btrim(coalesce(p_user->>'role', '')), '')
    when v_exists then v_current.role
    else null
  end;

  v_role := case v_role
    when 'direction_pedagogique' then 'direction2'
    when 'caisse' then 'direction3'
    when 'enseignant_maternelle' then 'enseignant'
    else v_role
  end;

  v_initials := case
    when p_user ? 'initials' then nullif(btrim(coalesce(p_user->>'initials', '')), '')
    when v_exists then v_current.initials
    else null
  end;

  v_phone := case
    when p_user ? 'phone' then nullif(btrim(coalesce(p_user->>'phone', '')), '')
    when v_exists then v_current.phone
    else null
  end;

  v_photo_url := case
    when p_user ? 'photo_url' then nullif(btrim(coalesce(p_user->>'photo_url', '')), '')
    when v_exists then v_current.photo_url
    else null
  end;

  v_email := case
    when p_user ? 'email' then nullif(lower(btrim(coalesce(p_user->>'email', ''))), '')
    when v_exists then v_current.email
    else null
  end;

  v_status := case
    when p_user ? 'status' then nullif(btrim(coalesce(p_user->>'status', '')), '')
    when v_exists then v_current.status
    else 'active'
  end;

  if v_status = 'disabled' then
    v_status := 'inactive';
  end if;

  if v_name is null or length(v_name) > 200 then
    return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'name');
  end if;

  if v_role not in ('direction', 'direction2', 'direction3', 'enseignant', 'parent', 'gardien') then
    return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'role');
  end if;

  if v_status not in ('active', 'inactive', 'suspended') then
    return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'status');
  end if;

  if length(coalesce(v_initials, '')) > 20 then
    return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'initials');
  end if;
  if length(coalesce(v_phone, '')) > 50 then
    return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'phone');
  end if;
  if length(coalesce(v_photo_url, '')) > 2048 then
    return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'photo_url');
  end if;
  if v_photo_url is not null and lower(v_photo_url) like 'data:%' then
    return jsonb_build_object('ok', false, 'code', 'PHOTO_MUST_BE_FILE_REFERENCE');
  end if;

  if v_email is null
     or length(v_email) > 320
     or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'email');
  end if;

  if exists(
    select 1 from public.users
    where id <> v_id
      and email = v_email
  ) then
    return jsonb_build_object('ok', false, 'code', 'EMAIL_IN_USE');
  end if;

  if v_exists and v_current.auth_user_id is not null then
    if v_current.email <> v_email then
      return jsonb_build_object('ok', false, 'code', 'AUTH_EMAIL_CHANGE_REQUIRED');
    end if;

    v_current_role_normalized := case v_current.role
      when 'direction_pedagogique' then 'direction2'
      when 'caisse' then 'direction3'
      when 'enseignant_maternelle' then 'enseignant'
      else v_current.role
    end;

    if v_current_role_normalized <> v_role then
      return jsonb_build_object('ok', false, 'code', 'AUTH_ROLE_CHANGE_REQUIRED');
    end if;
  end if;

  if v_id = v_actor_id and (v_role <> 'direction' or v_status <> 'active') then
    return jsonb_build_object('ok', false, 'code', 'CANNOT_DISABLE_CURRENT_DIRECTION');
  end if;

  if v_exists then
    update public.users
    set name = v_name,
        role = v_role,
        initials = v_initials,
        phone = v_phone,
        photo_url = v_photo_url,
        email = v_email,
        status = v_status,
        updated_at = now()
    where id = v_id
    returning * into v_saved;
  else
    insert into public.users (
      id, name, role, initials, phone, photo_url, email, status
    ) values (
      v_id, v_name, v_role, v_initials, v_phone, v_photo_url, v_email, v_status
    )
    returning * into v_saved;
  end if;

  if v_saved.auth_user_id is not null then
    update public.profiles
    set email = v_saved.email,
        full_name = v_saved.name,
        status = v_saved.status,
        updated_at = now()
    where id = v_saved.auth_user_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'code', case when v_exists then 'USER_UPDATED' else 'USER_CREATED' end,
    'requires_invitation', (v_saved.auth_user_id is null),
    'user', to_jsonb(v_saved)
  );
exception
  when unique_violation then
    return jsonb_build_object('ok', false, 'code', 'DUPLICATE_USER');
  when foreign_key_violation then
    return jsonb_build_object('ok', false, 'code', 'REFERENCE_NOT_FOUND');
  when check_violation or not_null_violation then
    return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR');
end;
$function$;

comment on column public.users.email is
  'Mandatory normalized login and account-recovery e-mail for every SchoolSafe profile.';

comment on constraint preinscriptions_email_required_check on public.preinscriptions is
  'A pre-registration must include the e-mail used for the future Parent account and password recovery.';