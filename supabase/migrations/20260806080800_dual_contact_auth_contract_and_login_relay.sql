-- P0-22 — invitation e-mail et accès téléphone vers un auth_user_id unique.
-- Déployé en production sous la migration Supabase dual_contact_auth_contract_and_login_relay.

create or replace function private.current_app_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case u.role
    when 'direction_pedagogique' then 'direction2'
    when 'caisse' then 'direction3'
    else u.role
  end
  from public.users u
  where u.auth_user_id = auth.uid()
    and u.status = 'active'
    and not u.must_change_password
  limit 1
$$;

create or replace function private.current_app_user_id()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select u.id
  from public.users u
  where u.auth_user_id = auth.uid()
    and u.status = 'active'
    and not u.must_change_password
  limit 1
$$;

create or replace function public.prepare_account_invitation(
  p_actor_auth_user_id uuid,
  p_app_user_id text,
  p_email text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor public.users%rowtype;
  v_target public.users%rowtype;
  v_actor_role text;
  v_target_role text;
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_existing_auth_id uuid;
  v_existing_user_id text;
  v_invitation private.account_invitations%rowtype;
begin
  if p_actor_auth_user_id is null then return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED'); end if;
  select * into v_actor from public.users where auth_user_id = p_actor_auth_user_id and status = 'active' limit 1;
  if not found then return jsonb_build_object('ok', false, 'code', 'ACTOR_NOT_FOUND'); end if;
  v_actor_role := case v_actor.role when 'direction_pedagogique' then 'direction2' when 'caisse' then 'direction3' else v_actor.role end;
  if v_actor_role not in ('direction', 'direction2') then return jsonb_build_object('ok', false, 'code', 'FORBIDDEN'); end if;

  if nullif(btrim(coalesce(p_app_user_id, '')), '') is null then
    return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'app_user_id');
  end if;
  if v_email = '' or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'email');
  end if;

  select * into v_target from public.users where id = p_app_user_id for update;
  if not found then return jsonb_build_object('ok', false, 'code', 'TARGET_NOT_FOUND'); end if;
  v_target_role := case v_target.role when 'direction_pedagogique' then 'direction2' when 'caisse' then 'direction3' when 'enseignant_maternelle' then 'enseignant' else v_target.role end;
  if v_target_role not in ('direction', 'direction2', 'direction3', 'enseignant', 'parent', 'gardien') then
    return jsonb_build_object('ok', false, 'code', 'UNSUPPORTED_ROLE');
  end if;
  if v_actor_role = 'direction2' and v_target_role not in ('enseignant', 'gardien', 'parent') then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN_TARGET_ROLE');
  end if;
  if v_target.status <> 'active' then return jsonb_build_object('ok', false, 'code', 'TARGET_DISABLED'); end if;
  if not v_target.login_email_enabled then return jsonb_build_object('ok', false, 'code', 'EMAIL_LOGIN_DISABLED'); end if;
  if not v_target.contact_setup_complete then return jsonb_build_object('ok', false, 'code', 'CONTACT_SETUP_INCOMPLETE'); end if;
  if v_target.email is distinct from v_email then return jsonb_build_object('ok', false, 'code', 'EMAIL_PROFILE_MISMATCH'); end if;
  if v_target.auth_user_id is not null then return jsonb_build_object('ok', false, 'code', 'ALREADY_LINKED', 'app_user_id', v_target.id); end if;

  select id into v_existing_user_id from public.users
   where id <> v_target.id and email is not null and email = v_email limit 1;
  if found then return jsonb_build_object('ok', false, 'code', 'EMAIL_IN_USE'); end if;
  select id into v_existing_auth_id from auth.users
   where email is not null and lower(btrim(email)) = v_email limit 1;
  if found then return jsonb_build_object('ok', false, 'code', 'EMAIL_IN_USE'); end if;

  select * into v_invitation from private.account_invitations where lower(email) = v_email limit 1;
  if found and v_invitation.app_user_id is distinct from v_target.id and v_invitation.accepted_at is null then
    return jsonb_build_object('ok', false, 'code', 'EMAIL_IN_USE');
  end if;

  insert into private.account_invitations(
    email, full_name, role, invited_at, expires_at, accepted_at,
    auth_user_id, app_user_id, invited_by
  ) values (
    v_email, v_target.name, v_target.role, now(), now() + interval '3 days', null,
    null, v_target.id, v_actor.id
  )
  on conflict(email) do update
    set full_name = excluded.full_name,
        role = excluded.role,
        invited_at = excluded.invited_at,
        expires_at = excluded.expires_at,
        accepted_at = null,
        auth_user_id = null,
        app_user_id = excluded.app_user_id,
        invited_by = excluded.invited_by
  returning * into v_invitation;

  update public.users set invitation_sent_at = now(), updated_at = now() where id = v_target.id;
  perform private.write_audit_event(
    v_actor.id, v_actor.name, 'account_invitation_prepared',
    jsonb_build_object('email', v_email, 'role', v_target.role, 'invitation_id', v_invitation.id),
    v_target.id
  );

  return jsonb_build_object(
    'ok', true,
    'code', 'INVITATION_PREPARED',
    'invitation_id', v_invitation.id,
    'app_user_id', v_target.id,
    'email', v_email,
    'full_name', v_target.name,
    'role', v_target.role,
    'expires_at', v_invitation.expires_at
  );
exception
  when unique_violation then return jsonb_build_object('ok', false, 'code', 'INVITATION_CONFLICT');
  when foreign_key_violation then return jsonb_build_object('ok', false, 'code', 'REFERENCE_NOT_FOUND');
end;
$$;

create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invitation private.account_invitations%rowtype;
  v_phone_request private.parent_phone_access_requests%rowtype;
  v_target public.users%rowtype;
  v_email text := lower(btrim(coalesce(new.email, '')));
  v_expected_email text;
  v_request_id uuid;
  v_request_secret uuid;
  v_target_role text;
begin
  if coalesce(new.raw_user_meta_data->>'school_phone_request_id', '') <> ''
     or coalesce(new.raw_user_meta_data->>'school_phone_request_secret', '') <> '' then
    begin
      v_request_id := nullif(new.raw_user_meta_data->>'school_phone_request_id', '')::uuid;
      v_request_secret := nullif(new.raw_user_meta_data->>'school_phone_request_secret', '')::uuid;
    exception when invalid_text_representation then
      raise exception using errcode = '42501', message = 'Provision téléphone SchoolSafe invalide.';
    end;
    if v_request_id is null or v_request_secret is null then
      raise exception using errcode = '42501', message = 'Provision téléphone SchoolSafe manquante.';
    end if;

    select * into v_phone_request
      from private.parent_phone_access_requests r
     where r.id = v_request_id
       and r.secret = v_request_secret
       and r.action = 'provision'
       and r.status = 'prepared'
       and r.expires_at > now()
     for update;
    if not found then raise exception using errcode = '42501', message = 'Provision téléphone SchoolSafe expirée ou invalide.'; end if;

    select * into v_target from public.users u where u.id = v_phone_request.app_user_id for update;
    if not found then raise exception using errcode = '23503', message = 'Profil SchoolSafe introuvable.'; end if;
    v_target_role := case v_target.role when 'direction_pedagogique' then 'direction2' when 'caisse' then 'direction3' when 'enseignant_maternelle' then 'enseignant' else v_target.role end;
    if v_target_role not in ('direction', 'direction2', 'direction3', 'enseignant', 'gardien', 'parent')
       or v_target.status <> 'active'
       or not v_target.login_phone_enabled then
      raise exception using errcode = '42501', message = 'Profil téléphone SchoolSafe non autorisé.';
    end if;
    if not v_target.contact_setup_complete then
      raise exception using errcode = '23514', message = 'Le profil SchoolSafe doit contenir un e-mail et un téléphone.';
    end if;

    v_expected_email := coalesce(v_target.email, private.phone_auth_email(v_phone_request.phone));
    if v_email is distinct from v_expected_email then
      raise exception using errcode = '23514', message = 'Identité Auth SchoolSafe invalide.';
    end if;
    if v_target.auth_user_id is not null and v_target.auth_user_id <> new.id then
      raise exception using errcode = '23505', message = 'Ce profil SchoolSafe est déjà relié à un autre compte.';
    end if;
    if v_target.phone is distinct from v_phone_request.phone then
      raise exception using errcode = '23514', message = 'Le téléphone demandé ne correspond pas au profil SchoolSafe.';
    end if;

    insert into public.profiles(id, email, phone, full_name, role, status)
    values(new.id, v_target.email, v_phone_request.phone, v_target.name, v_target.role, v_target.status)
    on conflict(id) do update
      set email = excluded.email,
          phone = excluded.phone,
          full_name = excluded.full_name,
          role = excluded.role,
          status = excluded.status,
          updated_at = now();

    update public.users
       set auth_user_id = new.id,
           phone = v_phone_request.phone,
           must_change_password = true,
           temporary_access_expires_at = v_phone_request.expires_at,
           phone_access_updated_at = now(),
           updated_at = now()
     where id = v_target.id;
    update private.parent_phone_access_requests set status = 'auth_linked', auth_user_id = new.id where id = v_phone_request.id;
    return new;
  end if;

  if v_email = '' then raise exception using errcode = '42501', message = 'Identité SchoolSafe manquante.'; end if;
  select * into v_invitation
    from private.account_invitations i
   where lower(i.email) = v_email
     and i.accepted_at is null
     and i.expires_at > now()
   for update;
  if not found then raise exception using errcode = '42501', message = 'Ce compte SchoolSafe ne possède pas une invitation valide.'; end if;
  if v_invitation.app_user_id is null then raise exception using errcode = '23503', message = 'Invitation SchoolSafe non reliée à un profil.'; end if;

  select * into v_target from public.users u where u.id = v_invitation.app_user_id for update;
  if not found then raise exception using errcode = '23503', message = 'Profil SchoolSafe invité introuvable.'; end if;
  v_target_role := case v_target.role when 'direction_pedagogique' then 'direction2' when 'caisse' then 'direction3' when 'enseignant_maternelle' then 'enseignant' else v_target.role end;
  if v_target_role not in ('direction', 'direction2', 'direction3', 'enseignant', 'gardien', 'parent')
     or v_target.status <> 'active'
     or not v_target.login_email_enabled then
    raise exception using errcode = '42501', message = 'Profil e-mail SchoolSafe non autorisé.';
  end if;
  if not v_target.contact_setup_complete then
    raise exception using errcode = '23514', message = 'Le profil SchoolSafe doit contenir un e-mail et un téléphone.';
  end if;
  if v_target.email is distinct from v_email then
    raise exception using errcode = '23514', message = 'L e-mail invité ne correspond pas au profil SchoolSafe.';
  end if;
  if v_target.auth_user_id is not null and v_target.auth_user_id <> new.id then
    raise exception using errcode = '23505', message = 'Ce profil SchoolSafe est déjà relié à un autre compte.';
  end if;

  insert into public.profiles(id, email, phone, full_name, role, status)
  values(new.id, v_email, v_target.phone, v_target.name, v_target.role, v_target.status)
  on conflict(id) do update
    set email = excluded.email,
        phone = excluded.phone,
        full_name = excluded.full_name,
        role = excluded.role,
        status = excluded.status,
        updated_at = now();
  update public.users
     set auth_user_id = new.id,
         invitation_sent_at = coalesce(invitation_sent_at, now()),
         updated_at = now()
   where id = v_target.id;
  update private.account_invitations set accepted_at = now(), auth_user_id = new.id where email = v_invitation.email;
  return new;
end;
$$;

create or replace function public.prepare_parent_phone_access(
  p_actor_auth_user_id uuid,
  p_app_user_id text,
  p_action text,
  p_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor public.users%rowtype;
  v_target public.users%rowtype;
  v_actor_role text;
  v_target_role text;
  v_action text := lower(btrim(coalesce(p_action, '')));
  v_phone text;
  v_auth_email text;
  v_request private.parent_phone_access_requests%rowtype;
  v_next_allowed timestamptz;
begin
  if p_actor_auth_user_id is null then return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED'); end if;
  select * into v_actor from public.users where auth_user_id = p_actor_auth_user_id and status = 'active' limit 1;
  if not found then return jsonb_build_object('ok', false, 'code', 'ACTOR_NOT_FOUND'); end if;
  v_actor_role := case v_actor.role when 'direction_pedagogique' then 'direction2' when 'caisse' then 'direction3' else v_actor.role end;
  if v_actor_role not in ('direction', 'direction2') then return jsonb_build_object('ok', false, 'code', 'FORBIDDEN'); end if;
  if v_action not in ('provision', 'reset', 'change_phone') then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'action'); end if;

  select * into v_target from public.users where id = p_app_user_id for update;
  if not found then return jsonb_build_object('ok', false, 'code', 'TARGET_NOT_FOUND'); end if;
  v_target_role := case v_target.role when 'direction_pedagogique' then 'direction2' when 'caisse' then 'direction3' when 'enseignant_maternelle' then 'enseignant' else v_target.role end;
  if v_target_role not in ('direction', 'direction2', 'direction3', 'enseignant', 'gardien', 'parent') then
    return jsonb_build_object('ok', false, 'code', 'TARGET_NOT_PHONE_ACCOUNT');
  end if;
  if v_actor_role = 'direction2' and v_target_role not in ('enseignant', 'gardien', 'parent') then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN_TARGET_ROLE');
  end if;
  if v_target.status <> 'active' then return jsonb_build_object('ok', false, 'code', 'TARGET_DISABLED'); end if;
  if not v_target.login_phone_enabled then return jsonb_build_object('ok', false, 'code', 'PHONE_LOGIN_DISABLED'); end if;
  if not v_target.contact_setup_complete then return jsonb_build_object('ok', false, 'code', 'CONTACT_SETUP_INCOMPLETE'); end if;

  v_phone := case when v_action = 'change_phone' then private.normalize_phone_e164(p_phone) else private.normalize_phone_e164(v_target.phone) end;
  if v_phone is null then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'phone'); end if;
  if v_action = 'provision' and v_target.auth_user_id is not null then return jsonb_build_object('ok', false, 'code', 'ALREADY_LINKED'); end if;
  if v_action in ('reset', 'change_phone') and v_target.auth_user_id is null then return jsonb_build_object('ok', false, 'code', 'ACCOUNT_NOT_LINKED'); end if;
  if exists(select 1 from public.users where id <> v_target.id and phone = v_phone) then return jsonb_build_object('ok', false, 'code', 'PHONE_IN_USE'); end if;

  v_auth_email := coalesce(v_target.email, private.phone_auth_email(v_phone));
  if exists(select 1 from auth.users where lower(email) = v_auth_email and id is distinct from v_target.auth_user_id) then
    return jsonb_build_object('ok', false, 'code', 'EMAIL_IN_USE');
  end if;

  select created_at + interval '60 seconds' into v_next_allowed
    from private.parent_phone_access_requests
   where app_user_id = v_target.id
     and created_at > now() - interval '60 seconds'
   order by created_at desc limit 1;
  if found then return jsonb_build_object('ok', false, 'code', 'TOO_SOON', 'next_allowed_at', v_next_allowed); end if;

  update private.parent_phone_access_requests
     set status = case when expires_at <= now() then 'expired' else 'failed' end,
         failed_at = now(),
         failure_code = case when expires_at <= now() then 'EXPIRED_REPLACED' else 'REPLACED' end
   where app_user_id = v_target.id and status in ('prepared', 'auth_linked', 'ready');

  insert into private.parent_phone_access_requests(app_user_id, phone, action, requested_by, auth_user_id)
  values(v_target.id, v_phone, v_action, v_actor.id, case when v_action = 'provision' then null else v_target.auth_user_id end)
  returning * into v_request;

  perform private.write_audit_event(
    v_actor.id, v_actor.name, 'phone_access_prepared',
    jsonb_build_object('app_user_id', v_target.id, 'role', v_target_role, 'action', v_action, 'expires_at', v_request.expires_at),
    v_target.id
  );

  return jsonb_build_object(
    'ok', true,
    'code', 'PHONE_ACCESS_PREPARED',
    'request_id', v_request.id,
    'request_secret', v_request.secret,
    'app_user_id', v_target.id,
    'phone', v_phone,
    'auth_email', v_auth_email,
    'action', v_action,
    'auth_user_id', v_request.auth_user_id,
    'expires_at', v_request.expires_at
  );
exception when unique_violation then
  return jsonb_build_object('ok', false, 'code', 'PHONE_ACCESS_CONFLICT');
end;
$$;

create or replace function private.finalize_parent_phone_access_impl(p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request private.parent_phone_access_requests%rowtype;
  v_target public.users%rowtype;
  v_auth auth.users%rowtype;
  v_fingerprint text;
  v_expected_email text;
begin
  select * into v_request from private.parent_phone_access_requests where id = p_request_id for update;
  if not found then return jsonb_build_object('ok', false, 'code', 'REQUEST_NOT_FOUND'); end if;
  if v_request.status = 'ready' then
    return jsonb_build_object('ok', true, 'code', 'PHONE_ACCESS_READY', 'app_user_id', v_request.app_user_id, 'phone', v_request.phone, 'expires_at', v_request.expires_at);
  end if;
  if v_request.status not in ('prepared', 'auth_linked') then return jsonb_build_object('ok', false, 'code', 'REQUEST_NOT_OPEN'); end if;
  if v_request.expires_at <= now() then
    update private.parent_phone_access_requests set status = 'expired', failed_at = now(), failure_code = 'EXPIRED' where id = v_request.id;
    return jsonb_build_object('ok', false, 'code', 'REQUEST_EXPIRED');
  end if;

  select * into v_target from public.users where id = v_request.app_user_id for update;
  if not found then return jsonb_build_object('ok', false, 'code', 'TARGET_NOT_FOUND'); end if;
  if v_request.auth_user_id is null then v_request.auth_user_id := v_target.auth_user_id; end if;
  if v_request.auth_user_id is null then return jsonb_build_object('ok', false, 'code', 'AUTH_LINK_MISSING'); end if;
  select * into v_auth from auth.users where id = v_request.auth_user_id;
  if not found then return jsonb_build_object('ok', false, 'code', 'AUTH_USER_NOT_FOUND'); end if;

  v_expected_email := coalesce(v_target.email, private.phone_auth_email(v_request.phone));
  if lower(coalesce(v_auth.email, '')) is distinct from v_expected_email then
    return jsonb_build_object('ok', false, 'code', 'AUTH_IDENTITY_MISMATCH');
  end if;
  v_fingerprint := pg_catalog.encode(extensions.digest(coalesce(v_auth.encrypted_password, ''), 'sha256'), 'hex');

  update public.users
     set auth_user_id = v_request.auth_user_id,
         phone = v_request.phone,
         must_change_password = true,
         temporary_access_expires_at = v_request.expires_at,
         phone_access_updated_at = now(),
         updated_at = now()
   where id = v_request.app_user_id;

  insert into public.profiles(id, email, phone, full_name, role, status)
  values(v_request.auth_user_id, v_target.email, v_request.phone, v_target.name, v_target.role, v_target.status)
  on conflict(id) do update
    set email = excluded.email,
        phone = excluded.phone,
        full_name = excluded.full_name,
        role = excluded.role,
        status = excluded.status,
        updated_at = now();

  update private.parent_phone_access_requests
     set status = 'ready', auth_user_id = v_request.auth_user_id,
         password_fingerprint = v_fingerprint, ready_at = now()
   where id = v_request.id;

  perform private.write_audit_event(
    v_request.requested_by,
    (select name from public.users where id = v_request.requested_by),
    'phone_access_ready',
    jsonb_build_object('app_user_id', v_request.app_user_id, 'action', v_request.action, 'expires_at', v_request.expires_at),
    v_request.app_user_id
  );

  return jsonb_build_object(
    'ok', true,
    'code', 'PHONE_ACCESS_READY',
    'app_user_id', v_request.app_user_id,
    'phone', v_request.phone,
    'action', v_request.action,
    'expires_at', v_request.expires_at,
    'next_allowed_at', v_request.created_at + interval '60 seconds'
  );
end;
$$;

create or replace function private.confirm_parent_phone_password_change_impl()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user public.users%rowtype;
  v_request private.parent_phone_access_requests%rowtype;
  v_auth auth.users%rowtype;
  v_fingerprint text;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED'); end if;
  select * into v_user from public.users where auth_user_id = auth.uid() for update;
  if not found then return jsonb_build_object('ok', false, 'code', 'PROFILE_NOT_LINKED'); end if;
  if not v_user.login_phone_enabled then return jsonb_build_object('ok', false, 'code', 'NOT_PHONE_ACCOUNT'); end if;
  if not v_user.must_change_password then return jsonb_build_object('ok', true, 'code', 'ACCESS_ALREADY_READY'); end if;
  if v_user.temporary_access_expires_at is null or v_user.temporary_access_expires_at <= now() then
    return jsonb_build_object('ok', false, 'code', 'TEMPORARY_PASSWORD_EXPIRED');
  end if;

  select * into v_request
    from private.parent_phone_access_requests
   where app_user_id = v_user.id
     and auth_user_id = auth.uid()
     and status = 'ready'
   order by created_at desc limit 1 for update;
  if not found then return jsonb_build_object('ok', false, 'code', 'ACCESS_REQUEST_NOT_FOUND'); end if;
  select * into v_auth from auth.users where id = auth.uid();
  if not found then return jsonb_build_object('ok', false, 'code', 'AUTH_USER_NOT_FOUND'); end if;

  v_fingerprint := pg_catalog.encode(extensions.digest(coalesce(v_auth.encrypted_password, ''), 'sha256'), 'hex');
  if v_fingerprint = v_request.password_fingerprint then return jsonb_build_object('ok', false, 'code', 'PASSWORD_NOT_CHANGED'); end if;

  update public.users
     set must_change_password = false,
         temporary_access_expires_at = null,
         phone_access_updated_at = now(),
         updated_at = now()
   where id = v_user.id;
  update public.profiles
     set phone = v_user.phone,
         email = v_user.email,
         role = v_user.role,
         updated_at = now()
   where id = auth.uid();
  update private.parent_phone_access_requests set status = 'completed', completed_at = now() where id = v_request.id;
  perform private.write_audit_event(v_user.id, v_user.name, 'phone_password_changed', jsonb_build_object('app_user_id', v_user.id, 'role', v_user.role), v_user.id);
  return jsonb_build_object('ok', true, 'code', 'ACCESS_READY');
end;
$$;

create or replace function public.get_my_access_state()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user public.users%rowtype;
  v_expired boolean;
begin
  if auth.uid() is null then return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED'); end if;
  select * into v_user from public.users where auth_user_id = auth.uid() limit 1;
  if not found then return jsonb_build_object('ok', false, 'code', 'PROFILE_NOT_LINKED'); end if;
  if v_user.status <> 'active' then return jsonb_build_object('ok', false, 'code', 'ACCOUNT_DISABLED', 'status', v_user.status); end if;
  v_expired := v_user.must_change_password and v_user.temporary_access_expires_at is not null and v_user.temporary_access_expires_at <= now();
  return jsonb_build_object(
    'ok', true,
    'code', case when v_expired then 'TEMPORARY_PASSWORD_EXPIRED' when v_user.must_change_password then 'TEMPORARY_PASSWORD_MUST_CHANGE' else 'ACCESS_READY' end,
    'app_user_id', v_user.id,
    'role', v_user.role,
    'access_channel', v_user.access_channel,
    'email', v_user.email,
    'phone', v_user.phone,
    'login_email_enabled', v_user.login_email_enabled,
    'login_phone_enabled', v_user.login_phone_enabled,
    'contact_setup_complete', v_user.contact_setup_complete,
    'must_change_password', v_user.must_change_password,
    'temporary_access_expires_at', v_user.temporary_access_expires_at,
    'expired', v_expired
  );
end;
$$;

create table if not exists private.school_login_rate_limits (
  key_hash text primary key check (key_hash ~ '^[0-9a-f]{64}$'),
  window_started_at timestamptz not null default now(),
  attempts integer not null default 0 check (attempts >= 0),
  blocked_until timestamptz,
  updated_at timestamptz not null default now()
);

create or replace function public.resolve_school_login_identity(p_identifier text, p_channel text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_channel text := lower(btrim(coalesce(p_channel, '')));
  v_identifier text;
  v_user public.users%rowtype;
  v_auth_email text;
  v_identifier_key text;
begin
  if v_channel = 'email' then
    v_identifier := lower(btrim(coalesce(p_identifier, '')));
    if v_identifier = '' or v_identifier !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
      return jsonb_build_object('ok', false, 'code', 'INVALID_CREDENTIALS');
    end if;
    select * into v_user from public.users
     where email = v_identifier and login_email_enabled and status = 'active' limit 1;
  elsif v_channel in ('phone', 'phone_whatsapp') then
    v_identifier := private.normalize_phone_e164(p_identifier);
    if v_identifier is null then return jsonb_build_object('ok', false, 'code', 'INVALID_CREDENTIALS'); end if;
    select * into v_user from public.users
     where phone = v_identifier and login_phone_enabled and status = 'active' limit 1;
    v_channel := 'phone';
  else
    return jsonb_build_object('ok', false, 'code', 'INVALID_CREDENTIALS');
  end if;

  if not found or v_user.auth_user_id is null then
    return jsonb_build_object('ok', false, 'code', 'INVALID_CREDENTIALS');
  end if;
  select lower(email) into v_auth_email from auth.users where id = v_user.auth_user_id and deleted_at is null;
  if v_auth_email is null then return jsonb_build_object('ok', false, 'code', 'INVALID_CREDENTIALS'); end if;

  v_identifier_key := pg_catalog.encode(extensions.digest(v_channel || ':' || v_identifier, 'sha256'), 'hex');
  return jsonb_build_object('ok', true, 'auth_email', v_auth_email, 'identifier_key', v_identifier_key);
end;
$$;

create or replace function public.consume_school_login_attempt(p_key_hash text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row private.school_login_rate_limits%rowtype;
  v_now timestamptz := now();
  v_retry integer;
begin
  if p_key_hash is null or p_key_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('ok', false, 'allowed', false, 'code', 'INVALID_RATE_KEY');
  end if;

  insert into private.school_login_rate_limits(key_hash, window_started_at, attempts, updated_at)
  values(p_key_hash, v_now, 0, v_now)
  on conflict(key_hash) do nothing;

  select * into v_row from private.school_login_rate_limits where key_hash = p_key_hash for update;
  if v_row.blocked_until is not null and v_row.blocked_until > v_now then
    v_retry := greatest(1, ceil(extract(epoch from (v_row.blocked_until - v_now)))::integer);
    return jsonb_build_object('ok', true, 'allowed', false, 'code', 'TOO_MANY_ATTEMPTS', 'retry_after_seconds', v_retry);
  end if;

  if v_row.window_started_at <= v_now - interval '15 minutes' then
    v_row.window_started_at := v_now;
    v_row.attempts := 0;
    v_row.blocked_until := null;
  end if;
  v_row.attempts := v_row.attempts + 1;
  if v_row.attempts > 8 then
    v_row.blocked_until := v_now + interval '15 minutes';
  end if;

  update private.school_login_rate_limits
     set window_started_at = v_row.window_started_at,
         attempts = v_row.attempts,
         blocked_until = v_row.blocked_until,
         updated_at = v_now
   where key_hash = p_key_hash;

  if v_row.blocked_until is not null then
    return jsonb_build_object('ok', true, 'allowed', false, 'code', 'TOO_MANY_ATTEMPTS', 'retry_after_seconds', 900);
  end if;
  return jsonb_build_object('ok', true, 'allowed', true, 'attempts_remaining', greatest(0, 8 - v_row.attempts));
end;
$$;

create or replace function public.clear_school_login_attempts(p_key_hash text)
returns void
language sql
security definer
set search_path = ''
as $$
  delete from private.school_login_rate_limits where key_hash = p_key_hash
$$;

revoke all on function public.resolve_school_login_identity(text, text) from public, anon, authenticated;
grant execute on function public.resolve_school_login_identity(text, text) to service_role;
revoke all on function public.consume_school_login_attempt(text) from public, anon, authenticated;
grant execute on function public.consume_school_login_attempt(text) to service_role;
revoke all on function public.clear_school_login_attempts(text) from public, anon, authenticated;
grant execute on function public.clear_school_login_attempts(text) to service_role;

comment on function public.resolve_school_login_identity(text, text) is
  'Résout côté serveur une adresse e-mail ou un téléphone vers l unique identité Auth liée. Exécution service_role uniquement.';
comment on table private.school_login_rate_limits is
  'Compteurs anti-bruteforce du relais de connexion e-mail ou téléphone; aucune coordonnée en clair.';
