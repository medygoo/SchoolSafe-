-- SchoolSafe VPS baseline - 04c account lifecycle RPCs

BEGIN;

CREATE OR REPLACE FUNCTION public.prepare_school_account_removal(p_actor_auth_user_id uuid, p_app_user_id text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  if not found then return jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); end if;

  v_actor_role := case v_actor.role
    when 'direction_pedagogique' then 'direction2'
    when 'caisse' then 'direction3'
    else v_actor.role
  end;
  if v_actor_role<>'direction' then return jsonb_build_object('ok',false,'code','FORBIDDEN'); end if;

  select * into v_target from public.users where id=p_app_user_id for update;
  if not found then return jsonb_build_object('ok',false,'code','TARGET_NOT_FOUND'); end if;
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
    update public.profiles set status='inactive',updated_at=v_now where id=v_auth_user_id;
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
$function$;

CREATE OR REPLACE FUNCTION public.confirm_school_account_removal(p_actor_auth_user_id uuid, p_app_user_id text, p_expected_auth_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor public.users%rowtype;
  v_target public.users%rowtype;
begin
  select * into v_actor from public.users
  where auth_user_id=p_actor_auth_user_id and status='active'
  limit 1;
  if not found or v_actor.role<>'direction' then return jsonb_build_object('ok',false,'code','FORBIDDEN'); end if;

  select * into v_target from public.users where id=p_app_user_id limit 1;
  if not found then return jsonb_build_object('ok',false,'code','TARGET_NOT_FOUND'); end if;
  if v_target.auth_user_id is not null then return jsonb_build_object('ok',false,'code','AUTH_IDENTITY_STILL_PRESENT'); end if;

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
$function$;

CREATE OR REPLACE FUNCTION public.suspend_school_account(p_app_user_id text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.reactivate_school_account(p_app_user_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

COMMIT;
