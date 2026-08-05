create or replace function public.record_payment_transaction(
  p_sid text,
  p_amount numeric,
  p_currency text default 'USD'::text,
  p_payment_method text default 'cash'::text,
  p_external_reference text default null::text,
  p_note text default null::text,
  p_payment_date date default null::date,
  p_allocations jsonb default null::jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  role_code text := private.current_app_role();
  uid text := private.current_app_user_id();
  yr text;
  txid text := 'ptx_' || replace(gen_random_uuid()::text, '-', '');
  receipt text := 'SS-' || to_char(timezone('Africa/Kinshasa', now()), 'YYYYMMDD') || '-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8));
  curr text := upper(btrim(coalesce(p_currency, 'USD')));
  method text := lower(btrim(coalesce(p_payment_method, 'cash')));
  remaining numeric(14,2) := p_amount;
  allocated numeric(14,2) := 0;
  rec record;
  piece numeric(14,2);
  item jsonb;
begin
  if role_code not in ('direction', 'direction3') then
    raise exception 'Accès refusé' using errcode = '42501';
  end if;

  if uid is null then
    raise exception 'Compte SchoolSafe non relié' using errcode = '42501';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Montant invalide' using errcode = '22023';
  end if;

  if curr !~ '^[A-Z]{3}$' or method not in ('cash', 'bank', 'mobile_money', 'other') then
    raise exception 'Paramètres de paiement invalides' using errcode = '22023';
  end if;

  if not exists(
    select 1 from public.students
    where id = p_sid and not coalesce(archived, false)
  ) then
    raise exception 'Élève introuvable' using errcode = 'P0002';
  end if;

  yr := private.current_school_year();

  insert into public.payment_transactions(
    id, sid, school_year, amount, currency, payment_date, payment_method,
    external_reference, receipt_no, status, recorded_by, note
  ) values (
    txid, p_sid, yr, p_amount, curr,
    coalesce(p_payment_date, timezone('Africa/Kinshasa', now())::date),
    method, nullif(btrim(p_external_reference), ''), receipt, 'confirmed', uid,
    nullif(btrim(p_note), '')
  );

  if p_allocations is not null
     and jsonb_typeof(p_allocations) = 'array'
     and jsonb_array_length(p_allocations) > 0 then
    for item in select value from jsonb_array_elements(p_allocations)
    loop
      piece := (item->>'amount')::numeric;
      if piece is null or piece <= 0 then
        raise exception 'Allocation invalide' using errcode = '22023';
      end if;
      insert into public.payment_allocations(transaction_id, obligation_id, amount)
      values (txid, item->>'obligation_id', piece);
      allocated := allocated + piece;
    end loop;

    if allocated <> p_amount then
      raise exception 'Somme des allocations incorrecte' using errcode = '22023';
    end if;
  else
    for rec in
      with balances as (
        select
          o.id,
          o.due_date,
          o.installment_no,
          o.amount_due,
          coalesce(sum(a.amount) filter (where t.status = 'confirmed'), 0)::numeric as paid
        from public.student_fee_obligations o
        left join public.payment_allocations a on a.obligation_id = o.id
        left join public.payment_transactions t on t.id = a.transaction_id
        where o.sid = p_sid
          and o.school_year = yr
          and o.currency = curr
          and o.active
        group by o.id, o.due_date, o.installment_no, o.amount_due
      )
      select id, greatest(amount_due - paid, 0)::numeric(14,2) as outstanding
      from balances
      where amount_due - paid > 0
      order by due_date nulls last, installment_no, id
    loop
      exit when remaining <= 0;
      piece := least(remaining, rec.outstanding);
      insert into public.payment_allocations(transaction_id, obligation_id, amount)
      values (txid, rec.id, piece);
      remaining := remaining - piece;
    end loop;

    if remaining <> 0 then
      raise exception 'Montant supérieur au solde exigible ou aucune obligation configurée' using errcode = '22023';
    end if;
  end if;

  return jsonb_build_object(
    'transaction_id', txid,
    'receipt_no', receipt,
    'student_id', p_sid,
    'amount', p_amount,
    'currency', curr,
    'payment_date', coalesce(p_payment_date, timezone('Africa/Kinshasa', now())::date),
    'school_year', yr,
    'status', 'confirmed'
  );
end;
$$;

revoke all on function public.record_payment_transaction(text, numeric, text, text, text, text, date, jsonb) from public;
revoke all on function public.record_payment_transaction(text, numeric, text, text, text, text, date, jsonb) from anon;
grant execute on function public.record_payment_transaction(text, numeric, text, text, text, text, date, jsonb) to authenticated;
grant execute on function public.record_payment_transaction(text, numeric, text, text, text, text, date, jsonb) to service_role;

comment on function public.record_payment_transaction(text, numeric, text, text, text, text, date, jsonb) is
  'Records a confirmed payment for Direction 1 or Caisse using the server-only current school year source.';
