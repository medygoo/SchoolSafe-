-- SchoolSafe VPS baseline - 03c profile creation/update contract

BEGIN;

CREATE OR REPLACE FUNCTION private.save_school_user_profile_dual_impl(p_user jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor_id text:=private.current_app_user_id();
  v_actor_role text:=private.current_app_role();
  v_id text:=btrim(coalesce(p_user->>'id',''));
  v_exists boolean;
  v_current public.users%rowtype;
  v_saved public.users%rowtype;
  v_name text;
  v_role text;
  v_current_role text;
  v_initials text;
  v_phone_raw text;
  v_phone text;
  v_photo_url text;
  v_email text;
  v_status text;
  v_access_channel text;
begin
  if p_user is null or jsonb_typeof(p_user)<>'object' then
    return jsonb_build_object('ok',false,'code','INVALID_PAYLOAD');
  end if;
  if v_actor_role not in ('direction','direction2') then
    return jsonb_build_object('ok',false,'code','FORBIDDEN');
  end if;
  if v_id='' or length(v_id)>160 then
    return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','id');
  end if;

  select exists(select 1 from public.users where id=v_id) into v_exists;
  if v_exists then select * into v_current from public.users where id=v_id for update; end if;

  v_role:=case coalesce(nullif(btrim(p_user->>'role'),''),case when v_exists then v_current.role else null end)
    when 'direction_pedagogique' then 'direction2'
    when 'caisse' then 'direction3'
    when 'enseignant_maternelle' then 'enseignant'
    else coalesce(nullif(btrim(p_user->>'role'),''),case when v_exists then v_current.role else null end)
  end;
  v_current_role:=case when v_exists then case v_current.role
    when 'direction_pedagogique' then 'direction2'
    when 'caisse' then 'direction3'
    when 'enseignant_maternelle' then 'enseignant'
    else v_current.role end else null end;

  if v_role not in ('direction','direction2','direction3','enseignant','gardien','parent') then
    return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','role');
  end if;
  if v_actor_role='direction2' and v_role not in ('direction2','enseignant','gardien','parent') then
    return jsonb_build_object('ok',false,'code','FORBIDDEN_TARGET_ROLE');
  end if;
  if v_actor_role='direction2' and v_exists and v_current_role not in ('direction2','enseignant','gardien','parent') then
    return jsonb_build_object('ok',false,'code','FORBIDDEN_TARGET_ROLE');
  end if;

  v_name:=case when p_user?'name' then nullif(btrim(coalesce(p_user->>'name','')),'') when v_exists then v_current.name else null end;
  v_initials:=case when p_user?'initials' then nullif(btrim(coalesce(p_user->>'initials','')),'') when v_exists then v_current.initials else null end;
  v_phone_raw:=case when p_user?'phone' then nullif(btrim(coalesce(p_user->>'phone','')),'') when v_exists then v_current.phone else null end;
  v_phone:=case when v_phone_raw is null then null else private.normalize_phone_e164(v_phone_raw) end;
  v_photo_url:=case when p_user?'photo_url' then nullif(btrim(coalesce(p_user->>'photo_url','')),'') when v_exists then v_current.photo_url else null end;
  v_email:=case when p_user?'email' then nullif(lower(btrim(coalesce(p_user->>'email',''))),'') when v_exists then v_current.email else null end;
  v_status:=case when p_user?'status' then nullif(btrim(coalesce(p_user->>'status','')),'') when v_exists then v_current.status else 'active' end;
  if v_status='disabled' then v_status:='inactive'; end if;

  if v_name is null or length(v_name)>200 then
    return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','name');
  end if;
  if v_email is not null and (length(v_email)>320 or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') then
    return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','email');
  end if;
  if v_phone_raw is not null and v_phone is null then
    return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','phone');
  end if;
  if v_email is null and v_phone is null then return jsonb_build_object('ok',false,'code','CONTACT_REQUIRED'); end if;

  v_access_channel:=case
    when p_user?'access_channel' then nullif(lower(btrim(coalesce(p_user->>'access_channel',''))),'')
    when v_exists and ((v_current.access_channel='email' and v_email is not null)
      or (v_current.access_channel='phone_whatsapp' and v_phone is not null)) then v_current.access_channel
    when v_email is not null and v_phone is null then 'email'
    when v_phone is not null and v_email is null then 'phone_whatsapp'
    when v_role='direction' then 'email'
    else 'phone_whatsapp'
  end;

  if v_status not in ('active','inactive','suspended') then
    return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','status');
  end if;
  if v_access_channel not in ('email','phone_whatsapp') then
    return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','access_channel');
  end if;
  if (v_access_channel='email' and v_email is null) or (v_access_channel='phone_whatsapp' and v_phone is null) then
    return jsonb_build_object('ok',false,'code','PRIMARY_CONTACT_UNAVAILABLE','field','access_channel');
  end if;
  if length(coalesce(v_initials,''))>20 then return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','initials'); end if;
  if length(coalesce(v_photo_url,''))>2048 then return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','photo_url'); end if;
  if v_photo_url is not null and lower(v_photo_url) like 'data:%' then
    return jsonb_build_object('ok',false,'code','PHOTO_MUST_BE_FILE_REFERENCE');
  end if;

  if v_email is not null and exists(select 1 from public.users where id<>v_id and email=v_email) then
    return jsonb_build_object('ok',false,'code','EMAIL_IN_USE');
  end if;
  if v_phone is not null and exists(select 1 from public.users where id<>v_id and phone=v_phone) then
    return jsonb_build_object('ok',false,'code','PHONE_IN_USE');
  end if;

  if v_exists and v_actor_role='direction2' and (
    v_current.email is distinct from v_email
    or v_current.phone is distinct from v_phone
    or v_current_role is distinct from v_role
  ) then
    return jsonb_build_object('ok',false,'code','DIRECTION1_REQUIRED_FOR_IDENTITY_CHANGE');
  end if;

  if v_exists and v_current.auth_user_id is not null then
    if v_current.email is distinct from v_email then return jsonb_build_object('ok',false,'code','AUTH_EMAIL_CHANGE_REQUIRED'); end if;
    if v_current.phone is distinct from v_phone then return jsonb_build_object('ok',false,'code','AUTH_PHONE_CHANGE_REQUIRED'); end if;
    if v_current_role is distinct from v_role then return jsonb_build_object('ok',false,'code','AUTH_ROLE_CHANGE_REQUIRED'); end if;
  end if;
  if v_exists and v_id=v_actor_id and v_status<>'active' then
    return jsonb_build_object('ok',false,'code','CANNOT_DISABLE_CURRENT_ACCOUNT');
  end if;

  if v_exists then
    update public.users set
      name=v_name,role=v_role,initials=v_initials,phone=v_phone,photo_url=v_photo_url,
      email=v_email,status=v_status,access_channel=v_access_channel,
      login_email_enabled=(v_email is not null),login_phone_enabled=(v_phone is not null),updated_at=now()
    where id=v_id returning * into v_saved;
  else
    insert into public.users(
      id,name,role,initials,phone,photo_url,email,status,access_channel,
      login_email_enabled,login_phone_enabled
    ) values(
      v_id,v_name,v_role,v_initials,v_phone,v_photo_url,v_email,v_status,v_access_channel,
      (v_email is not null),(v_phone is not null)
    ) returning * into v_saved;
  end if;

  if v_saved.auth_user_id is not null then
    perform set_config('schoolsafe.profile_sync_target',v_saved.auth_user_id::text,true);
    update public.profiles set email=v_saved.email,phone=v_saved.phone,full_name=v_saved.name,
      role=v_saved.role,status=v_saved.status,updated_at=now()
    where id=v_saved.auth_user_id;
    perform set_config('schoolsafe.profile_sync_target','',true);
  end if;

  perform private.write_audit_event(
    v_actor_id,(select name from public.users where id=v_actor_id),
    case when v_exists then 'contact_profile_updated' else 'contact_profile_created' end,
    jsonb_build_object('app_user_id',v_saved.id,'role',v_saved.role,
      'access_channel',v_saved.access_channel,'email_enabled',v_saved.login_email_enabled,
      'phone_enabled',v_saved.login_phone_enabled,'contact_setup_complete',v_saved.contact_setup_complete,
      'access_ready',v_saved.access_ready,'access_block_reason',v_saved.access_block_reason),v_saved.id
  );

  return jsonb_build_object(
    'ok',true,
    'code',case when not v_exists and v_saved.role='parent' and not v_saved.access_ready
      then 'PARENT_PROFILE_CREATED_LINK_REQUIRED'
      when v_exists then 'USER_UPDATED' else 'USER_CREATED' end,
    'requires_provisioning',(v_saved.auth_user_id is null and v_saved.access_ready),
    'requires_invitation',(v_saved.auth_user_id is null and v_saved.email is not null and v_saved.access_ready),
    'requires_phone_provisioning',(v_saved.auth_user_id is null and v_saved.phone is not null and v_saved.access_ready),
    'access_ready',v_saved.access_ready,'access_block_reason',v_saved.access_block_reason,
    'user',to_jsonb(v_saved)
  );
exception
  when unique_violation then return jsonb_build_object('ok',false,'code','DUPLICATE_USER');
  when foreign_key_violation then return jsonb_build_object('ok',false,'code','REFERENCE_NOT_FOUND');
  when check_violation or not_null_violation then return jsonb_build_object('ok',false,'code','VALIDATION_ERROR');
end;
$function$;

COMMIT;
