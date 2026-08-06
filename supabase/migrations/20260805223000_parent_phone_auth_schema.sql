-- SchoolSafe — comptes Parent par téléphone + code temporaire livré par WhatsApp
-- Date: 2026-08-05
-- Objectif: supprimer la dépendance e-mail/SMTP pour les parents tout en gardant
-- Supabase Auth, les RLS et une identité unique par numéro E.164.

create schema if not exists private;

create or replace function private.normalize_phone_e164(p_phone text)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_raw text := btrim(coalesce(p_phone, ''));
  v_compact text;
  v_digits text;
  v_result text;
begin
  if v_raw = '' then
    return null;
  end if;

  v_compact := regexp_replace(v_raw, '[[:space:]().\-]', '', 'g');

  if left(v_compact, 2) = '00' then
    v_compact := '+' || substr(v_compact, 3);
  end if;

  if left(v_compact, 1) = '+' then
    v_digits := substr(v_compact, 2);
    if v_digits !~ '^[1-9][0-9]{7,14}$' then
      return null;
    end if;
    return '+' || v_digits;
  end if;

  if v_compact !~ '^[0-9]+$' then
    return null;
  end if;

  if v_compact ~ '^0[0-9]{9}$' then
    v_result := '+243' || substr(v_compact, 2);
  elsif v_compact ~ '^243[0-9]{9}$' then
    v_result := '+' || v_compact;
  elsif v_compact ~ '^[89][0-9]{8}$' then
    v_result := '+243' || v_compact;
  else
    return null;
  end if;

  if v_result !~ '^\+[1-9][0-9]{7,14}$' then
    return null;
  end if;
  return v_result;
end;
$$;

comment on function private.normalize_phone_e164(text) is
'Normalise un téléphone au format E.164. Les numéros locaux RDC sont convertis en +243...';

alter table public.users alter column email drop not null;
alter table public.profiles alter column email drop not null;

alter table public.users
  add column if not exists access_channel text not null default 'email',
  add column if not exists must_change_password boolean not null default false,
  add column if not exists temporary_access_expires_at timestamptz,
  add column if not exists phone_access_updated_at timestamptz;

update public.users
set access_channel = case
  when role = 'parent' and email is null and phone is not null then 'phone_whatsapp'
  else 'email'
end
where access_channel is null or access_channel not in ('email', 'phone_whatsapp');

do $$
begin
  if exists (
    select 1 from public.users
    where phone is not null
      and btrim(phone) <> ''
      and private.normalize_phone_e164(phone) is null
  ) then
    raise exception using errcode = '23514',
      message = 'Un numéro public.users.phone existant ne peut pas être normalisé en E.164.';
  end if;
end;
$$;

update public.users
set phone = private.normalize_phone_e164(phone)
where phone is not null and btrim(phone) <> '';

update public.profiles
set phone = private.normalize_phone_e164(phone)
where phone is not null
  and btrim(phone) <> ''
  and private.normalize_phone_e164(phone) is not null;

alter table public.users drop constraint if exists users_email_normalized_check;
alter table public.users add constraint users_email_normalized_check
check (
  email is null
  or (
    email = lower(btrim(email))
    and length(email) <= 320
    and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'
  )
);

alter table public.users drop constraint if exists users_phone_e164_check;
alter table public.users add constraint users_phone_e164_check
check (phone is null or phone ~ '^\+[1-9][0-9]{7,14}$');

alter table public.users drop constraint if exists users_access_channel_check;
alter table public.users add constraint users_access_channel_check
check (access_channel in ('email', 'phone_whatsapp'));

alter table public.users drop constraint if exists users_contact_required_check;
alter table public.users add constraint users_contact_required_check
check (
  (
    role = 'parent'
    and (
      (access_channel = 'email' and email is not null)
      or (access_channel = 'phone_whatsapp' and phone is not null)
    )
  )
  or
  (
    role <> 'parent'
    and access_channel = 'email'
    and email is not null
  )
);

create unique index if not exists users_phone_e164_unique
on public.users(phone)
where phone is not null;

alter table public.profiles drop constraint if exists profiles_phone_e164_check;
alter table public.profiles add constraint profiles_phone_e164_check
check (phone is null or phone ~ '^\+[1-9][0-9]{7,14}$');

create table if not exists private.parent_phone_access_requests (
  id uuid primary key default gen_random_uuid(),
  secret uuid not null default gen_random_uuid(),
  app_user_id text not null references public.users(id) on delete cascade,
  phone text not null,
  action text not null check (action in ('provision', 'reset', 'change_phone')),
  requested_by text not null references public.users(id),
  status text not null default 'prepared'
    check (status in ('prepared', 'auth_linked', 'ready', 'completed', 'failed', 'expired')),
  auth_user_id uuid,
  password_fingerprint text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '30 minutes'),
  ready_at timestamptz,
  completed_at timestamptz,
  failed_at timestamptz,
  failure_code text
);

create index if not exists parent_phone_access_target_created_idx
on private.parent_phone_access_requests(app_user_id, created_at desc);

create unique index if not exists parent_phone_access_one_active_idx
on private.parent_phone_access_requests(app_user_id)
where status in ('prepared', 'auth_linked', 'ready');

revoke all on table private.parent_phone_access_requests from public, anon, authenticated;
