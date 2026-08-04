-- Repair the Auth invitation contract.
-- A new Auth identity must link to the existing SchoolSafe profile instead of creating a duplicate user row.

alter table private.account_invitations
  add column if not exists id uuid not null default gen_random_uuid(),
  add column if not exists app_user_id text,
  add column if not exists invited_by text;

alter table public.users
  add column if not exists invitation_sent_at timestamptz,
  add column if not exists updated_at timestamptz not null default now();

update private.account_invitations i
set app_user_id = u.id
from public.users u
where i.app_user_id is null
  and ((i.auth_user_id is not null and u.auth_user_id = i.auth_user_id)
       or (u.email is not null and lower(btrim(u.email)) = lower(btrim(i.email))));

update private.account_invitations i
set invited_by = u.id
from public.users u
where i.invited_by is null
  and u.role = 'direction'
  and u.status = 'active';

create unique index if not exists account_invitations_id_key
  on private.account_invitations(id);
create unique index if not exists account_invitations_pending_app_user_key
  on private.account_invitations(app_user_id)
  where accepted_at is null and app_user_id is not null;
create index if not exists account_invitations_invited_by_idx
  on private.account_invitations(invited_by)
  where invited_by is not null;

create or replace function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invitation private.account_invitations%rowtype;
  v_target public.users%rowtype;
  v_email text := lower(btrim(coalesce(new.email, '')));
begin
  if v_email = '' then
    raise exception using errcode='42501', message='Adresse email SchoolSafe manquante.';
  end if;

  select * into v_invitation
  from private.account_invitations i
  where lower(i.email)=v_email
    and i.accepted_at is null
    and i.expires_at>now()
  for update;

  if not found then
    raise exception using errcode='42501', message='Ce compte SchoolSafe ne possède pas une invitation valide.';
  end if;

  if v_invitation.app_user_id is null then
    raise exception using errcode='23503', message='Invitation SchoolSafe non reliée à un profil.';
  end if;

  select * into v_target
  from public.users u
  where u.id=v_invitation.app_user_id
  for update;

  if not found then
    raise exception using errcode='23503', message='Profil SchoolSafe invité introuvable.';
  end if;

  if v_target.status<>'active' then
    raise exception using errcode='42501', message='Profil SchoolSafe inactif.';
  end if;

  if v_target.auth_user_id is not null and v_target.auth_user_id<>new.id then
    raise exception using errcode='23505', message='Ce profil SchoolSafe est déjà relié à un autre compte.';
  end if;

  insert into public.profiles(id,email,full_name,role,status)
  values(new.id,v_email,v_target.name,v_target.role,v_target.status)
  on conflict(id) do update
    set email=excluded.email,
        full_name=excluded.full_name,
        role=excluded.role,
        status=excluded.status,
        updated_at=now();

  update public.users
  set auth_user_id=new.id,
      email=v_email,
      invitation_sent_at=coalesce(invitation_sent_at,now()),
      updated_at=now()
  where id=v_target.id;

  update private.account_invitations
  set accepted_at=now(),auth_user_id=new.id
  where email=v_invitation.email;

  return new;
end;
$$;

comment on function private.handle_new_auth_user() is
  'Links a new Supabase Auth identity to the existing invited SchoolSafe profile; never creates a duplicate public.users row.';
