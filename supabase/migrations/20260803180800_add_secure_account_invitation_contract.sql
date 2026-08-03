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
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_existing_auth_id uuid;
  v_existing_user_id text;
  v_invitation private.account_invitations%rowtype;
begin
  if p_actor_auth_user_id is null then
    return jsonb_build_object('ok', false, 'code', 'AUTH_REQUIRED');
  end if;

  select * into v_actor
  from public.users
  where auth_user_id = p_actor_auth_user_id
    and status = 'active'
  limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'code', 'ACTOR_NOT_FOUND');
  end if;

  if v_actor.role <> 'direction' then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN');
  end if;

  if nullif(btrim(coalesce(p_app_user_id, '')), '') is null then
    return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'app_user_id');
  end if;

  if v_email = '' or v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
    return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'email');
  end if;

  select * into v_target
  from public.users
  where id = p_app_user_id
  limit 1;

  if not found then
    return jsonb_build_object('ok', false, 'code', 'TARGET_NOT_FOUND');
  end if;

  if v_target.status <> 'active' then
    return jsonb_build_object('ok', false, 'code', 'TARGET_DISABLED');
  end if;

  if v_target.role not in (
    'direction', 'direction2', 'direction3',
    'enseignant', 'enseignant_maternelle',
    'parent', 'gardien'
  ) then
    return jsonb_build_object('ok', false, 'code', 'UNSUPPORTED_ROLE');
  end if;

  if v_target.auth_user_id is not null then
    return jsonb_build_object(
      'ok', false,
      'code', 'ALREADY_LINKED',
      'app_user_id', v_target.id
    );
  end if;

  select id into v_existing_user_id
  from public.users
  where id <> v_target.id
    and email is not null
    and lower(btrim(email)) = v_email
  limit 1;

  if found then
    return jsonb_build_object('ok', false, 'code', 'EMAIL_IN_USE');
  end if;

  select id into v_existing_auth_id
  from auth.users
  where email is not null
    and lower(btrim(email)) = v_email
  limit 1;

  if found then
    return jsonb_build_object('ok', false, 'code', 'EMAIL_IN_USE');
  end if;

  select * into v_invitation
  from private.account_invitations
  where lower(email) = v_email
  limit 1;

  if found and v_invitation.app_user_id <> v_target.id then
    return jsonb_build_object('ok', false, 'code', 'EMAIL_IN_USE');
  end if;

  if found and v_invitation.accepted_at is not null then
    delete from private.account_invitations
    where id = v_invitation.id;
    v_invitation := null;
  end if;

  update public.users
  set email = v_email,
      invitation_sent_at = now(),
      updated_at = now()
  where id = v_target.id;

  if v_invitation.id is null then
    insert into private.account_invitations (
      email,
      app_user_id,
      role,
      full_name,
      invited_by,
      expires_at
    ) values (
      v_email,
      v_target.id,
      v_target.role,
      v_target.name,
      v_actor.id,
      now() + interval '3 days'
    )
    returning * into v_invitation;
  else
    update private.account_invitations
    set role = v_target.role,
        full_name = v_target.name,
        invited_by = v_actor.id,
        created_at = now(),
        expires_at = now() + interval '3 days',
        accepted_at = null
    where id = v_invitation.id
    returning * into v_invitation;
  end if;

  insert into public.audit_log (
    user_id,
    user_name,
    role,
    action,
    target,
    target_id,
    new_data
  ) values (
    v_actor.id,
    v_actor.name,
    v_actor.role,
    'account_invitation_prepared',
    'user',
    v_target.id,
    jsonb_build_object(
      'email', v_email,
      'role', v_target.role,
      'invitation_id', v_invitation.id
    )
  );

  return jsonb_build_object(
    'ok', true,
    'code', 'INVITATION_PREPARED',
    'invitation_id', v_invitation.id,
    'app_user_id', v_target.id,
    'email', v_email,
    'full_name', v_target.name,
    'role', v_target.role,
    'expires_at', v_invitation.expires_at
  );
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
    return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR');
  end if;

  select * into v_actor
  from public.users
  where auth_user_id = p_actor_auth_user_id
    and status = 'active'
  limit 1;

  if not found or v_actor.role <> 'direction' then
    return jsonb_build_object('ok', false, 'code', 'FORBIDDEN');
  end if;

  select * into v_invitation
  from private.account_invitations
  where id = p_invitation_id
  limit 1;

  if not found then
    return jsonb_build_object('ok', true, 'code', 'NOTHING_TO_CANCEL');
  end if;

  if v_invitation.accepted_at is not null then
    return jsonb_build_object('ok', true, 'code', 'ALREADY_ACCEPTED');
  end if;

  delete from private.account_invitations
  where id = v_invitation.id
    and accepted_at is null;

  update public.users
  set invitation_sent_at = null,
      updated_at = now()
  where id = v_invitation.app_user_id
    and auth_user_id is null;

  insert into public.audit_log (
    user_id,
    user_name,
    role,
    action,
    target,
    target_id,
    old_data
  ) values (
    v_actor.id,
    v_actor.name,
    v_actor.role,
    'account_invitation_cancelled',
    'user',
    v_invitation.app_user_id,
    jsonb_build_object(
      'email', v_invitation.email,
      'invitation_id', v_invitation.id
    )
  );

  return jsonb_build_object('ok', true, 'code', 'INVITATION_CANCELLED');
end;
$$;

revoke all on function public.prepare_account_invitation(uuid, text, text)
from public, anon, authenticated;
grant execute on function public.prepare_account_invitation(uuid, text, text)
to service_role;

revoke all on function public.cancel_account_invitation(uuid, uuid)
from public, anon, authenticated;
grant execute on function public.cancel_account_invitation(uuid, uuid)
to service_role;

comment on function public.prepare_account_invitation(uuid, text, text) is
'Service-only SchoolSafe contract that validates Direction 1 and prepares a short-lived Auth invitation without exposing service credentials to the browser.';

comment on function public.cancel_account_invitation(uuid, uuid) is
'Service-only compensating operation used when the external Supabase Auth invitation cannot be created.';
