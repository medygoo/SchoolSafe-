-- SchoolSafe VPS baseline - 04l palmares/payroll RPCs

BEGIN;

CREATE OR REPLACE FUNCTION public.get_my_palmares_publications()
 RETURNS TABLE(id text, cid text, year text, trimestre text, status text, formula_version text, snapshot jsonb, version integer, published_at timestamp with time zone)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if private.current_app_role() <> 'parent' then raise exception 'Accès refusé'; end if;
  return query
  select p.id, p.cid, p.year, p.trimestre, p.status, p.formula_version,
         jsonb_build_array(x.result), p.version, p.published_at
  from public.palmares_publications p
  join public.students s
    on s.cid = p.cid
   and s.pid = private.current_app_user_id()
   and coalesce(s.access_parent, false)
  cross join lateral (
    select e as result
    from jsonb_array_elements(p.snapshot) e
    where e ->> 'sid' = s.id
    limit 1
  ) x
  where p.status = 'published';
end
$function$;

CREATE OR REPLACE FUNCTION public.mark_salary_paid(p_salary_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  v_role text;
  v_row public.salaries%rowtype;
begin
  v_role := private.current_app_role();
  if v_role is null or v_role not in ('direction', 'direction3') then
    return jsonb_build_object('ok', false,'code', 'ACCESS_DENIED','message', 'Seule la Direction 1 ou la Caisse peut confirmer ce versement.');
  end if;

  select * into v_row from public.salaries where id = p_salary_id for update;
  if not found then
    return jsonb_build_object('ok', false,'code', 'SALARY_NOT_FOUND','message', 'Fiche de salaire introuvable.');
  end if;

  if coalesce(v_row.paid, false) then
    return jsonb_build_object('ok', true,'code', 'SALARY_ALREADY_PAID','message', 'Ce salaire était déjà marqué comme versé.',
      'data', jsonb_build_object('id', v_row.id,'paid', true,'status', 'paid','paid_date', v_row.paid_date,'amount', v_row.amount,'net', v_row.net));
  end if;

  update public.salaries set paid = true,paid_date = current_date::text,updated = now()::text
  where id = p_salary_id returning * into v_row;

  return jsonb_build_object('ok', true,'code', 'SALARY_PAID','message', 'Versement du salaire confirmé.',
    'data', jsonb_build_object('id', v_row.id,'paid', v_row.paid,'status', 'paid','paid_date', v_row.paid_date,'amount', v_row.amount,'net', v_row.net));
end
$function$;

COMMIT;
