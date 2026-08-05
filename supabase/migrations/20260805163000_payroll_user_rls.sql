-- SchoolSafe — paie du personnel (P0-15, P0-16, P0-17)
-- Décisions de Loms, 5 août 2026 :
--   * tous les comptes sauf les parents peuvent être payés ;
--   * Direction 1 fixe les montants ;
--   * la Caisse verse sans pouvoir modifier les montants ;
--   * chaque membre du personnel ne lit que sa propre paie ;
--   * Direction 2 n'administre pas la paie, mais lit la sienne ;
--   * les primes directes sont visibles par Direction 1, Direction 2 et
--     l'enseignant concerné uniquement.

begin;

-- ---------------------------------------------------------------------------
-- P0-15 — une référence de compte explicite, sans casser l'historique
-- ---------------------------------------------------------------------------

alter table public.salaries
  add column if not exists user_id text;

alter table public.advances
  add column if not exists user_id text;

-- Les anciennes lignes peuvent avoir été saisies en texte libre. La FK reste
-- donc nullable ; lorsqu'un compte est supprimé, la pièce comptable demeure.
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.salaries'::regclass
      and conname = 'salaries_user_id_fkey'
  ) then
    alter table public.salaries
      add constraint salaries_user_id_fkey
      foreign key (user_id) references public.users(id) on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.advances'::regclass
      and conname = 'advances_user_id_fkey'
  ) then
    alter table public.advances
      add constraint advances_user_id_fkey
      foreign key (user_id) references public.users(id) on delete set null;
  end if;
end
$$;

update public.salaries s
set user_id = s.teacher_id
where s.user_id is null
  and exists (select 1 from public.users u where u.id = s.teacher_id);

update public.advances a
set user_id = a.teacher_id
where a.user_id is null
  and exists (select 1 from public.users u where u.id = a.teacher_id);

create index if not exists salaries_user_id_idx
  on public.salaries(user_id);
create index if not exists advances_user_id_idx
  on public.advances(user_id);

create or replace function private.sync_payroll_user_reference()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_teacher_is_user boolean;
begin
  if new.user_id is not null then
    if not exists (select 1 from public.users u where u.id = new.user_id) then
      raise exception using
        errcode = '23503',
        message = 'PAYROLL_USER_NOT_FOUND';
    end if;

    v_teacher_is_user := new.teacher_id is not null
      and exists (select 1 from public.users u where u.id = new.teacher_id);

    if v_teacher_is_user and new.teacher_id <> new.user_id then
      raise exception using
        errcode = '23514',
        message = 'PAYROLL_USER_MISMATCH';
    end if;

    -- Dès qu'une référence canonique existe, l'ancien champ reste synchronisé
    -- pour le frontend actuel de Claude, qui lit encore teacher_id.
    new.teacher_id := new.user_id;
  elsif new.teacher_id is not null
    and exists (select 1 from public.users u where u.id = new.teacher_id) then
    new.user_id := new.teacher_id;
  end if;

  return new;
end
$$;

revoke all on function private.sync_payroll_user_reference() from public;

DROP TRIGGER IF EXISTS salaries_sync_user_reference ON public.salaries;
create trigger salaries_sync_user_reference
before insert or update of teacher_id, user_id on public.salaries
for each row execute function private.sync_payroll_user_reference();

DROP TRIGGER IF EXISTS advances_sync_user_reference ON public.advances;
create trigger advances_sync_user_reference
before insert or update of teacher_id, user_id on public.advances
for each row execute function private.sync_payroll_user_reference();

comment on column public.salaries.user_id is
  'Compte public.users payé. teacher_id est conservé temporairement pour compatibilité frontend et historique.';
comment on column public.advances.user_id is
  'Compte public.users bénéficiaire. teacher_id est conservé temporairement pour compatibilité frontend et historique.';

-- ---------------------------------------------------------------------------
-- P0-16 — RLS de la paie et des avances
-- ---------------------------------------------------------------------------

alter table public.salaries enable row level security;
alter table public.advances enable row level security;
alter table public.direct_primes enable row level security;

-- Retirer les anciennes politiques globales avant de poser les droits précis.
drop policy if exists salaries_direction_all on public.salaries;
drop policy if exists advances_direction_all on public.advances;
drop policy if exists direct_primes_direction_all on public.direct_primes;

-- Direction 1 administre toutes les fiches de salaire.
create policy salaries_direction_select
on public.salaries for select to authenticated
using (private.current_app_role() = 'direction');

create policy salaries_direction_insert
on public.salaries for insert to authenticated
with check (private.current_app_role() = 'direction');

create policy salaries_direction_update
on public.salaries for update to authenticated
using (private.current_app_role() = 'direction')
with check (private.current_app_role() = 'direction');

create policy salaries_direction_delete
on public.salaries for delete to authenticated
using (private.current_app_role() = 'direction');

-- La Caisse doit voir les fiches à verser, mais ne reçoit aucun droit direct
-- d'écriture : le versement passe par mark_salary_paid().
create policy salaries_cashier_select
on public.salaries for select to authenticated
using (private.current_app_role() = 'direction3');

-- Tout membre du personnel, sauf parent, lit seulement sa propre fiche.
create policy salaries_self_select
on public.salaries for select to authenticated
using (
  private.current_app_role() is not null
  and private.current_app_role() <> 'parent'
  and coalesce(user_id, teacher_id) = private.current_app_user_id()
);

-- Même séparation pour les avances.
create policy advances_direction_select
on public.advances for select to authenticated
using (private.current_app_role() = 'direction');

create policy advances_direction_insert
on public.advances for insert to authenticated
with check (private.current_app_role() = 'direction');

create policy advances_direction_update
on public.advances for update to authenticated
using (private.current_app_role() = 'direction')
with check (private.current_app_role() = 'direction');

create policy advances_direction_delete
on public.advances for delete to authenticated
using (private.current_app_role() = 'direction');

create policy advances_cashier_select
on public.advances for select to authenticated
using (private.current_app_role() = 'direction3');

create policy advances_self_select
on public.advances for select to authenticated
using (
  private.current_app_role() is not null
  and private.current_app_role() <> 'parent'
  and coalesce(user_id, teacher_id) = private.current_app_user_id()
);

-- ---------------------------------------------------------------------------
-- P0-17 — primes directes
-- ---------------------------------------------------------------------------

create policy direct_primes_management_select
on public.direct_primes for select to authenticated
using (private.current_app_role() in ('direction', 'direction2'));

create policy direct_primes_teacher_self_select
on public.direct_primes for select to authenticated
using (
  private.current_app_role() = 'enseignant'
  and teacher_id = private.current_app_user_id()
);

create policy direct_primes_direction_insert
on public.direct_primes for insert to authenticated
with check (private.current_app_role() = 'direction');

create policy direct_primes_direction_update
on public.direct_primes for update to authenticated
using (private.current_app_role() = 'direction')
with check (private.current_app_role() = 'direction');

create policy direct_primes_direction_delete
on public.direct_primes for delete to authenticated
using (private.current_app_role() = 'direction');

-- Les tables restent accessibles à authenticated sous RLS ; anon ne reçoit
-- aucun accès aux données de paie.
revoke all on public.salaries, public.advances, public.direct_primes from anon;
grant select, insert, update, delete
  on public.salaries, public.advances, public.direct_primes
  to authenticated;

-- ---------------------------------------------------------------------------
-- La Caisse verse par RPC : elle ne peut jamais changer le montant.
-- ---------------------------------------------------------------------------

create or replace function public.mark_salary_paid(p_salary_id text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_role text;
  v_row public.salaries%rowtype;
begin
  v_role := private.current_app_role();
  if v_role not in ('direction', 'direction3') then
    return jsonb_build_object(
      'ok', false,
      'code', 'ACCESS_DENIED',
      'message', 'Seule la Direction 1 ou la Caisse peut confirmer ce versement.'
    );
  end if;

  select * into v_row
  from public.salaries
  where id = p_salary_id
  for update;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'code', 'SALARY_NOT_FOUND',
      'message', 'Fiche de salaire introuvable.'
    );
  end if;

  if coalesce(v_row.paid, false) or v_row.status = 'paid' then
    return jsonb_build_object(
      'ok', true,
      'code', 'SALARY_ALREADY_PAID',
      'message', 'Ce salaire était déjà marqué comme versé.',
      'data', jsonb_build_object(
        'id', v_row.id,
        'paid', true,
        'status', 'paid',
        'paid_date', v_row.paid_date,
        'net', v_row.net
      )
    );
  end if;

  update public.salaries
  set paid = true,
      status = 'paid',
      paid_date = current_date,
      updated_at = now()
  where id = p_salary_id
  returning * into v_row;

  return jsonb_build_object(
    'ok', true,
    'code', 'SALARY_PAID',
    'message', 'Versement du salaire confirmé.',
    'data', jsonb_build_object(
      'id', v_row.id,
      'paid', v_row.paid,
      'status', v_row.status,
      'paid_date', v_row.paid_date,
      'net', v_row.net
    )
  );
end
$$;

create or replace function public.mark_advance_repaid(p_advance_id text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_role text;
  v_row public.advances%rowtype;
begin
  v_role := private.current_app_role();
  if v_role not in ('direction', 'direction3') then
    return jsonb_build_object(
      'ok', false,
      'code', 'ACCESS_DENIED',
      'message', 'Seule la Direction 1 ou la Caisse peut confirmer ce remboursement.'
    );
  end if;

  select * into v_row
  from public.advances
  where id = p_advance_id
  for update;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'code', 'ADVANCE_NOT_FOUND',
      'message', 'Avance introuvable.'
    );
  end if;

  if coalesce(v_row.repaid, false) or v_row.status = 'repaid' then
    return jsonb_build_object(
      'ok', true,
      'code', 'ADVANCE_ALREADY_REPAID',
      'message', 'Cette avance était déjà marquée comme remboursée.',
      'data', jsonb_build_object(
        'id', v_row.id,
        'repaid', true,
        'status', 'repaid',
        'amount', v_row.amount
      )
    );
  end if;

  update public.advances
  set repaid = true,
      status = 'repaid',
      updated_at = now()
  where id = p_advance_id
  returning * into v_row;

  return jsonb_build_object(
    'ok', true,
    'code', 'ADVANCE_REPAID',
    'message', 'Remboursement de l’avance confirmé.',
    'data', jsonb_build_object(
      'id', v_row.id,
      'repaid', v_row.repaid,
      'status', v_row.status,
      'amount', v_row.amount
    )
  );
end
$$;

revoke all on function public.mark_salary_paid(text) from public, anon;
revoke all on function public.mark_advance_repaid(text) from public, anon;
grant execute on function public.mark_salary_paid(text) to authenticated;
grant execute on function public.mark_advance_repaid(text) to authenticated;

comment on function public.mark_salary_paid(text) is
  'Confirme uniquement le versement d’un salaire. Direction 1 ou Caisse ; aucun montant ne peut être modifié.';
comment on function public.mark_advance_repaid(text) is
  'Confirme uniquement le remboursement d’une avance. Direction 1 ou Caisse ; aucun montant ne peut être modifié.';

commit;
