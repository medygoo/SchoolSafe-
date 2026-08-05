-- Final account invitation RPCs aligned with the existing SchoolSafe audit_log schema.

create or replace function private.write_audit_event(
  p_by text,
  p_by_name text,
  p_action text,
  p_detail jsonb,
  p_target_id text
)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
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
$$;

revoke all on function private.write_audit_event(text,text,text,jsonb,text) from public;
revoke all on function private.write_audit_event(text,text,text,jsonb,text) from anon;
grant execute on function private.write_audit_event(text,text,text,jsonb,text) to service_role;

create or replace function public.prepare_account_invitation(
  p_actor_auth_user_id uuid,
  p_app_user_id text,
  p_email text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor public.users%rowtype;
  v_target public.users%rowtype;
  v_email text := lower(btrim(coalesce(p_email,'')));
  v_existing_auth_id uuid;
  v_existing_user_id text;
  v_invitation private.account_invitations%rowtype;
begin
  if p_actor_auth_user_id is null then return jsonb_build_object('ok',false,'code','AUTH_REQUIRED'); end if;
  select * into v_actor from public.users where auth_user_id=p_actor_auth_user_id and status='active' limit 1;
  if not found then return jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); end if;
  if v_actor.role<>'direction' then return jsonb_build_object('ok',false,'code','FORBIDDEN'); end if;

  if nullif(btrim(coalesce(p_app_user_id,'')),'') is null then
    return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','app_user_id');
  end if;
  if v_email='' or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','email');
  end if;

  select * into v_target from public.users where id=p_app_user_id limit 1;
  if not found then return jsonb_build_object('ok',false,'code','TARGET_NOT_FOUND'); end if;
  if v_target.status<>'active' then return jsonb_build_object('ok',false,'code','TARGET_DISABLED'); end if;
  if v_target.role not in ('direction','direction2','direction3','enseignant','parent','gardien') then
    return jsonb_build_object('ok',false,'code','UNSUPPORTED_ROLE');
  end if;
  if v_target.auth_user_id is not null then
    return jsonb_build_object('ok',false,'code','ALREADY_LINKED','app_user_id',v_target.id);
  end if;

  select id into v_existing_user_id from public.users
  where id<>v_target.id and email is not null and lower(btrim(email))=v_email limit 1;
  if found then return jsonb_build_object('ok',false,'code','EMAIL_IN_USE'); end if;
  select id into v_existing_auth_id from auth.users
  where email is not null and lower(btrim(email))=v_email limit 1;
  if found then return jsonb_build_object('ok',false,'code','EMAIL_IN_USE'); end if;

  select * into v_invitation from private.account_invitations where lower(email)=v_email limit 1;
  if found and v_invitation.app_user_id is distinct from v_target.id and v_invitation.accepted_at is null then
    return jsonb_build_object('ok',false,'code','EMAIL_IN_USE');
  end if;

  insert into private.account_invitations(
    email,full_name,role,invited_at,expires_at,accepted_at,auth_user_id,app_user_id,invited_by
  ) values (
    v_email,v_target.name,v_target.role,now(),now()+interval '3 days',null,null,v_target.id,v_actor.id
  )
  on conflict(email) do update
    set full_name=excluded.full_name,role=excluded.role,invited_at=excluded.invited_at,
        expires_at=excluded.expires_at,accepted_at=null,auth_user_id=null,
        app_user_id=excluded.app_user_id,invited_by=excluded.invited_by
  returning * into v_invitation;

  update public.users
  set email=v_email,invitation_sent_at=now(),updated_at=now()
  where id=v_target.id;

  perform private.write_audit_event(
    v_actor.id,v_actor.name,'account_invitation_prepared',
    jsonb_build_object('email',v_email,'role',v_target.role,'invitation_id',v_invitation.id),
    v_target.id
  );

  return jsonb_build_object(
    'ok',true,'code','INVITATION_PREPARED','invitation_id',v_invitation.id,
    'app_user_id',v_target.id,'email',v_email,'full_name',v_target.name,
    'role',v_target.role,'expires_at',v_invitation.expires_at
  );
exception
  when unique_violation then return jsonb_build_object('ok',false,'code','INVITATION_CONFLICT');
  when foreign_key_violation then return jsonb_build_object('ok',false,'code','REFERENCE_NOT_FOUND');
end;
$$;

create or replace function public.cancel_account_invitation(
  p_actor_auth_user_id uuid,
  p_invitation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
$$;

revoke all on function public.prepare_account_invitation(uuid,text,text) from public;
revoke all on function public.prepare_account_invitation(uuid,text,text) from anon;
revoke all on function public.cancel_account_invitation(uuid,uuid) from public;
revoke all on function public.cancel_account_invitation(uuid,uuid) from anon;
grant execute on function public.prepare_account_invitation(uuid,text,text) to service_role;
grant execute on function public.cancel_account_invitation(uuid,uuid) to service_role;
