-- SchoolSafe VPS baseline - 03b private account/auth functions

BEGIN;

CREATE OR REPLACE FUNCTION private.can_notify(p_target_uid text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case private.current_app_role()
    when 'direction' then true
    when 'direction2' then exists(
      select 1 from public.users u where u.id = p_target_uid
        and u.role in ('direction', 'direction2', 'direction_pedagogique',
                       'enseignant', 'gardien', 'parent')
    )
    when 'direction3' then exists(
      select 1 from public.users u where u.id = p_target_uid
        and u.role in ('direction', 'parent')
    )
    when 'enseignant' then exists(
      select 1 from public.users u where u.id = p_target_uid
        and u.role in ('direction', 'direction2', 'direction_pedagogique', 'parent')
    )
    when 'gardien' then exists(
      select 1 from public.users u where u.id = p_target_uid
        and u.role in ('direction', 'direction2', 'direction_pedagogique', 'parent')
    )
    when 'parent' then exists(
      select 1 from public.users u where u.id = p_target_uid
        and u.role in ('direction', 'direction2', 'direction_pedagogique')
    )
    else false
  end
$function$;

CREATE OR REPLACE FUNCTION private.enforce_parent_access_ready_on_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text;
begin
  v_role:=case new.role when 'direction_pedagogique' then 'direction2' when 'caisse' then 'direction3' else new.role end;
  if v_role='parent' then
    new.access_ready:=exists(
      select 1 from public.students s where s.pid=new.id and not coalesce(s.archived,false)
    );
    new.access_block_reason:=case when new.access_ready then null else 'NO_LINKED_STUDENT' end;
  else
    new.access_ready:=true;
    new.access_block_reason:=null;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.guard_invitation_target_ready()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if exists(select 1 from public.users u where u.id=new.app_user_id and u.role='parent' and not u.access_ready) then
    raise exception 'PARENT_LINK_REQUIRED' using errcode='42501';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.guard_phone_request_target_ready()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if exists(select 1 from public.users u where u.id=new.app_user_id and u.role='parent' and not u.access_ready) then
    raise exception 'PARENT_LINK_REQUIRED' using errcode='42501';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.guard_auth_user_access_ready()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_request_id uuid;
  v_app_user_id text;
  v_email text:=lower(btrim(coalesce(new.email,'')));
begin
  if coalesce(new.raw_user_meta_data->>'school_phone_request_id','')<>'' then
    begin
      v_request_id:=(new.raw_user_meta_data->>'school_phone_request_id')::uuid;
    exception when invalid_text_representation then
      return new;
    end;
    select r.app_user_id into v_app_user_id from private.parent_phone_access_requests r where r.id=v_request_id;
  elsif v_email<>'' then
    select i.app_user_id into v_app_user_id from private.account_invitations i
    where lower(i.email)=v_email and i.accepted_at is null and i.expires_at>now() limit 1;
  end if;
  if exists(select 1 from public.users u where u.id=v_app_user_id and u.role='parent' and not u.access_ready) then
    raise exception 'PARENT_LINK_REQUIRED' using errcode='42501';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.handle_new_auth_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
       or v_target.phone is null
       or not v_target.login_phone_enabled then
      raise exception using errcode = '42501', message = 'Profil téléphone SchoolSafe non autorisé.';
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
           login_phone_enabled = true,
           login_email_enabled = (email is not null),
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
     or v_target.email is null
     or not v_target.login_email_enabled then
    raise exception using errcode = '42501', message = 'Profil e-mail SchoolSafe non autorisé.';
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
         login_email_enabled = true,
         login_phone_enabled = (phone is not null),
         invitation_sent_at = coalesce(invitation_sent_at, now()),
         updated_at = now()
   where id = v_target.id;
  update private.account_invitations set accepted_at = now(), auth_user_id = new.id where email = v_invitation.email;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.finalize_parent_phone_access_impl(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION private.confirm_parent_phone_password_change_impl()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION private.save_parent_phone_profile_impl(p_user jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select private.save_school_user_profile_dual_impl(p_user)
$function$;

COMMIT;
