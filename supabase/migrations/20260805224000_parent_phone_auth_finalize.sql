create or replace function public.finalize_parent_phone_access(p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request private.parent_phone_access_requests%rowtype;
  v_target public.users%rowtype;
  v_auth auth.users%rowtype;
  v_fingerprint text;
begin
  select * into v_request from private.parent_phone_access_requests where id=p_request_id for update;
  if not found then return jsonb_build_object('ok',false,'code','REQUEST_NOT_FOUND'); end if;
  if v_request.status='ready' then return jsonb_build_object('ok',true,'code','PHONE_ACCESS_READY','app_user_id',v_request.app_user_id,'phone',v_request.phone,'expires_at',v_request.expires_at); end if;
  if v_request.status not in ('prepared','auth_linked') then return jsonb_build_object('ok',false,'code','REQUEST_NOT_OPEN'); end if;
  if v_request.expires_at<=now() then
    update private.parent_phone_access_requests set status='expired',failed_at=now(),failure_code='EXPIRED' where id=v_request.id;
    return jsonb_build_object('ok',false,'code','REQUEST_EXPIRED');
  end if;
  select * into v_target from public.users where id=v_request.app_user_id for update;
  if not found then return jsonb_build_object('ok',false,'code','TARGET_NOT_FOUND'); end if;
  if v_request.auth_user_id is null then v_request.auth_user_id:=v_target.auth_user_id; end if;
  if v_request.auth_user_id is null then return jsonb_build_object('ok',false,'code','AUTH_LINK_MISSING'); end if;
  select * into v_auth from auth.users where id=v_request.auth_user_id;
  if not found then return jsonb_build_object('ok',false,'code','AUTH_USER_NOT_FOUND'); end if;
  if private.normalize_phone_e164(v_auth.phone) is distinct from v_request.phone then return jsonb_build_object('ok',false,'code','AUTH_PHONE_MISMATCH'); end if;
  v_fingerprint:=pg_catalog.encode(extensions.digest(coalesce(v_auth.encrypted_password,''),'sha256'),'hex');
  update public.users set auth_user_id=v_request.auth_user_id,phone=v_request.phone,access_channel='phone_whatsapp',must_change_password=true,temporary_access_expires_at=v_request.expires_at,phone_access_updated_at=now(),updated_at=now() where id=v_request.app_user_id;
  insert into public.profiles(id,email,phone,full_name,role,status)
  values(v_request.auth_user_id,v_target.email,v_request.phone,v_target.name,v_target.role,v_target.status)
  on conflict(id) do update set email=excluded.email,phone=excluded.phone,full_name=excluded.full_name,role=excluded.role,status=excluded.status,updated_at=now();
  update private.parent_phone_access_requests set status='ready',auth_user_id=v_request.auth_user_id,password_fingerprint=v_fingerprint,ready_at=now() where id=v_request.id;
  perform private.write_audit_event(v_request.requested_by,(select name from public.users where id=v_request.requested_by),'parent_phone_access_ready',jsonb_build_object('app_user_id',v_request.app_user_id,'action',v_request.action,'expires_at',v_request.expires_at),v_request.app_user_id);
  return jsonb_build_object('ok',true,'code','PHONE_ACCESS_READY','app_user_id',v_request.app_user_id,'phone',v_request.phone,'action',v_request.action,'expires_at',v_request.expires_at,'next_allowed_at',v_request.created_at+interval '60 seconds');
end;
$$;

create or replace function public.fail_parent_phone_access_request(p_request_id uuid,p_failure_code text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_request private.parent_phone_access_requests%rowtype;
begin
  select * into v_request from private.parent_phone_access_requests where id=p_request_id for update;
  if not found then return jsonb_build_object('ok',true,'code','REQUEST_NOT_FOUND'); end if;
  update private.parent_phone_access_requests set status='failed',failed_at=now(),failure_code=left(coalesce(nullif(btrim(p_failure_code),''),'UNKNOWN'),100)
  where id=p_request_id and status in ('prepared','auth_linked');
  if found then perform private.write_audit_event(v_request.requested_by,(select name from public.users where id=v_request.requested_by),'parent_phone_access_failed',jsonb_build_object('app_user_id',v_request.app_user_id,'action',v_request.action,'failure_code',left(coalesce(nullif(btrim(p_failure_code),''),'UNKNOWN'),100)),v_request.app_user_id); end if;
  return jsonb_build_object('ok',true,'code','REQUEST_FAILED');
end;
$$;

create or replace function public.get_my_access_state()
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_user public.users%rowtype; v_expired boolean;
begin
  if auth.uid() is null then return jsonb_build_object('ok',false,'code','AUTH_REQUIRED'); end if;
  select * into v_user from public.users where auth_user_id=auth.uid() limit 1;
  if not found then return jsonb_build_object('ok',false,'code','PROFILE_NOT_LINKED'); end if;
  if v_user.status<>'active' then return jsonb_build_object('ok',false,'code','ACCOUNT_DISABLED','status',v_user.status); end if;
  v_expired:=v_user.must_change_password and v_user.temporary_access_expires_at is not null and v_user.temporary_access_expires_at<=now();
  return jsonb_build_object('ok',true,'code',case when v_expired then 'TEMPORARY_PASSWORD_EXPIRED' when v_user.must_change_password then 'TEMPORARY_PASSWORD_MUST_CHANGE' else 'ACCESS_READY' end,'app_user_id',v_user.id,'role',v_user.role,'access_channel',v_user.access_channel,'phone',v_user.phone,'must_change_password',v_user.must_change_password,'temporary_access_expires_at',v_user.temporary_access_expires_at,'expired',v_expired);
end;
$$;

create or replace function public.confirm_parent_phone_password_change()
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
  v_user public.users%rowtype;
  v_request private.parent_phone_access_requests%rowtype;
  v_auth auth.users%rowtype;
  v_fingerprint text;
begin
  if auth.uid() is null then return jsonb_build_object('ok',false,'code','AUTH_REQUIRED'); end if;
  select * into v_user from public.users where auth_user_id=auth.uid() for update;
  if not found then return jsonb_build_object('ok',false,'code','PROFILE_NOT_LINKED'); end if;
  if v_user.role<>'parent' or v_user.access_channel<>'phone_whatsapp' then return jsonb_build_object('ok',false,'code','NOT_PHONE_PARENT'); end if;
  if not v_user.must_change_password then return jsonb_build_object('ok',true,'code','ACCESS_ALREADY_READY'); end if;
  if v_user.temporary_access_expires_at is null or v_user.temporary_access_expires_at<=now() then return jsonb_build_object('ok',false,'code','TEMPORARY_PASSWORD_EXPIRED'); end if;
  select * into v_request from private.parent_phone_access_requests where app_user_id=v_user.id and auth_user_id=auth.uid() and status='ready' order by created_at desc limit 1 for update;
  if not found then return jsonb_build_object('ok',false,'code','ACCESS_REQUEST_NOT_FOUND'); end if;
  select * into v_auth from auth.users where id=auth.uid();
  if not found then return jsonb_build_object('ok',false,'code','AUTH_USER_NOT_FOUND'); end if;
  v_fingerprint:=pg_catalog.encode(extensions.digest(coalesce(v_auth.encrypted_password,''),'sha256'),'hex');
  if v_fingerprint=v_request.password_fingerprint then return jsonb_build_object('ok',false,'code','PASSWORD_NOT_CHANGED'); end if;
  update public.users set must_change_password=false,temporary_access_expires_at=null,phone_access_updated_at=now(),updated_at=now() where id=v_user.id;
  update public.profiles set phone=v_user.phone,email=v_user.email,updated_at=now() where id=auth.uid();
  update private.parent_phone_access_requests set status='completed',completed_at=now() where id=v_request.id;
  perform private.write_audit_event(v_user.id,v_user.name,'parent_phone_password_changed',jsonb_build_object('app_user_id',v_user.id),v_user.id);
  return jsonb_build_object('ok',true,'code','ACCESS_READY');
end;
$$;

create or replace function private.current_app_role()
returns text language sql stable security definer set search_path=''
as $$
  select case u.role when 'direction_pedagogique' then 'direction2' when 'caisse' then 'direction3' else u.role end
  from public.users u
  where u.auth_user_id=auth.uid() and u.status='active'
    and not (u.role='parent' and u.access_channel='phone_whatsapp' and u.must_change_password)
  limit 1
$$;

create or replace function private.current_app_user_id()
returns text language sql stable security definer set search_path=''
as $$
  select u.id from public.users u
  where u.auth_user_id=auth.uid() and u.status='active'
    and not (u.role='parent' and u.access_channel='phone_whatsapp' and u.must_change_password)
  limit 1
$$;

create or replace function private.handle_new_auth_user()
returns trigger language plpgsql security definer set search_path=''
as $$
declare
  v_invitation private.account_invitations%rowtype;
  v_phone_request private.parent_phone_access_requests%rowtype;
  v_target public.users%rowtype;
  v_email text:=lower(btrim(coalesce(new.email,'')));
  v_phone text:=private.normalize_phone_e164(new.phone);
  v_request_id uuid;
  v_request_secret uuid;
begin
  if v_phone is not null then
    begin
      v_request_id:=nullif(new.raw_user_meta_data->>'school_phone_request_id','')::uuid;
      v_request_secret:=nullif(new.raw_user_meta_data->>'school_phone_request_secret','')::uuid;
    exception when invalid_text_representation then raise exception using errcode='42501',message='Provision téléphone SchoolSafe invalide.'; end;
    if v_request_id is null or v_request_secret is null then raise exception using errcode='42501',message='Provision téléphone SchoolSafe manquante.'; end if;
    select * into v_phone_request from private.parent_phone_access_requests r
    where r.id=v_request_id and r.secret=v_request_secret and r.action='provision' and r.status='prepared' and r.expires_at>now() and r.phone=v_phone for update;
    if not found then raise exception using errcode='42501',message='Provision téléphone SchoolSafe expirée ou invalide.'; end if;
    select * into v_target from public.users u where u.id=v_phone_request.app_user_id for update;
    if not found then raise exception using errcode='23503',message='Profil Parent SchoolSafe introuvable.'; end if;
    if v_target.role<>'parent' or v_target.status<>'active' then raise exception using errcode='42501',message='Profil Parent SchoolSafe non autorisé.'; end if;
    if v_target.auth_user_id is not null and v_target.auth_user_id<>new.id then raise exception using errcode='23505',message='Ce profil Parent est déjà relié à un autre compte.'; end if;
    if v_target.phone is distinct from v_phone then raise exception using errcode='23514',message='Le téléphone Auth ne correspond pas au profil Parent.'; end if;
    insert into public.profiles(id,email,phone,full_name,role,status)
    values(new.id,v_target.email,v_phone,v_target.name,v_target.role,v_target.status)
    on conflict(id) do update set email=excluded.email,phone=excluded.phone,full_name=excluded.full_name,role=excluded.role,status=excluded.status,updated_at=now();
    update public.users set auth_user_id=new.id,phone=v_phone,access_channel='phone_whatsapp',must_change_password=true,temporary_access_expires_at=v_phone_request.expires_at,phone_access_updated_at=now(),updated_at=now() where id=v_target.id;
    update private.parent_phone_access_requests set status='auth_linked',auth_user_id=new.id where id=v_phone_request.id;
    return new;
  end if;

  if v_email='' then raise exception using errcode='42501',message='Identité SchoolSafe manquante.'; end if;
  select * into v_invitation from private.account_invitations i where lower(i.email)=v_email and i.accepted_at is null and i.expires_at>now() for update;
  if not found then raise exception using errcode='42501',message='Ce compte SchoolSafe ne possède pas une invitation valide.'; end if;
  if v_invitation.app_user_id is null then raise exception using errcode='23503',message='Invitation SchoolSafe non reliée à un profil.'; end if;
  select * into v_target from public.users u where u.id=v_invitation.app_user_id for update;
  if not found then raise exception using errcode='23503',message='Profil SchoolSafe invité introuvable.'; end if;
  if v_target.status<>'active' then raise exception using errcode='42501',message='Profil SchoolSafe inactif.'; end if;
  if v_target.auth_user_id is not null and v_target.auth_user_id<>new.id then raise exception using errcode='23505',message='Ce profil SchoolSafe est déjà relié à un autre compte.'; end if;
  insert into public.profiles(id,email,phone,full_name,role,status)
  values(new.id,v_email,v_target.phone,v_target.name,v_target.role,v_target.status)
  on conflict(id) do update set email=excluded.email,phone=excluded.phone,full_name=excluded.full_name,role=excluded.role,status=excluded.status,updated_at=now();
  update public.users set auth_user_id=new.id,email=v_email,invitation_sent_at=coalesce(invitation_sent_at,now()),updated_at=now() where id=v_target.id;
  update private.account_invitations set accepted_at=now(),auth_user_id=new.id where email=v_invitation.email;
  return new;
end;
$$;

create or replace function public.get_parent_phone_access_request_status(p_request_id uuid)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_request private.parent_phone_access_requests%rowtype;
begin
  select * into v_request from private.parent_phone_access_requests where id=p_request_id;
  if not found then return jsonb_build_object('ok',false,'code','REQUEST_NOT_FOUND'); end if;
  return jsonb_build_object('ok',true,'code','REQUEST_STATUS','status',v_request.status,'app_user_id',v_request.app_user_id,'action',v_request.action,'expires_at',v_request.expires_at,'ready_at',v_request.ready_at,'completed_at',v_request.completed_at,'failure_code',v_request.failure_code);
end;
$$;

create or replace function public.expire_parent_phone_access_requests()
returns integer language plpgsql security definer set search_path=''
as $$
declare v_count integer;
begin
  update private.parent_phone_access_requests set status='expired',failed_at=coalesce(failed_at,now()),failure_code=coalesce(failure_code,'EXPIRED')
  where status in ('prepared','auth_linked','ready') and expires_at<=now();
  get diagnostics v_count=row_count;
  return v_count;
end;
$$;

revoke all on function public.finalize_parent_phone_access(uuid) from public,anon,authenticated;
grant execute on function public.finalize_parent_phone_access(uuid) to service_role;
revoke all on function public.fail_parent_phone_access_request(uuid,text) from public,anon,authenticated;
grant execute on function public.fail_parent_phone_access_request(uuid,text) to service_role;
revoke all on function public.get_parent_phone_access_request_status(uuid) from public,anon,authenticated;
grant execute on function public.get_parent_phone_access_request_status(uuid) to service_role;
revoke all on function public.expire_parent_phone_access_requests() from public,anon,authenticated;
grant execute on function public.expire_parent_phone_access_requests() to service_role;
revoke all on function public.get_my_access_state() from public,anon;
grant execute on function public.get_my_access_state() to authenticated;
revoke all on function public.confirm_parent_phone_password_change() from public,anon;
grant execute on function public.confirm_parent_phone_password_change() to authenticated;
