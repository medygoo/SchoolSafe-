-- SchoolSafe VPS baseline - 04b phone access RPCs

BEGIN;

CREATE OR REPLACE FUNCTION public.prepare_parent_phone_access(p_actor_auth_user_id uuid, p_app_user_id text, p_action text, p_phone text DEFAULT NULL::text)
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
  v_action text:=lower(btrim(coalesce(p_action,'')));
  v_phone text;
  v_auth_email text;
  v_request private.parent_phone_access_requests%rowtype;
  v_next_allowed timestamptz;
begin
  if p_actor_auth_user_id is null then return jsonb_build_object('ok',false,'code','AUTH_REQUIRED'); end if;
  select * into v_actor from public.users where auth_user_id=p_actor_auth_user_id and status='active' and access_ready limit 1;
  if not found then return jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); end if;
  v_actor_role:=case v_actor.role when 'direction_pedagogique' then 'direction2' when 'caisse' then 'direction3' else v_actor.role end;
  if v_actor_role not in ('direction','direction2') then return jsonb_build_object('ok',false,'code','FORBIDDEN'); end if;
  if v_action not in ('provision','reset','change_phone') then
    return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','action');
  end if;
  select * into v_target from public.users where id=p_app_user_id for update;
  if not found then return jsonb_build_object('ok',false,'code','TARGET_NOT_FOUND'); end if;
  v_target_role:=case v_target.role when 'direction_pedagogique' then 'direction2' when 'caisse' then 'direction3' when 'enseignant_maternelle' then 'enseignant' else v_target.role end;
  if v_target_role not in ('direction','direction2','direction3','enseignant','gardien','parent') then
    return jsonb_build_object('ok',false,'code','TARGET_NOT_PHONE_ACCOUNT');
  end if;
  if v_actor_role='direction2' and v_target_role not in ('direction2','enseignant','gardien','parent') then
    return jsonb_build_object('ok',false,'code','FORBIDDEN_TARGET_ROLE');
  end if;
  if v_target.status<>'active' then return jsonb_build_object('ok',false,'code','TARGET_DISABLED'); end if;
  if not v_target.access_ready then return jsonb_build_object('ok',false,'code',coalesce(v_target.access_block_reason,'ACCESS_NOT_READY')); end if;
  if v_target.phone is null then return jsonb_build_object('ok',false,'code','PHONE_REQUIRED'); end if;
  if not v_target.login_phone_enabled then return jsonb_build_object('ok',false,'code','PHONE_LOGIN_DISABLED'); end if;
  v_phone:=case when v_action='change_phone' then private.normalize_phone_e164(p_phone) else private.normalize_phone_e164(v_target.phone) end;
  if v_phone is null then return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','phone'); end if;
  if v_action='provision' and v_target.auth_user_id is not null then return jsonb_build_object('ok',false,'code','ALREADY_LINKED'); end if;
  if v_action in ('reset','change_phone') and v_target.auth_user_id is null then return jsonb_build_object('ok',false,'code','ACCOUNT_NOT_LINKED'); end if;
  if exists(select 1 from public.users where id<>v_target.id and phone=v_phone) then return jsonb_build_object('ok',false,'code','PHONE_IN_USE'); end if;
  v_auth_email:=coalesce(v_target.email,private.phone_auth_email(v_phone));
  if exists(select 1 from auth.users where lower(email)=v_auth_email and id is distinct from v_target.auth_user_id) then
    return jsonb_build_object('ok',false,'code','EMAIL_IN_USE');
  end if;
  select created_at+interval '60 seconds' into v_next_allowed from private.parent_phone_access_requests
  where app_user_id=v_target.id and created_at>now()-interval '60 seconds' order by created_at desc limit 1;
  if found then return jsonb_build_object('ok',false,'code','TOO_SOON','next_allowed_at',v_next_allowed); end if;
  update private.parent_phone_access_requests set
    status=case when expires_at<=now() then 'expired' else 'failed' end,
    failed_at=now(),failure_code=case when expires_at<=now() then 'EXPIRED_REPLACED' else 'REPLACED' end
  where app_user_id=v_target.id and status in ('prepared','auth_linked','ready');
  insert into private.parent_phone_access_requests(app_user_id,phone,action,requested_by,auth_user_id)
  values(v_target.id,v_phone,v_action,v_actor.id,case when v_action='provision' then null else v_target.auth_user_id end)
  returning * into v_request;
  perform private.write_audit_event(v_actor.id,v_actor.name,'phone_access_prepared',
    jsonb_build_object('app_user_id',v_target.id,'role',v_target_role,'action',v_action,'expires_at',v_request.expires_at),v_target.id);
  return jsonb_build_object('ok',true,'code','PHONE_ACCESS_PREPARED','request_id',v_request.id,
    'request_secret',v_request.secret,'app_user_id',v_target.id,'phone',v_phone,'auth_email',v_auth_email,
    'action',v_action,'auth_user_id',v_request.auth_user_id,'expires_at',v_request.expires_at);
exception when unique_violation then return jsonb_build_object('ok',false,'code','PHONE_ACCESS_CONFLICT');
end;
$function$;

CREATE OR REPLACE FUNCTION public.finalize_parent_phone_access(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.confirm_parent_phone_password_change()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.fail_parent_phone_access_request(p_request_id uuid, p_failure_code text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_request private.parent_phone_access_requests%rowtype;
begin
  select * into v_request from private.parent_phone_access_requests where id=p_request_id for update;
  if not found then return jsonb_build_object('ok',true,'code','REQUEST_NOT_FOUND'); end if;
  update private.parent_phone_access_requests set status='failed',failed_at=now(),failure_code=left(coalesce(nullif(btrim(p_failure_code),''),'UNKNOWN'),100)
  where id=p_request_id and status in ('prepared','auth_linked');
  if found then
    perform private.write_audit_event(v_request.requested_by,(select name from public.users where id=v_request.requested_by),'parent_phone_access_failed',jsonb_build_object('app_user_id',v_request.app_user_id,'action',v_request.action,'failure_code',left(coalesce(nullif(btrim(p_failure_code),''),'UNKNOWN'),100)),v_request.app_user_id);
  end if;
  return jsonb_build_object('ok',true,'code','REQUEST_FAILED');
end;
$function$;

CREATE OR REPLACE FUNCTION public.expire_parent_phone_access_requests()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_count integer;
begin
  update private.parent_phone_access_requests
  set status='expired',failed_at=coalesce(failed_at,now()),failure_code=coalesce(failure_code,'EXPIRED')
  where status in ('prepared','auth_linked','ready') and expires_at<=now();
  get diagnostics v_count=row_count;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_parent_phone_access_request_status(p_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_request private.parent_phone_access_requests%rowtype;
begin
  select * into v_request from private.parent_phone_access_requests where id=p_request_id;
  if not found then return jsonb_build_object('ok',false,'code','REQUEST_NOT_FOUND'); end if;
  return jsonb_build_object('ok',true,'code','REQUEST_STATUS','status',v_request.status,'app_user_id',v_request.app_user_id,'action',v_request.action,'expires_at',v_request.expires_at,'ready_at',v_request.ready_at,'completed_at',v_request.completed_at,'failure_code',v_request.failure_code);
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_parent_phone_profile(p_user jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.get_my_access_state()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

COMMIT;
