-- SchoolSafe VPS baseline - 03d parent/identity/audit helpers

BEGIN;

CREATE OR REPLACE FUNCTION private.parent_has_child_in_class(p_cid text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(
    private.current_app_role() = 'parent'
    and exists (
      select 1
      from public.students s
      where s.cid = p_cid
        and s.pid = private.current_app_user_id()
        and coalesce(s.archived, false) = false
        and coalesce(s.access_parent, true) = true
    ),
    false
  )
$function$;

CREATE OR REPLACE FUNCTION private.enforce_max_three_accredited_people()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_count integer;
begin
  if new.approval_status = 'approved' and new.active then
    perform pg_advisory_xact_lock(hashtext('aps:' || coalesce(new.sid, '')));
    select count(*) into v_count
    from public.aps a
    where a.sid = new.sid
      and a.approval_status = 'approved'
      and a.active
      and a.id is distinct from new.id;
    if v_count >= 3 then
      raise exception 'Maximum de trois personnes accréditées atteint';
    end if;
  end if;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION private.refresh_parent_access_ready(p_parent_id text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION private.track_primary_parent_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION private.protect_primary_parent_history()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  raise exception 'L historique du parent principal est immuable.' using errcode='23514';
end;
$function$;

CREATE OR REPLACE FUNCTION private.protect_profile_identity_fields()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
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
$function$;

CREATE OR REPLACE FUNCTION private.write_audit_event(p_by text, p_by_name text, p_action text, p_detail jsonb, p_target_id text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  insert into public.audit_log(id,by,by_name,action,detail,target_id,date,time)
  values(
    'audit_'||replace(gen_random_uuid()::text,'-',''),
    p_by,
    p_by_name,
    p_action,
    coalesce(p_detail,'{}'::jsonb)::text,
    p_target_id,
    to_char(timezone('Africa/Kinshasa',now()),'YYYY-MM-DD'),
    to_char(timezone('Africa/Kinshasa',now()),'HH24:MI:SS')
  )
$function$;

COMMIT;
