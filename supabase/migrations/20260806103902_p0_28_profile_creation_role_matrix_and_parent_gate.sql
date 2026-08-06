-- P0-28: final profile role matrix and parent access gate.

create or replace function private.enforce_parent_access_ready_on_user()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
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
$$;

drop trigger if exists trg_users_parent_access_ready on public.users;
create trigger trg_users_parent_access_ready
before insert or update of role on public.users
for each row execute function private.enforce_parent_access_ready_on_user();

create or replace function private.save_school_user_profile_dual_impl(p_user jsonb)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
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
$$;

create or replace function public.prepare_account_invitation(
  p_actor_auth_user_id uuid,p_app_user_id text,p_email text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
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
$$;

create or replace function public.prepare_parent_phone_access(
  p_actor_auth_user_id uuid,p_app_user_id text,p_action text,p_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
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
$$;

revoke all on function private.enforce_parent_access_ready_on_user() from public,anon,authenticated;
grant execute on function private.enforce_parent_access_ready_on_user() to service_role;