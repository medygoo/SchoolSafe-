-- P0-1: immutable, server-authored payment provenance.

alter table public.payments
  add column if not exists recorded_by text,
  add column if not exists recorded_by_name text,
  add column if not exists recorded_by_role text,
  add column if not exists recorded_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.payments'::regclass
      and conname = 'payments_recorded_by_fkey'
  ) then
    alter table public.payments
      add constraint payments_recorded_by_fkey
      foreign key (recorded_by) references public.users(id) on delete restrict;
  end if;
end $$;

create or replace function private.stamp_legacy_payment_provenance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid text;
  v_role text;
  v_name text;
  v_now timestamptz := now();
begin
  if tg_op = 'DELETE' then
    if coalesce(old.paid, false) then
      raise exception 'Un paiement validé ne peut pas être supprimé directement. Utilisez une contrepassation.'
        using errcode = '23514';
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE' and coalesce(old.paid, false) then
    if not coalesce(new.paid, false) then
      raise exception 'Un paiement validé ne peut pas être remis à non payé. Utilisez une contrepassation.'
        using errcode = '23514';
    end if;
    if new.sid is distinct from old.sid or new.t is distinct from old.t then
      raise exception 'L élève et la période d un paiement validé sont immuables.'
        using errcode = '23514';
    end if;

    new.recorded_by := old.recorded_by;
    new.recorded_by_name := old.recorded_by_name;
    new.recorded_by_role := old.recorded_by_role;
    new.recorded_at := old.recorded_at;
    new."by" := old."by";
    new.date := old.date;
    return new;
  end if;

  if coalesce(new.paid, false) then
    v_uid := private.current_app_user_id();
    v_role := private.current_app_role();

    if v_uid is null or v_role not in ('direction', 'direction3') then
      raise exception 'Accès refusé pour valider ce paiement.' using errcode = '42501';
    end if;

    select nullif(btrim(u.name), '') into v_name
    from public.users u
    where u.id = v_uid and u.status = 'active';

    if v_name is null then
      raise exception 'Profil SchoolSafe actif introuvable.' using errcode = '42501';
    end if;

    new.recorded_by := v_uid;
    new.recorded_by_name := v_name;
    new.recorded_by_role := v_role;
    new.recorded_at := v_now;
    new."by" := v_name;
    new.date := coalesce(
      nullif(btrim(new.date), ''),
      to_char(timezone('Africa/Kinshasa', v_now), 'YYYY-MM-DD')
    );

    perform private.write_audit_event(
      v_uid,
      v_name,
      'legacy_payment_confirmed',
      jsonb_build_object(
        'payment_id', new.id,
        'student_id', new.sid,
        'term', new.t,
        'recorded_by_role', v_role,
        'recorded_at', v_now
      ),
      new.sid
    );
  else
    new.recorded_by := null;
    new.recorded_by_name := null;
    new.recorded_by_role := null;
    new.recorded_at := null;
  end if;

  return new;
end;
$$;

revoke all on function private.stamp_legacy_payment_provenance() from public, anon, authenticated;
grant execute on function private.stamp_legacy_payment_provenance() to service_role;

drop trigger if exists trg_payments_server_provenance on public.payments;
create trigger trg_payments_server_provenance
before insert or update or delete on public.payments
for each row execute function private.stamp_legacy_payment_provenance();

comment on column public.payments.recorded_by is
  'Identifiant applicatif de la personne ayant confirmé le paiement; renseigné exclusivement côté serveur.';
comment on column public.payments.recorded_by_name is
  'Nom figé de la personne ayant confirmé le paiement.';
comment on column public.payments.recorded_by_role is
  'Rôle figé de la personne ayant confirmé le paiement.';
comment on column public.payments.recorded_at is
  'Horodatage serveur de la confirmation du paiement.';
comment on function private.stamp_legacy_payment_provenance() is
  'Compatibilité P0-1: ajoute une provenance serveur aux paiements legacy et empêche leur effacement ou dévalidation directe.';

-- The transaction ledger is authoritative and may only be written through controlled RPCs.
alter function public.record_payment_transaction(
  text, numeric, text, text, text, text, date, jsonb
) security definer;

revoke insert, update, delete, truncate, references, trigger
  on table public.payment_transactions from authenticated;
grant select on table public.payment_transactions to authenticated;

drop policy if exists ptx_insert on public.payment_transactions;
drop policy if exists ptx_update on public.payment_transactions;

revoke all on function public.record_payment_transaction(
  text, numeric, text, text, text, text, date, jsonb
) from public, anon;
grant execute on function public.record_payment_transaction(
  text, numeric, text, text, text, text, date, jsonb
) to authenticated, service_role;

revoke all on function public.reverse_payment_transaction(text, text) from public, anon;
grant execute on function public.reverse_payment_transaction(text, text) to authenticated, service_role;

comment on function public.record_payment_transaction(
  text, numeric, text, text, text, text, date, jsonb
) is 'Porte unique pour enregistrer un encaissement: auteur, rôle, reçu et allocations sont calculés côté serveur.';
comment on table public.payment_transactions is
  'Registre financier immuable. Les écritures directes du navigateur sont interdites; utiliser record_payment_transaction et reverse_payment_transaction.';
