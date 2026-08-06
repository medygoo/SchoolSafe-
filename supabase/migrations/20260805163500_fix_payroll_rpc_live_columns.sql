-- SchoolSafe — correctif du contrat de versement de salaire
-- Le schéma vivant utilise amount/paid/paid_date/updated, pas status/updated_at.

begin;

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
  if v_role is null or v_role not in ('direction', 'direction3') then
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

  if coalesce(v_row.paid, false) then
    return jsonb_build_object(
      'ok', true,
      'code', 'SALARY_ALREADY_PAID',
      'message', 'Ce salaire était déjà marqué comme versé.',
      'data', jsonb_build_object(
        'id', v_row.id,
        'paid', true,
        'status', 'paid',
        'paid_date', v_row.paid_date,
        'amount', v_row.amount,
        'net', v_row.net
      )
    );
  end if;

  update public.salaries
  set paid = true,
      paid_date = current_date::text,
      updated = now()::text
  where id = p_salary_id
  returning * into v_row;

  return jsonb_build_object(
    'ok', true,
    'code', 'SALARY_PAID',
    'message', 'Versement du salaire confirmé.',
    'data', jsonb_build_object(
      'id', v_row.id,
      'paid', v_row.paid,
      'status', 'paid',
      'paid_date', v_row.paid_date,
      'amount', v_row.amount,
      'net', v_row.net
    )
  );
end
$$;

revoke all on function public.mark_salary_paid(text) from public, anon;
grant execute on function public.mark_salary_paid(text) to authenticated;

comment on function public.mark_salary_paid(text) is
  'Confirme uniquement le versement d’un salaire dans le schéma vivant amount/paid/paid_date/updated. Direction 1 ou Caisse ; aucun montant ne peut être modifié.';

commit;
