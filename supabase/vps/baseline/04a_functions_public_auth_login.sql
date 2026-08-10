-- SchoolSafe VPS baseline - 04a public auth/login RPCs

BEGIN;

CREATE OR REPLACE FUNCTION public.clear_school_login_attempts(p_key_hash text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  delete from private.school_login_rate_limits where key_hash = p_key_hash
$function$;

CREATE OR REPLACE FUNCTION public.consume_school_login_attempt(p_key_hash text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.resolve_school_login_identity(p_identifier text, p_channel text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.prepare_account_invitation(p_actor_auth_user_id uuid, p_app_user_id text, p_email text)
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
  v_email text:=lower(btrim(coalesce(p_email,'')));
  v_existing_auth_id uuid;
  v_existing_user_id text;
  v_invitation private.account_invitations%rowtype;
begin
  if p_actor_auth_user_id is null then return jsonb_build_object('ok',false,'code','AUTH_REQUIRED'); end if;
  select * into v_actor from public.users where auth_user_id=p_actor_auth_user_id and status='active' and access_ready limit 1;
  if not found then return jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); end if;
  v_actor_role:=case v_actor.role when 'direction_pedagogique' then 'direction2' when 'caisse' then 'direction3' else v_actor.role end;
  if v_actor_role not in ('direction','direction2') then return jsonb_build_object('ok',false,'code','FORBIDDEN'); end if;
  if nullif(btrim(coalesce(p_app_user_id,'')),'') is null then
    return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','app_user_id');
  end if;
  if v_email='' or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','email');
  end if;
  select * into v_target from public.users where id=p_app_user_id for update;
  if not found then return jsonb_build_object('ok',false,'code','TARGET_NOT_FOUND'); end if;
  v_target_role:=case v_target.role when 'direction_pedagogique' then 'direction2' when 'caisse' then 'direction3' when 'enseignant_maternelle' then 'enseignant' else v_target.role end;
  if v_target_role not in ('direction','direction2','direction3','enseignant','parent','gardien') then
    return jsonb_build_object('ok',false,'code','UNSUPPORTED_ROLE');
  end if;
  if v_actor_role='direction2' and v_target_role not in ('direction2','enseignant','gardien','parent') then
    return jsonb_build_object('ok',false,'code','FORBIDDEN_TARGET_ROLE');
  end if;
  if v_target.status<>'active' then return jsonb_build_object('ok',false,'code','TARGET_DISABLED'); end if;
  if not v_target.access_ready then return jsonb_build_object('ok',false,'code',coalesce(v_target.access_block_reason,'ACCESS_NOT_READY')); end if;
  if v_target.email is null then return jsonb_build_object('ok',false,'code','EMAIL_REQUIRED'); end if;
  if not v_target.login_email_enabled then return jsonb_build_object('ok',false,'code','EMAIL_LOGIN_DISABLED'); end if;
  if v_target.email is distinct from v_email then return jsonb_build_object('ok',false,'code','EMAIL_PROFILE_MISMATCH'); end if;
  if v_target.auth_user_id is not null then return jsonb_build_object('ok',false,'code','ALREADY_LINKED','app_user_id',v_target.id); end if;
  select id into v_existing_user_id from public.users where id<>v_target.id and email=v_email limit 1;
  if found then return jsonb_build_object('ok',false,'code','EMAIL_IN_USE'); end if;
  select id into v_existing_auth_id from auth.users where email is not null and lower(btrim(email))=v_email limit 1;
  if found then return jsonb_build_object('ok',false,'code','EMAIL_IN_USE'); end if;
  select * into v_invitation from private.account_invitations where lower(email)=v_email limit 1;
  if found and v_invitation.app_user_id is distinct from v_target.id and v_invitation.accepted_at is null then
    return jsonb_build_object('ok',false,'code','EMAIL_IN_USE');
  end if;
  insert into private.account_invitations(
    email,full_name,role,invited_at,expires_at,accepted_at,auth_user_id,app_user_id,invited_by
  ) values(v_email,v_target.name,v_target.role,now(),now()+interval '3 days',null,null,v_target.id,v_actor.id)
  on conflict(email) do update set full_name=excluded.full_name,role=excluded.role,
    invited_at=excluded.invited_at,expires_at=excluded.expires_at,accepted_at=null,
    auth_user_id=null,app_user_id=excluded.app_user_id,invited_by=excluded.invited_by
  returning * into v_invitation;
  update public.users set invitation_sent_at=now(),updated_at=now() where id=v_target.id;
  perform private.write_audit_event(v_actor.id,v_actor.name,'account_invitation_prepared',
    jsonb_build_object('email',v_email,'role',v_target.role,'invitation_id',v_invitation.id),v_target.id);
  return jsonb_build_object('ok',true,'code','INVITATION_PREPARED','invitation_id',v_invitation.id,
    'app_user_id',v_target.id,'email',v_email,'full_name',v_target.name,'role',v_target.role,
    'expires_at',v_invitation.expires_at);
exception
  when unique_violation then return jsonb_build_object('ok',false,'code','INVITATION_CONFLICT');
  when foreign_key_violation then return jsonb_build_object('ok',false,'code','REFERENCE_NOT_FOUND');
end;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_account_invitation(p_actor_auth_user_id uuid, p_invitation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor public.users%rowtype;
  v_invitation private.account_invitations%rowtype;
begin
  if p_actor_auth_user_id is null or p_invitation_id is null then
    return jsonb_build_object('ok',false,'code','VALIDATION_ERROR');
  end if;
  select * into v_actor from public.users where auth_user_id=p_actor_auth_user_id and status='active' limit 1;
  if not found or v_actor.role<>'direction' then return jsonb_build_object('ok',false,'code','FORBIDDEN'); end if;

  select * into v_invitation from private.account_invitations where id=p_invitation_id limit 1;
  if not found then return jsonb_build_object('ok',true,'code','NOTHING_TO_CANCEL'); end if;
  if v_invitation.accepted_at is not null then return jsonb_build_object('ok',true,'code','ALREADY_ACCEPTED'); end if;

  delete from private.account_invitations where id=v_invitation.id and accepted_at is null;
  update public.users set invitation_sent_at=null,updated_at=now()
  where id=v_invitation.app_user_id and auth_user_id is null;

  perform private.write_audit_event(
    v_actor.id,v_actor.name,'account_invitation_cancelled',
    jsonb_build_object('email',v_invitation.email,'invitation_id',v_invitation.id),
    v_invitation.app_user_id
  );

  return jsonb_build_object('ok',true,'code','INVITATION_CANCELLED');
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_school_user_profile(p_user jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select private.save_school_user_profile_dual_impl(p_user)
$function$;

CREATE OR REPLACE FUNCTION public.save_school_user_profile_email(p_user jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select private.save_school_user_profile_dual_impl(p_user)
$function$;

COMMIT;
