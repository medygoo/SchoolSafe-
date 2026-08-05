-- SchoolSafe — consolide les politiques SELECT de paie
-- Même matrice de droits, une seule politique permissive par table.

begin;

-- salaries
drop policy if exists salaries_direction_select on public.salaries;
drop policy if exists salaries_cashier_select on public.salaries;
drop policy if exists salaries_self_select on public.salaries;

create policy salaries_authorized_select
on public.salaries for select to authenticated
using (
  private.current_app_role() = 'direction'
  or private.current_app_role() = 'direction3'
  or (
    private.current_app_role() is not null
    and private.current_app_role() <> 'parent'
    and coalesce(user_id, teacher_id) = private.current_app_user_id()
  )
);

-- advances
drop policy if exists advances_direction_select on public.advances;
drop policy if exists advances_cashier_select on public.advances;
drop policy if exists advances_self_select on public.advances;

create policy advances_authorized_select
on public.advances for select to authenticated
using (
  private.current_app_role() = 'direction'
  or private.current_app_role() = 'direction3'
  or (
    private.current_app_role() is not null
    and private.current_app_role() <> 'parent'
    and coalesce(user_id, teacher_id) = private.current_app_user_id()
  )
);

-- direct_primes
drop policy if exists direct_primes_management_select on public.direct_primes;
drop policy if exists direct_primes_teacher_self_select on public.direct_primes;

create policy direct_primes_authorized_select
on public.direct_primes for select to authenticated
using (
  private.current_app_role() in ('direction', 'direction2')
  or (
    private.current_app_role() = 'enseignant'
    and teacher_id = private.current_app_user_id()
  )
);

commit;
