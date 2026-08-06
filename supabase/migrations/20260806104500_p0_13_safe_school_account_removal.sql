-- P0-13: remove Auth access while preserving SchoolSafe audit history.

alter table public.users
  add column if not exists access_removed_at timestamptz,
  add column if not exists access_removed_by text,
  add column if not exists access_removal_reason text,
  add column if not exists removed_auth_user_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.users'::regclass
      and conname='users_access_removed_by_fkey'
  ) then
    alter table public.users
      add constraint users_access_removed_by_fkey
      foreign key(access_removed_by) references public.users(id) on delete restrict;
  end if;
end $$;

alter table public.users drop constraint if exists users_auth_user_id_fkey;
alter table public.users
  add constraint users_auth_user_id_fkey
  foreign key(auth_user_id) references auth.users(id) on delete set null;

comment on column public.users.access_removed_at is
  'Horodatage serveur du retrait de l accès Auth.';
comment on column public.users.access_removed_by is
  'Direction 1 ayant retiré l accès Auth.';
comment on column public.users.access_removal_reason is
  'Motif administratif du retrait d accès.';
comment on column public.users.removed_auth_user_id is
  'Dernier UUID Auth conservé comme trace après suppression de l identité.';

alter table public.school_files
  add column if not exists uploaded_by_app_user_id text,
  add column if not exists uploaded_by_name text,
  add column if not exists uploaded_by_role text;

update public.school_files f
set uploaded_by_app_user_id=u.id,
    uploaded_by_name=u.name,
    uploaded_by_role=case u.role
      when 'direction_pedagogique' then 'direction2'
      when 'caisse' then 'direction3'
      else u.role
    end
from public.users u
where u.auth_user_id=f.uploaded_by
  and (f.uploaded_by_app_user_id is null
    or f.uploaded_by_name is null
    or f.uploaded_by_role is null);

create or replace function private.stamp_school_file_uploader()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user public.users%rowtype;
  v_role text;
begin
  if tg_op='UPDATE' then
    new.uploaded_by := old.uploaded_by;
    new.uploaded_by_app_user_id := old.uploaded_by_app_user_id;
    new.uploaded_by_name := old.uploaded_by_name;
    new.uploaded_by_role := old.uploaded_by_role;
    return new;
  end if;

  if new.uploaded_by is null then
    raise exception 'Identité du téléverseur requise.' using errcode='23502';
  end if;

  select * into v_user from public.users
  where auth_user_id=new.uploaded_by and status='active'
  limit 1;

  if not found then
    raise exception 'Profil SchoolSafe actif du téléverseur introuvable.' using errcode='42501';
  end if;

  v_role := case v_user.role
    when 'direction_pedagogique' then 'direction2'
    when 'caisse' then 'direction3'
    else v_user.role
  end;

  new.uploaded_by_app_user_id := v_user.id;
  new.uploaded_by_name := v_user.name;
  new.uploaded_by_role := v_role;
  return new;
end;
$$;

revoke all on function private.stamp_school_file_uploader() from public,anon,authenticated;
grant execute on function private.stamp_school_file_uploader() to service_role;

drop trigger if exists trg_school_files_uploader_snapshot on public.school_files;
create trigger trg_school_files_uploader_snapshot
before insert or update on public.school_files
for each row execute function private.stamp_school_file_uploader();

alter table public.school_files
  alter column uploaded_by_app_user_id set not null,
  alter column uploaded_by_name set not null,
  alter column uploaded_by_role set not null,
  alter column uploaded_by drop not null;

alter table public.school_files drop constraint if exists school_files_uploaded_by_fkey;
alter table public.school_files
  add constraint school_files_uploaded_by_fkey
  foreign key(uploaded_by) references auth.users(id) on delete set null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.school_files'::regclass
      and conname='school_files_uploaded_by_app_user_id_fkey'
  ) then
    alter table public.school_files
      add constraint school_files_uploaded_by_app_user_id_fkey
      foreign key(uploaded_by_app_user_id) references public.users(id) on delete restrict;
  end if;
end $$;

comment on column public.school_files.uploaded_by_app_user_id is
  'Identifiant SchoolSafe immuable du téléverseur.';
comment on column public.school_files.uploaded_by_name is
  'Nom figé du téléverseur au moment du dépôt.';
comment on column public.school_files.uploaded_by_role is
  'Rôle figé du téléverseur au moment du dépôt.';

create or replace function public.prepare_school_account_removal(
  p_actor_auth_user_id uuid,
  p_app_user_id text,
  p_reason text
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
  v_reason text := btrim(coalesce(p_reason,''));
  v_auth_user_id uuid;
  v_now timestamptz := now();
  v_cancelled_invitations integer := 0;
  v_expired_phone_requests integer := 0;
begin
  if p_actor_auth_user_id is null
     or nullif(btrim(coalesce(p_app_user_id,'')),'') is null then
    return jsonb_build_object('ok',false,'code','VALIDATION_ERROR');
  end if;

  if length(v_reason)<5 or length(v_reason)>500 then
    return jsonb_build_object('ok',false,'code','INVALID_REASON');
  end if;

  select * into v_actor from public.users
  where auth_user_id=p_actor_auth_user_id and status='active'
  limit 1;

  if not found then
    return jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND');
  end if;

  v_actor_role := case v_actor.role
    when 'direction_pedagogique' then 'direction2'
    when 'caisse' then 'direction3'
    else v_actor.role
  end;

  if v_actor_role<>'direction' then
    return jsonb_build_object('ok',false,'code','FORBIDDEN');
  end if;

  select * into v_target from public.users
  where id=p_app_user_id
  for update;

  if not found then
    return jsonb_build_object('ok',false,'code','TARGET_NOT_FOUND');
  end if;

  if v_target.id=v_actor.id or v_target.auth_user_id=p_actor_auth_user_id then
    return jsonb_build_object('ok',false,'code','CANNOT_REMOVE_CURRENT_ACCOUNT');
  end if;

  v_target_role := case v_target.role
    when 'direction_pedagogique' then 'direction2'
    when 'caisse' then 'direction3'
    else v_target.role
  end;

  if v_target_role='direction' and not exists(
    select 1 from public.users u
    where u.id<>v_target.id
      and u.status='active'
      and (case u.role when 'direction_pedagogique' then 'direction2' when 'caisse' then 'direction3' else u.role end)='direction'
      and u.auth_user_id is not null
  ) then
    return jsonb_build_object('ok',false,'code','LAST_DIRECTION_ACCOUNT');
  end if;

  v_auth_user_id := v_target.auth_user_id;

  delete from private.account_invitations i
  where i.accepted_at is null
    and (i.app_user_id=v_target.id
      or (v_target.email is not null and lower(i.email)=lower(v_target.email)));
  get diagnostics v_cancelled_invitations=row_count;

  update private.parent_phone_access_requests r
  set status='expired',
      failed_at=coalesce(r.failed_at,v_now),
      failure_code='ACCOUNT_REMOVED'
  where r.app_user_id=v_target.id
    and r.status in ('prepared','auth_linked','ready');
  get diagnostics v_expired_phone_requests=row_count;

  update public.users
  set status='inactive',
      login_email_enabled=false,
      login_phone_enabled=false,
      must_change_password=false,
      temporary_access_expires_at=null,
      invitation_sent_at=null,
      access_removed_at=coalesce(access_removed_at,v_now),
      access_removed_by=coalesce(access_removed_by,v_actor.id),
      access_removal_reason=v_reason,
      removed_auth_user_id=coalesce(removed_auth_user_id,v_auth_user_id),
      updated_at=v_now
  where id=v_target.id
  returning * into v_target;

  if v_auth_user_id is not null then
    update public.profiles
    set status='inactive',updated_at=v_now
    where id=v_auth_user_id;
  end if;

  perform private.write_audit_event(
    v_actor.id,
    v_actor.name,
    'school_account_removal_prepared',
    jsonb_build_object(
      'target_role',v_target_role,
      'had_auth_identity',v_auth_user_id is not null,
      'cancelled_invitations',v_cancelled_invitations,
      'expired_phone_requests',v_expired_phone_requests,
      'reason',v_reason
    ),
    v_target.id
  );

  return jsonb_build_object(
    'ok',true,
    'code',case when v_auth_user_id is null then 'ACCOUNT_ALREADY_WITHOUT_AUTH' else 'REMOVAL_PREPARED' end,
    'app_user_id',v_target.id,
    'auth_user_id',v_auth_user_id,
    'removed_auth_user_id',v_target.removed_auth_user_id,
    'name',v_target.name,
    'role',v_target_role,
    'status',v_target.status,
    'access_removed_at',v_target.access_removed_at
  );
end;
$$;

create or replace function public.confirm_school_account_removal(
  p_actor_auth_user_id uuid,
  p_app_user_id text,
  p_expected_auth_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor public.users%rowtype;
  v_target public.users%rowtype;
begin
  select * into v_actor from public.users
  where auth_user_id=p_actor_auth_user_id and status='active'
  limit 1;

  if not found or v_actor.role<>'direction' then
    return jsonb_build_object('ok',false,'code','FORBIDDEN');
  end if;

  select * into v_target from public.users where id=p_app_user_id limit 1;
  if not found then
    return jsonb_build_object('ok',false,'code','TARGET_NOT_FOUND');
  end if;

  if v_target.auth_user_id is not null then
    return jsonb_build_object('ok',false,'code','AUTH_IDENTITY_STILL_PRESENT');
  end if;

  if p_expected_auth_user_id is not null
     and v_target.removed_auth_user_id is distinct from p_expected_auth_user_id then
    return jsonb_build_object('ok',false,'code','AUTH_IDENTITY_MISMATCH');
  end if;

  perform private.write_audit_event(
    v_actor.id,
    v_actor.name,
    'school_account_access_removed',
    jsonb_build_object(
      'removed_auth_user_id',v_target.removed_auth_user_id,
      'access_removed_at',v_target.access_removed_at,
      'reason',v_target.access_removal_reason
    ),
    v_target.id
  );

  return jsonb_build_object(
    'ok',true,
    'code','ACCOUNT_ACCESS_REMOVED',
    'app_user_id',v_target.id,
    'status',v_target.status,
    'access_removed_at',v_target.access_removed_at
  );
end;
$$;

revoke all on function public.prepare_school_account_removal(uuid,text,text) from public,anon,authenticated;
grant execute on function public.prepare_school_account_removal(uuid,text,text) to service_role;
revoke all on function public.confirm_school_account_removal(uuid,text,uuid) from public,anon,authenticated;
grant execute on function public.confirm_school_account_removal(uuid,text,uuid) to service_role;

comment on function public.prepare_school_account_removal(uuid,text,text) is
  'Direction 1 only via Edge Function: disables a target, cancels pending access and returns the Auth UUID to delete.';
comment on function public.confirm_school_account_removal(uuid,text,uuid) is
  'Confirms that the Auth identity was deleted while the inactive SchoolSafe audit record remains.';
