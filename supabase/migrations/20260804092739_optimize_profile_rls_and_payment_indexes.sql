-- Index the remaining payment foreign keys and protect self-service profile updates.

create index if not exists idx_payment_access_exceptions_granted_by
  on public.payment_access_exceptions(granted_by);
create index if not exists idx_payment_access_exceptions_revoked_by
  on public.payment_access_exceptions(revoked_by)
  where revoked_by is not null;
create index if not exists idx_payment_scan_log_checked_by
  on public.payment_scan_log(checked_by);

drop index if exists public.idx_payment_allocations_obligation_id;

drop policy if exists payment_receipt_counters_deny_all on public.payment_receipt_counters;
create policy payment_receipt_counters_deny_all
on public.payment_receipt_counters
as restrictive
for all
to authenticated
using (false)
with check (false);

create or replace function private.protect_profile_identity_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if private.is_direction() then
    new.updated_at:=now();
    return new;
  end if;

  if (select auth.uid()) is null or old.id<>(select auth.uid()) then
    raise exception 'Accès refusé' using errcode='42501';
  end if;

  if new.id is distinct from old.id
     or new.email is distinct from old.email
     or new.role is distinct from old.role
     or new.status is distinct from old.status
     or new.created_at is distinct from old.created_at then
    raise exception 'Les champs d’identité et de rôle sont protégés' using errcode='42501';
  end if;

  new.updated_at:=now();
  return new;
end;
$$;

drop trigger if exists protect_profile_identity_fields on public.profiles;
create trigger protect_profile_identity_fields
before update on public.profiles
for each row execute function private.protect_profile_identity_fields();

drop policy if exists profiles_d1_write on public.profiles;
drop policy if exists profiles_read on public.profiles;
drop policy if exists profiles_self_update on public.profiles;
drop policy if exists profiles_select on public.profiles;
drop policy if exists profiles_insert on public.profiles;
drop policy if exists profiles_update on public.profiles;
drop policy if exists profiles_delete on public.profiles;

create policy profiles_select
on public.profiles
for select
to authenticated
using (id=(select auth.uid()) or private.is_direction_any());

create policy profiles_insert
on public.profiles
for insert
to authenticated
with check (private.is_direction());

create policy profiles_update
on public.profiles
for update
to authenticated
using (id=(select auth.uid()) or private.is_direction())
with check (id=(select auth.uid()) or private.is_direction());

create policy profiles_delete
on public.profiles
for delete
to authenticated
using (private.is_direction());

comment on function private.protect_profile_identity_fields() is
  'Prevents self-service changes to profile id, email, role, status or creation timestamp while allowing safe personal fields.';
