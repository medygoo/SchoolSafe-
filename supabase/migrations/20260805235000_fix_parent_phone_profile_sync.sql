create or replace function private.protect_profile_identity_fields()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  -- Only the phone-auth wrappers set this transaction-local target before a
  -- server-controlled profile synchronization. The value must match the row.
  if nullif(current_setting('schoolsafe.profile_sync_target', true), '') = old.id::text then
    new.updated_at := now();
    return new;
  end if;

  if private.is_direction() then
    new.updated_at := now();
    return new;
  end if;

  if (select auth.uid()) is null or old.id <> (select auth.uid()) then
    raise exception 'Accès refusé' using errcode='42501';
  end if;

  if new.id is distinct from old.id
     or new.email is distinct from old.email
     or new.role is distinct from old.role
     or new.status is distinct from old.status
     or new.created_at is distinct from old.created_at then
    raise exception 'Les champs d’identité et de rôle sont protégés' using errcode='42501';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

alter function public.save_parent_phone_profile(jsonb)
  rename to save_parent_phone_profile_impl;
alter function public.save_parent_phone_profile_impl(jsonb)
  set schema private;

create or replace function public.save_parent_phone_profile(p_user jsonb)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_id text := btrim(coalesce(p_user->>'id', ''));
  v_auth_user_id uuid;
  v_result jsonb;
begin
  select u.auth_user_id into v_auth_user_id
  from public.users u
  where u.id = v_id;

  if v_auth_user_id is not null then
    perform set_config('schoolsafe.profile_sync_target', v_auth_user_id::text, true);
  end if;

  v_result := private.save_parent_phone_profile_impl(p_user);
  perform set_config('schoolsafe.profile_sync_target', '', true);
  return v_result;
exception
  when others then
    perform set_config('schoolsafe.profile_sync_target', '', true);
    raise;
end;
$$;

alter function public.finalize_parent_phone_access(uuid)
  rename to finalize_parent_phone_access_impl;
alter function public.finalize_parent_phone_access_impl(uuid)
  set schema private;

create or replace function public.finalize_parent_phone_access(p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_auth_user_id uuid;
  v_result jsonb;
begin
  select coalesce(r.auth_user_id, u.auth_user_id)
    into v_auth_user_id
  from private.parent_phone_access_requests r
  left join public.users u on u.id = r.app_user_id
  where r.id = p_request_id;

  if v_auth_user_id is not null then
    perform set_config('schoolsafe.profile_sync_target', v_auth_user_id::text, true);
  end if;

  v_result := private.finalize_parent_phone_access_impl(p_request_id);
  perform set_config('schoolsafe.profile_sync_target', '', true);
  return v_result;
exception
  when others then
    perform set_config('schoolsafe.profile_sync_target', '', true);
    raise;
end;
$$;

alter function public.confirm_parent_phone_password_change()
  rename to confirm_parent_phone_password_change_impl;
alter function public.confirm_parent_phone_password_change_impl()
  set schema private;

create or replace function public.confirm_parent_phone_password_change()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_auth_user_id uuid := auth.uid();
  v_result jsonb;
begin
  if v_auth_user_id is not null then
    perform set_config('schoolsafe.profile_sync_target', v_auth_user_id::text, true);
  end if;

  v_result := private.confirm_parent_phone_password_change_impl();
  perform set_config('schoolsafe.profile_sync_target', '', true);
  return v_result;
exception
  when others then
    perform set_config('schoolsafe.profile_sync_target', '', true);
    raise;
end;
$$;

revoke all on function private.save_parent_phone_profile_impl(jsonb)
  from public, anon, authenticated, service_role;
revoke all on function private.finalize_parent_phone_access_impl(uuid)
  from public, anon, authenticated, service_role;
revoke all on function private.confirm_parent_phone_password_change_impl()
  from public, anon, authenticated, service_role;

revoke all on function public.save_parent_phone_profile(jsonb) from public, anon;
grant execute on function public.save_parent_phone_profile(jsonb)
  to authenticated, service_role;

revoke all on function public.finalize_parent_phone_access(uuid)
  from public, anon, authenticated;
grant execute on function public.finalize_parent_phone_access(uuid)
  to service_role;

revoke all on function public.confirm_parent_phone_password_change()
  from public, anon;
grant execute on function public.confirm_parent_phone_password_change()
  to authenticated, service_role;
