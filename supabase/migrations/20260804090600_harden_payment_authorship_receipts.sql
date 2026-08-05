-- Immutable payment author snapshots and annual sequential receipt numbers.

alter table public.payment_transactions
  add column if not exists recorded_by_name text,
  add column if not exists recorded_by_role text,
  add column if not exists reversed_by_name text,
  add column if not exists reversed_by_role text;

update public.payment_transactions t
set recorded_by_name = coalesce(nullif(btrim(t.recorded_by_name), ''), u.name, 'Compte SchoolSafe'),
    recorded_by_role = coalesce(nullif(btrim(t.recorded_by_role), ''),
      case u.role when 'direction_pedagogique' then 'direction2' when 'caisse' then 'direction3' else u.role end,
      'inconnu')
from public.users u
where u.id = t.recorded_by
  and (t.recorded_by_name is null or t.recorded_by_role is null);

update public.payment_transactions
set recorded_by_name = coalesce(nullif(btrim(recorded_by_name), ''), 'Compte SchoolSafe'),
    recorded_by_role = coalesce(nullif(btrim(recorded_by_role), ''), 'inconnu');

alter table public.payment_transactions
  alter column recorded_by_name set not null,
  alter column recorded_by_role set not null;

create table if not exists public.payment_receipt_counters (
  school_year text primary key,
  last_no bigint not null default 0 check (last_no >= 0),
  updated_at timestamptz not null default now()
);

alter table public.payment_receipt_counters enable row level security;
revoke all on table public.payment_receipt_counters from public;
revoke all on table public.payment_receipt_counters from anon;
revoke all on table public.payment_receipt_counters from authenticated;
grant all on table public.payment_receipt_counters to service_role;

create or replace function private.next_payment_receipt_no(p_school_year text)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_year text := btrim(coalesce(p_school_year, ''));
  v_next bigint;
begin
  if v_year !~ '^\d{4}-\d{4}$' then
    raise exception 'Année scolaire invalide' using errcode = '22023';
  end if;

  insert into public.payment_receipt_counters(school_year, last_no, updated_at)
  values (v_year, 1, now())
  on conflict (school_year) do update
    set last_no = public.payment_receipt_counters.last_no + 1,
        updated_at = now()
  returning last_no into v_next;

  return 'REC-' || v_year || '-' || lpad(v_next::text, 6, '0');
end;
$$;

revoke all on function private.next_payment_receipt_no(text) from public;
revoke all on function private.next_payment_receipt_no(text) from anon;
grant execute on function private.next_payment_receipt_no(text) to authenticated;
grant execute on function private.next_payment_receipt_no(text) to service_role;

create index if not exists idx_payment_transactions_sid on public.payment_transactions(sid);
create index if not exists idx_payment_transactions_recorded_by on public.payment_transactions(recorded_by);
create index if not exists idx_payment_transactions_reversed_by on public.payment_transactions(reversed_by) where reversed_by is not null;
create index if not exists idx_payment_allocations_obligation_id on public.payment_allocations(obligation_id);
create index if not exists idx_student_fee_obligations_sid on public.student_fee_obligations(sid);
create index if not exists idx_student_fee_obligations_fee_type_id on public.student_fee_obligations(fee_type_id);
create index if not exists idx_student_fee_obligations_created_by on public.student_fee_obligations(created_by) where created_by is not null;

comment on table public.payment_receipt_counters is 'Server-only annual receipt sequence; never exposed to browser roles.';
