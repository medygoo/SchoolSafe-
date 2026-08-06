create or replace function public.save_parent_phone_profile(p_user jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id text;
  v_actor_role text;
  v_id text := btrim(coalesce(p_user->>'id', ''));
  v_exists boolean;
  v_current public.users%rowtype;
  v_saved public.users%rowtype;
  v_name text;
  v_initials text;
  v_phone text;
  v_photo_url text;
  v_email text;
  v_status text;
  v_existing_auth_phone uuid;
begin
  if p_user is null or jsonb_typeof(p_user) <> 'object' then return jsonb_build_object('ok', false, 'code', 'INVALID_PAYLOAD'); end if;
  v_actor_id := private.current_app_user_id();
  v_actor_role := private.current_app_role();
  if v_actor_role not in ('direction', 'direction2') then return jsonb_build_object('ok', false, 'code', 'FORBIDDEN'); end if;
  if v_id = '' or length(v_id) > 160 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'id'); end if;

  select exists(select 1 from public.users where id = v_id) into v_exists;
  if v_exists then
    select * into v_current from public.users where id = v_id for update;
    if v_current.role <> 'parent' then return jsonb_build_object('ok', false, 'code', 'TARGET_ROLE_MISMATCH'); end if;
  end if;

  v_name := case when p_user ? 'name' then nullif(btrim(coalesce(p_user->>'name', '')), '') when v_exists then v_current.name else null end;
  v_initials := case when p_user ? 'initials' then nullif(btrim(coalesce(p_user->>'initials', '')), '') when v_exists then v_current.initials else null end;
  v_phone := case when p_user ? 'phone' then private.normalize_phone_e164(p_user->>'phone') when v_exists then v_current.phone else null end;
  v_photo_url := case when p_user ? 'photo_url' then nullif(btrim(coalesce(p_user->>'photo_url', '')), '') when v_exists then v_current.photo_url else null end;
  v_email := case when p_user ? 'email' then nullif(lower(btrim(coalesce(p_user->>'email', ''))), '') when v_exists then v_current.email else null end;
  v_status := case when p_user ? 'status' then nullif(btrim(coalesce(p_user->>'status', '')), '') when v_exists then v_current.status else 'active' end;
  if v_status = 'disabled' then v_status := 'inactive'; end if;

  if v_name is null or length(v_name) > 200 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'name'); end if;
  if v_phone is null then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'phone'); end if;
  if v_status not in ('active', 'inactive', 'suspended') then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'status'); end if;
  if length(coalesce(v_initials, '')) > 20 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'initials'); end if;
  if length(coalesce(v_photo_url, '')) > 2048 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'photo_url'); end if;
  if v_photo_url is not null and lower(v_photo_url) like 'data:%' then return jsonb_build_object('ok', false, 'code', 'PHOTO_MUST_BE_FILE_REFERENCE'); end if;
  if v_email is not null and (length(v_email) > 320 or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'email'); end if;

  if exists(select 1 from public.users where id <> v_id and phone = v_phone) then return jsonb_build_object('ok', false, 'code', 'PHONE_IN_USE'); end if;
  if v_email is not null and exists(select 1 from public.users where id <> v_id and email = v_email) then return jsonb_build_object('ok', false, 'code', 'EMAIL_IN_USE'); end if;
  select id into v_existing_auth_phone from auth.users where phone = v_phone and (not v_exists or id is distinct from v_current.auth_user_id) limit 1;
  if found then return jsonb_build_object('ok', false, 'code', 'PHONE_IN_USE'); end if;
  if v_exists and v_current.auth_user_id is not null and v_current.phone is distinct from v_phone then return jsonb_build_object('ok', false, 'code', 'AUTH_PHONE_CHANGE_REQUIRED'); end if;

  if v_exists then
    update public.users set name=v_name, role='parent', initials=v_initials, phone=v_phone, photo_url=v_photo_url, email=v_email, status=v_status, access_channel='phone_whatsapp', updated_at=now()
    where id=v_id returning * into v_saved;
  else
    insert into public.users(id,name,role,initials,phone,photo_url,email,status,access_channel)
    values(v_id,v_name,'parent',v_initials,v_phone,v_photo_url,v_email,v_status,'phone_whatsapp') returning * into v_saved;
  end if;

  if v_saved.auth_user_id is not null then
    update public.profiles set email=v_saved.email, phone=v_saved.phone, full_name=v_saved.name, status=v_saved.status, updated_at=now() where id=v_saved.auth_user_id;
  end if;
  perform private.write_audit_event(v_actor_id,(select name from public.users where id=v_actor_id),case when v_exists then 'parent_phone_profile_updated' else 'parent_phone_profile_created' end,jsonb_build_object('app_user_id',v_saved.id,'access_channel','phone_whatsapp'),v_saved.id);
  return jsonb_build_object('ok',true,'code',case when v_exists then 'USER_UPDATED' else 'USER_CREATED' end,'requires_phone_provisioning',(v_saved.auth_user_id is null),'user',to_jsonb(v_saved));
exception
  when unique_violation then return jsonb_build_object('ok', false, 'code', 'DUPLICATE_USER');
  when check_violation or not_null_violation then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR');
end;
$$;

create or replace function public.prepare_parent_phone_access(p_actor_auth_user_id uuid,p_app_user_id text,p_action text,p_phone text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor public.users%rowtype;
  v_target public.users%rowtype;
  v_action text := lower(btrim(coalesce(p_action, '')));
  v_phone text;
  v_request private.parent_phone_access_requests%rowtype;
  v_next_allowed timestamptz;
begin
  if p_actor_auth_user_id is null then return jsonb_build_object('ok',false,'code','AUTH_REQUIRED'); end if;
  select * into v_actor from public.users where auth_user_id=p_actor_auth_user_id and status='active' limit 1;
  if not found then return jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); end if;
  if v_actor.role not in ('direction','direction2','direction_pedagogique') then return jsonb_build_object('ok',false,'code','FORBIDDEN'); end if;
  if v_action not in ('provision','reset','change_phone') then return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','action'); end if;
  select * into v_target from public.users where id=p_app_user_id for update;
  if not found then return jsonb_build_object('ok',false,'code','TARGET_NOT_FOUND'); end if;
  if v_target.role<>'parent' then return jsonb_build_object('ok',false,'code','TARGET_NOT_PARENT'); end if;
  if v_target.status<>'active' then return jsonb_build_object('ok',false,'code','TARGET_DISABLED'); end if;
  v_phone := case when v_action='change_phone' then private.normalize_phone_e164(p_phone) else private.normalize_phone_e164(v_target.phone) end;
  if v_phone is null then return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','phone'); end if;
  if v_action='provision' and v_target.auth_user_id is not null then return jsonb_build_object('ok',false,'code','ALREADY_LINKED'); end if;
  if v_action in ('reset','change_phone') and v_target.auth_user_id is null then return jsonb_build_object('ok',false,'code','ACCOUNT_NOT_LINKED'); end if;
  if exists(select 1 from public.users where id<>v_target.id and phone=v_phone) then return jsonb_build_object('ok',false,'code','PHONE_IN_USE'); end if;
  if exists(select 1 from auth.users where phone=v_phone and id is distinct from v_target.auth_user_id) then return jsonb_build_object('ok',false,'code','PHONE_IN_USE'); end if;
  select created_at+interval '60 seconds' into v_next_allowed from private.parent_phone_access_requests where app_user_id=v_target.id and created_at>now()-interval '60 seconds' order by created_at desc limit 1;
  if found then return jsonb_build_object('ok',false,'code','TOO_SOON','next_allowed_at',v_next_allowed); end if;
  update private.parent_phone_access_requests set status=case when expires_at<=now() then 'expired' else 'failed' end,failed_at=now(),failure_code=case when expires_at<=now() then 'EXPIRED_REPLACED' else 'REPLACED' end
  where app_user_id=v_target.id and status in ('prepared','auth_linked','ready');
  insert into private.parent_phone_access_requests(app_user_id,phone,action,requested_by,auth_user_id)
  values(v_target.id,v_phone,v_action,v_actor.id,case when v_action='provision' then null else v_target.auth_user_id end) returning * into v_request;
  perform private.write_audit_event(v_actor.id,v_actor.name,'parent_phone_access_prepared',jsonb_build_object('app_user_id',v_target.id,'action',v_action,'expires_at',v_request.expires_at),v_target.id);
  return jsonb_build_object('ok',true,'code','PHONE_ACCESS_PREPARED','request_id',v_request.id,'request_secret',v_request.secret,'app_user_id',v_target.id,'phone',v_phone,'action',v_action,'auth_user_id',v_request.auth_user_id,'expires_at',v_request.expires_at);
exception when unique_violation then return jsonb_build_object('ok',false,'code','PHONE_ACCESS_CONFLICT');
end;
$$;

revoke all on function public.save_parent_phone_profile(jsonb) from public,anon;
grant execute on function public.save_parent_phone_profile(jsonb) to authenticated;
revoke all on function public.prepare_parent_phone_access(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.prepare_parent_phone_access(uuid,text,text,text) to service_role;
