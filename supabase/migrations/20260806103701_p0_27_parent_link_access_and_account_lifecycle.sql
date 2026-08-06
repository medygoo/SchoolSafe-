-- P0-27A: parent access readiness, primary-parent history, identity and account lifecycle.

alter table public.users
  add column if not exists access_ready boolean not null default true,
  add column if not exists access_block_reason text;

update public.users u
set access_ready = exists(
      select 1 from public.students s
      where s.pid=u.id and not coalesce(s.archived,false)
    ),
    access_block_reason = case when exists(
      select 1 from public.students s
      where s.pid=u.id and not coalesce(s.archived,false)
    ) then null else 'NO_LINKED_STUDENT' end
where (case u.role when 'direction_pedagogique' then 'direction2' when 'caisse' then 'direction3' else u.role end)='parent';

comment on column public.users.access_ready is
  'False blocks invitation, phone provisioning, login and current sessions. Parent becomes ready only after an active student is linked.';
comment on column public.users.access_block_reason is
  'Machine-readable reason such as NO_LINKED_STUDENT.';

create table if not exists public.student_primary_parent_history (
  id text primary key default ('pph_'||replace(gen_random_uuid()::text,'-','')),
  sid text not null references public.students(id) on delete restrict,
  student_name_snapshot text not null,
  old_parent_id text references public.users(id) on delete restrict,
  old_parent_name_snapshot text,
  new_parent_id text references public.users(id) on delete restrict,
  new_parent_name_snapshot text,
  changed_by_user_id text references public.users(id) on delete restrict,
  changed_by_name text not null,
  changed_by_role text not null,
  changed_at timestamptz not null default now()
);
create index if not exists idx_primary_parent_history_student
  on public.student_primary_parent_history(sid,changed_at desc);

create or replace function private.refresh_parent_access_ready(p_parent_id text)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare
  v_ready boolean;
begin
  if p_parent_id is null then return; end if;
  if not exists(select 1 from public.users where id=p_parent_id and role='parent') then return; end if;
  select exists(
    select 1 from public.students s
    where s.pid=p_parent_id and not coalesce(s.archived,false)
  ) into v_ready;
  update public.users
  set access_ready=v_ready,
      access_block_reason=case when v_ready then null else 'NO_LINKED_STUDENT' end,
      updated_at=now()
  where id=p_parent_id and role='parent';
end;
$$;

create or replace function private.track_primary_parent_change()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_actor_id text:=private.current_app_user_id();
  v_actor_name text;
  v_actor_role text:=coalesce(private.current_app_role(),'system');
  v_old_name text;
  v_new_name text;
begin
  v_actor_name:=coalesce((select name from public.users where id=v_actor_id),'SchoolSafe');
  if tg_op='INSERT' then
    if new.pid is not null then
      select name into v_new_name from public.users where id=new.pid;
      insert into public.student_primary_parent_history(
        sid,student_name_snapshot,old_parent_id,old_parent_name_snapshot,
        new_parent_id,new_parent_name_snapshot,changed_by_user_id,changed_by_name,changed_by_role
      ) values(new.id,coalesce(new.name,new.id),null,null,new.pid,v_new_name,
        v_actor_id,v_actor_name,v_actor_role);
    end if;
    perform private.refresh_parent_access_ready(new.pid);
    return new;
  end if;

  if old.pid is distinct from new.pid then
    select name into v_old_name from public.users where id=old.pid;
    select name into v_new_name from public.users where id=new.pid;
    insert into public.student_primary_parent_history(
      sid,student_name_snapshot,old_parent_id,old_parent_name_snapshot,
      new_parent_id,new_parent_name_snapshot,changed_by_user_id,changed_by_name,changed_by_role
    ) values(new.id,coalesce(new.name,new.id),old.pid,v_old_name,new.pid,v_new_name,
      v_actor_id,v_actor_name,v_actor_role);
  end if;
  perform private.refresh_parent_access_ready(old.pid);
  perform private.refresh_parent_access_ready(new.pid);
  return new;
end;
$$;

drop trigger if exists trg_students_primary_parent_history on public.students;
create trigger trg_students_primary_parent_history
after insert or update of pid,archived on public.students
for each row execute function private.track_primary_parent_change();

create or replace function private.protect_primary_parent_history()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  raise exception 'L historique du parent principal est immuable.' using errcode='23514';
end;
$$;
drop trigger if exists trg_primary_parent_history_immutable on public.student_primary_parent_history;
create trigger trg_primary_parent_history_immutable
before update or delete on public.student_primary_parent_history
for each row execute function private.protect_primary_parent_history();

alter table public.student_primary_parent_history enable row level security;
create policy primary_parent_history_read on public.student_primary_parent_history
for select to authenticated using (
  private.is_direction_any()
  or old_parent_id=private.current_app_user_id()
  or new_parent_id=private.current_app_user_id()
);
revoke all on public.student_primary_parent_history from anon,authenticated;
grant select on public.student_primary_parent_history to authenticated;

create or replace function private.current_app_user_id()
returns text
language sql
stable
security definer
set search_path=''
as $$
  select u.id
  from public.users u
  where u.auth_user_id=auth.uid()
    and u.status='active'
    and u.access_ready
    and not u.must_change_password
  limit 1
$$;

create or replace function private.current_app_role()
returns text
language sql
stable
security definer
set search_path=''
as $$
  select case u.role
    when 'direction_pedagogique' then 'direction2'
    when 'caisse' then 'direction3'
    else u.role
  end
  from public.users u
  where u.auth_user_id=auth.uid()
    and u.status='active'
    and u.access_ready
    and not u.must_change_password
  limit 1
$$;

create or replace function public.get_my_access_state()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_user public.users%rowtype;
  v_expired boolean;
begin
  if auth.uid() is null then return jsonb_build_object('ok',false,'code','AUTH_REQUIRED'); end if;
  select * into v_user from public.users where auth_user_id=auth.uid() limit 1;
  if not found then return jsonb_build_object('ok',false,'code','PROFILE_NOT_LINKED'); end if;
  if v_user.status<>'active' then
    return jsonb_build_object('ok',false,'code','ACCOUNT_DISABLED','status',v_user.status);
  end if;
  if not v_user.access_ready then
    return jsonb_build_object('ok',false,'code',coalesce(v_user.access_block_reason,'ACCESS_NOT_READY'),
      'app_user_id',v_user.id,'role',v_user.role,'access_ready',false);
  end if;
  v_expired:=v_user.must_change_password and v_user.temporary_access_expires_at is not null
    and v_user.temporary_access_expires_at<=now();
  return jsonb_build_object(
    'ok',true,
    'code',case when v_expired then 'TEMPORARY_PASSWORD_EXPIRED'
      when v_user.must_change_password then 'TEMPORARY_PASSWORD_MUST_CHANGE' else 'ACCESS_READY' end,
    'app_user_id',v_user.id,'role',v_user.role,'access_channel',v_user.access_channel,
    'email',v_user.email,'phone',v_user.phone,
    'login_email_enabled',v_user.login_email_enabled,
    'login_phone_enabled',v_user.login_phone_enabled,
    'contact_setup_complete',v_user.contact_setup_complete,
    'access_ready',v_user.access_ready,'must_change_password',v_user.must_change_password,
    'temporary_access_expires_at',v_user.temporary_access_expires_at,'expired',v_expired
  );
end;
$$;

create or replace function public.resolve_school_login_identity(p_identifier text,p_channel text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_channel text:=lower(btrim(coalesce(p_channel,'')));
  v_identifier text;
  v_user public.users%rowtype;
  v_auth_email text;
  v_identifier_key text;
begin
  if v_channel='email' then
    v_identifier:=lower(btrim(coalesce(p_identifier,'')));
    if v_identifier='' or v_identifier !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
      return jsonb_build_object('ok',false,'code','INVALID_CREDENTIALS');
    end if;
    select * into v_user from public.users
    where email=v_identifier and login_email_enabled and status='active' and access_ready limit 1;
  elsif v_channel in ('phone','phone_whatsapp') then
    v_identifier:=private.normalize_phone_e164(p_identifier);
    if v_identifier is null then return jsonb_build_object('ok',false,'code','INVALID_CREDENTIALS'); end if;
    select * into v_user from public.users
    where phone=v_identifier and login_phone_enabled and status='active' and access_ready limit 1;
    v_channel:='phone';
  else
    return jsonb_build_object('ok',false,'code','INVALID_CREDENTIALS');
  end if;
  if not found or v_user.auth_user_id is null then
    return jsonb_build_object('ok',false,'code','INVALID_CREDENTIALS');
  end if;
  select lower(email) into v_auth_email from auth.users where id=v_user.auth_user_id and deleted_at is null;
  if v_auth_email is null then return jsonb_build_object('ok',false,'code','INVALID_CREDENTIALS'); end if;
  v_identifier_key:=pg_catalog.encode(extensions.digest(v_channel||':'||v_identifier,'sha256'),'hex');
  return jsonb_build_object('ok',true,'auth_email',v_auth_email,'identifier_key',v_identifier_key);
end;
$$;

create or replace function private.guard_invitation_target_ready()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if exists(select 1 from public.users u where u.id=new.app_user_id and u.role='parent' and not u.access_ready) then
    raise exception 'PARENT_LINK_REQUIRED' using errcode='42501';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_invitation_target_ready on private.account_invitations;
create trigger trg_invitation_target_ready
before insert or update of app_user_id on private.account_invitations
for each row execute function private.guard_invitation_target_ready();

create or replace function private.guard_phone_request_target_ready()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if exists(select 1 from public.users u where u.id=new.app_user_id and u.role='parent' and not u.access_ready) then
    raise exception 'PARENT_LINK_REQUIRED' using errcode='42501';
  end if;
  return new;
end;
$$;
drop trigger if exists trg_phone_request_target_ready on private.parent_phone_access_requests;
create trigger trg_phone_request_target_ready
before insert or update of app_user_id on private.parent_phone_access_requests
for each row execute function private.guard_phone_request_target_ready();

create or replace function private.guard_auth_user_access_ready()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
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
$$;
drop trigger if exists before_auth_user_access_ready on auth.users;
create trigger before_auth_user_access_ready
before insert on auth.users
for each row execute function private.guard_auth_user_access_ready();

create or replace function public.set_student_primary_parent(p_sid text,p_parent_id text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_role text:=private.current_app_role();
  v_actor_id text:=private.current_app_user_id();
  v_actor_name text;
  s public.students%rowtype;
  p public.users%rowtype;
  v_parent_id text:=nullif(btrim(coalesce(p_parent_id,'')),'');
begin
  if v_role not in ('direction','direction2') then return jsonb_build_object('ok',false,'code','FORBIDDEN'); end if;
  select name into v_actor_name from public.users where id=v_actor_id and status='active';
  if not found then return jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); end if;
  select * into s from public.students where id=p_sid and not coalesce(archived,false) for update;
  if not found then return jsonb_build_object('ok',false,'code','STUDENT_NOT_FOUND'); end if;
  if v_parent_id is not null then
    select * into p from public.users where id=v_parent_id and role='parent' and status='active';
    if not found then return jsonb_build_object('ok',false,'code','PARENT_NOT_FOUND'); end if;
  end if;
  update public.students set pid=v_parent_id where id=s.id returning * into s;
  perform private.write_audit_event(v_actor_id,v_actor_name,'student_primary_parent_changed',
    jsonb_build_object('student_id',s.id,'new_parent_id',v_parent_id),s.id);
  return jsonb_build_object('ok',true,'code','PRIMARY_PARENT_UPDATED','student',to_jsonb(s));
end;
$$;

create or replace function public.save_primary_parent_pickup_identity(
  p_parent_id text,
  p_photo_portrait text,
  p_photo_full_body text,
  p_id_doc_type text,
  p_id_doc_last4 text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_role text:=private.current_app_role();
  v_actor_id text:=private.current_app_user_id();
  v_actor_name text;
  v_parent public.users%rowtype;
  v_portrait text:=nullif(btrim(coalesce(p_photo_portrait,'')),'');
  v_full text:=nullif(btrim(coalesce(p_photo_full_body,'')),'');
  v_doc_type text:=nullif(btrim(coalesce(p_id_doc_type,'')),'');
  v_doc_last4 text:=nullif(btrim(coalesce(p_id_doc_last4,'')),'');
begin
  if v_role not in ('direction','direction2') then return jsonb_build_object('ok',false,'code','FORBIDDEN'); end if;
  select name into v_actor_name from public.users where id=v_actor_id and status='active';
  if not found then return jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); end if;
  if v_portrait is null or lower(v_portrait) like 'data:%' or length(v_portrait)>2048 then
    return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','photo_portrait');
  end if;
  if v_full is null or lower(v_full) like 'data:%' or length(v_full)>2048 then
    return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','photo_full_body');
  end if;
  if v_doc_type is null or length(v_doc_type)>80 then
    return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','id_doc_type');
  end if;
  if v_doc_last4 is null or length(v_doc_last4) not between 2 and 12 then
    return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','id_doc_last4');
  end if;
  update public.users set photo_url=v_portrait,identity_full_body_photo_url=v_full,
    identity_document_type=v_doc_type,identity_document_last4=v_doc_last4,updated_at=now()
  where id=p_parent_id and role='parent' returning * into v_parent;
  if not found then return jsonb_build_object('ok',false,'code','PARENT_NOT_FOUND'); end if;
  perform private.write_audit_event(v_actor_id,v_actor_name,'primary_parent_pickup_identity_updated',
    jsonb_build_object('parent_id',v_parent.id,'has_portrait',true,'has_full_body',true),v_parent.id);
  return jsonb_build_object('ok',true,'code','PRIMARY_PARENT_IDENTITY_SAVED','parent',to_jsonb(v_parent));
end;
$$;

create or replace function public.suspend_school_account(p_app_user_id text,p_reason text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_role text:=private.current_app_role();
  v_actor_id text:=private.current_app_user_id();
  v_actor_name text;
  v_target public.users%rowtype;
  v_target_role text;
  v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
begin
  if v_role not in ('direction','direction2') then return jsonb_build_object('ok',false,'code','FORBIDDEN'); end if;
  if v_reason is null or length(v_reason)<5 then return jsonb_build_object('ok',false,'code','REASON_REQUIRED'); end if;
  select name into v_actor_name from public.users where id=v_actor_id and status='active';
  select * into v_target from public.users where id=p_app_user_id for update;
  if not found then return jsonb_build_object('ok',false,'code','TARGET_NOT_FOUND'); end if;
  if v_target.id=v_actor_id then return jsonb_build_object('ok',false,'code','CANNOT_SUSPEND_CURRENT_ACCOUNT'); end if;
  v_target_role:=case v_target.role when 'direction_pedagogique' then 'direction2' when 'caisse' then 'direction3' else v_target.role end;
  if v_role='direction2' and v_target_role not in ('direction2','enseignant','gardien','parent') then
    return jsonb_build_object('ok',false,'code','FORBIDDEN_TARGET_ROLE');
  end if;
  if v_target_role='direction' and not exists(
    select 1 from public.users u where u.id<>v_target.id and u.status='active' and u.auth_user_id is not null
      and (case u.role when 'direction_pedagogique' then 'direction2' when 'caisse' then 'direction3' else u.role end)='direction'
  ) then return jsonb_build_object('ok',false,'code','LAST_DIRECTION_ACCOUNT'); end if;
  update public.users set status='suspended',updated_at=now() where id=v_target.id returning * into v_target;
  if v_target.auth_user_id is not null then
    update public.profiles set status='suspended',updated_at=now() where id=v_target.auth_user_id;
  end if;
  perform private.write_audit_event(v_actor_id,v_actor_name,'school_account_suspended',
    jsonb_build_object('target_role',v_target_role,'reason',left(v_reason,500)),v_target.id);
  return jsonb_build_object('ok',true,'code','ACCOUNT_SUSPENDED','user',to_jsonb(v_target));
end;
$$;

create or replace function public.reactivate_school_account(p_app_user_id text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_role text:=private.current_app_role();
  v_actor_id text:=private.current_app_user_id();
  v_actor_name text;
  v_target public.users%rowtype;
  v_target_role text;
begin
  if v_role not in ('direction','direction2') then return jsonb_build_object('ok',false,'code','FORBIDDEN'); end if;
  select name into v_actor_name from public.users where id=v_actor_id and status='active';
  select * into v_target from public.users where id=p_app_user_id for update;
  if not found then return jsonb_build_object('ok',false,'code','TARGET_NOT_FOUND'); end if;
  v_target_role:=case v_target.role when 'direction_pedagogique' then 'direction2' when 'caisse' then 'direction3' else v_target.role end;
  if v_role='direction2' and v_target_role not in ('direction2','enseignant','gardien','parent') then
    return jsonb_build_object('ok',false,'code','FORBIDDEN_TARGET_ROLE');
  end if;
  update public.users set status='active',updated_at=now() where id=v_target.id returning * into v_target;
  perform private.refresh_parent_access_ready(v_target.id);
  select * into v_target from public.users where id=v_target.id;
  if v_target.auth_user_id is not null then
    update public.profiles set status='active',updated_at=now() where id=v_target.auth_user_id;
  end if;
  perform private.write_audit_event(v_actor_id,v_actor_name,'school_account_reactivated',
    jsonb_build_object('target_role',v_target_role,'access_ready',v_target.access_ready),v_target.id);
  return jsonb_build_object('ok',true,'code','ACCOUNT_REACTIVATED','user',to_jsonb(v_target));
end;
$$;

revoke all on function public.set_student_primary_parent(text,text) from public,anon;
grant execute on function public.set_student_primary_parent(text,text) to authenticated,service_role;
revoke all on function public.save_primary_parent_pickup_identity(text,text,text,text,text) from public,anon;
grant execute on function public.save_primary_parent_pickup_identity(text,text,text,text,text) to authenticated,service_role;
revoke all on function public.suspend_school_account(text,text) from public,anon;
grant execute on function public.suspend_school_account(text,text) to authenticated,service_role;
revoke all on function public.reactivate_school_account(text) from public,anon;
grant execute on function public.reactivate_school_account(text) to authenticated,service_role;

revoke all on function private.refresh_parent_access_ready(text) from public,anon,authenticated;
revoke all on function private.track_primary_parent_change() from public,anon,authenticated;
revoke all on function private.protect_primary_parent_history() from public,anon,authenticated;
revoke all on function private.guard_invitation_target_ready() from public,anon,authenticated;
revoke all on function private.guard_phone_request_target_ready() from public,anon,authenticated;
revoke all on function private.guard_auth_user_access_ready() from public,anon,authenticated;
grant execute on function private.refresh_parent_access_ready(text) to service_role;
grant execute on function private.track_primary_parent_change() to service_role;
grant execute on function private.protect_primary_parent_history() to service_role;
grant execute on function private.guard_invitation_target_ready() to service_role;
grant execute on function private.guard_phone_request_target_ready() to service_role;
grant execute on function private.guard_auth_user_access_ready() to service_role;