-- SchoolSafe P0-13 — DRAFT ONLY
-- Permanent account removal must never be reversible through suspend/reactivate.
-- This file is NOT a production migration and ends with ROLLBACK deliberately.

begin;

create or replace function public.suspend_school_account(
  p_app_user_id text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_role text:=private.current_app_role();
  v_actor_id text:=private.current_app_user_id();
  v_actor_name text;
  v_target public.users%rowtype;
  v_target_role text;
  v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
begin
  if v_role not in ('direction','direction2') then
    return jsonb_build_object('ok',false,'code','FORBIDDEN');
  end if;
  if v_reason is null or length(v_reason)<5 then
    return jsonb_build_object('ok',false,'code','REASON_REQUIRED');
  end if;

  select name into v_actor_name
  from public.users
  where id=v_actor_id and status='active';

  select * into v_target
  from public.users
  where id=p_app_user_id
  for update;

  if not found then
    return jsonb_build_object('ok',false,'code','TARGET_NOT_FOUND');
  end if;

  -- A permanent removal is an irreversible lifecycle state even though the
  -- legacy status column remains 'inactive'. Do not let UI/API callers turn it
  -- into another reversible state.
  if v_target.access_removed_at is not null
     or v_target.removed_auth_user_id is not null then
    return jsonb_build_object('ok',false,'code','ACCOUNT_ACCESS_REMOVED');
  end if;

  if v_target.id=v_actor_id then
    return jsonb_build_object('ok',false,'code','CANNOT_SUSPEND_CURRENT_ACCOUNT');
  end if;

  v_target_role:=case v_target.role
    when 'direction_pedagogique' then 'direction2'
    when 'caisse' then 'direction3'
    else v_target.role
  end;

  if v_role='direction2'
     and v_target_role not in ('direction2','enseignant','gardien','parent') then
    return jsonb_build_object('ok',false,'code','FORBIDDEN_TARGET_ROLE');
  end if;

  if v_target_role='direction' and not exists(
    select 1
    from public.users u
    where u.id<>v_target.id
      and u.status='active'
      and u.auth_user_id is not null
      and (case u.role
        when 'direction_pedagogique' then 'direction2'
        when 'caisse' then 'direction3'
        else u.role end)='direction'
  ) then
    return jsonb_build_object('ok',false,'code','LAST_DIRECTION_ACCOUNT');
  end if;

  update public.users
  set status='suspended',updated_at=now()
  where id=v_target.id
  returning * into v_target;

  if v_target.auth_user_id is not null then
    update public.profiles
    set status='suspended',updated_at=now()
    where id=v_target.auth_user_id;
  end if;

  perform private.write_audit_event(
    v_actor_id,v_actor_name,'school_account_suspended',
    jsonb_build_object('target_role',v_target_role,'reason',left(v_reason,500)),
    v_target.id
  );

  return jsonb_build_object(
    'ok',true,
    'code','ACCOUNT_SUSPENDED',
    'user',to_jsonb(v_target)
  );
end;
$function$;

create or replace function public.reactivate_school_account(
  p_app_user_id text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_role text:=private.current_app_role();
  v_actor_id text:=private.current_app_user_id();
  v_actor_name text;
  v_target public.users%rowtype;
  v_target_role text;
begin
  if v_role not in ('direction','direction2') then
    return jsonb_build_object('ok',false,'code','FORBIDDEN');
  end if;

  select name into v_actor_name
  from public.users
  where id=v_actor_id and status='active';

  select * into v_target
  from public.users
  where id=p_app_user_id
  for update;

  if not found then
    return jsonb_build_object('ok',false,'code','TARGET_NOT_FOUND');
  end if;

  -- Permanent removal must never be reversed by this RPC. A new account, if
  -- ever justified, must follow the normal explicit account-creation process.
  if v_target.access_removed_at is not null
     or v_target.removed_auth_user_id is not null then
    return jsonb_build_object('ok',false,'code','ACCOUNT_ACCESS_REMOVED');
  end if;

  v_target_role:=case v_target.role
    when 'direction_pedagogique' then 'direction2'
    when 'caisse' then 'direction3'
    else v_target.role
  end;

  if v_role='direction2'
     and v_target_role not in ('direction2','enseignant','gardien','parent') then
    return jsonb_build_object('ok',false,'code','FORBIDDEN_TARGET_ROLE');
  end if;

  update public.users
  set status='active',updated_at=now()
  where id=v_target.id
  returning * into v_target;

  perform private.refresh_parent_access_ready(v_target.id);
  select * into v_target from public.users where id=v_target.id;

  if v_target.auth_user_id is not null then
    update public.profiles
    set status='active',updated_at=now()
    where id=v_target.auth_user_id;
  end if;

  perform private.write_audit_event(
    v_actor_id,v_actor_name,'school_account_reactivated',
    jsonb_build_object('target_role',v_target_role,'access_ready',v_target.access_ready),
    v_target.id
  );

  return jsonb_build_object(
    'ok',true,
    'code','ACCOUNT_REACTIVATED',
    'user',to_jsonb(v_target)
  );
end;
$function$;

rollback;
