-- SchoolSafe VPS baseline - 03i secure payment receipt counter

BEGIN;

CREATE OR REPLACE FUNCTION private.next_payment_receipt_no(p_school_year text)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

COMMIT;
