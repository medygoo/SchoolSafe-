-- Payment contract v2: immutable author snapshot, annual receipt and audited reversal.

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
  actor_name text;
  yr text;
  txid text := 'ptx_' || replace(gen_random_uuid()::text, '-', '');
  receipt text;
  curr text := upper(btrim(coalesce(p_currency, 'USD')));
  method text := lower(btrim(coalesce(p_payment_method, 'cash')));
  remaining numeric(14,2) := p_amount;
  allocated numeric(14,2) := 0;
  rec record;
  piece numeric(14,2);
  item jsonb;
  v_payment_date date := coalesce(p_payment_date, timezone('Africa/Kinshasa', now())::date);
begin
  if role_code not in ('direction', 'direction3') then
    raise exception 'Accès refusé' using errcode = '42501';
  end if;
  if uid is null then
    raise exception 'Compte SchoolSafe non relié' using errcode = '42501';
  end if;

  select u.name into actor_name from public.users u
  where u.id = uid and u.status = 'active';
  if nullif(btrim(coalesce(actor_name, '')), '') is null then
    raise exception 'Profil SchoolSafe actif introuvable' using errcode = '42501';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Montant invalide' using errcode = '22023';
  end if;
  if curr !~ '^[A-Z]{3}$' or method not in ('cash', 'bank', 'mobile_money', 'other') then
    raise exception 'Paramètres de paiement invalides' using errcode = '22023';
  end if;
  if not exists(select 1 from public.students where id = p_sid and not coalesce(archived, false)) then
    raise exception 'Élève introuvable ou archivé' using errcode = 'P0002';
  end if;

  yr := private.current_school_year();
  receipt := private.next_payment_receipt_no(yr);

  insert into public.payment_transactions(
    id, sid, school_year, amount, currency, payment_date, payment_method,
    external_reference, receipt_no, status, recorded_by,
    recorded_by_name, recorded_by_role, note
  ) values (
    txid, p_sid, yr, p_amount, curr, v_payment_date,
    method, nullif(btrim(p_external_reference), ''), receipt, 'confirmed', uid,
    actor_name, role_code, nullif(btrim(p_note), '')
  );

  if p_allocations is not null and jsonb_typeof(p_allocations) = 'array'
     and jsonb_array_length(p_allocations) > 0 then
    for item in select value from jsonb_array_elements(p_allocations)
    loop
      begin piece := (item->>'amount')::numeric;
      exception when others then raise exception 'Allocation invalide' using errcode = '22023'; end;

      if nullif(btrim(coalesce(item->>'obligation_id', '')), '') is null or piece is null or piece <= 0 then
        raise exception 'Allocation invalide' using errcode = '22023';
      end if;
      if not exists(
        select 1 from public.student_fee_obligations o
        where o.id = item->>'obligation_id' and o.sid = p_sid
          and o.school_year = yr and o.currency = curr and o.active
      ) then
        raise exception 'Obligation incompatible avec ce paiement' using errcode = '22023';
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
        select o.id,o.due_date,o.installment_no,o.amount_due,
          coalesce(sum(a.amount) filter(where t.status='confirmed'),0)::numeric as paid
        from public.student_fee_obligations o
        left join public.payment_allocations a on a.obligation_id=o.id
        left join public.payment_transactions t on t.id=a.transaction_id
        where o.sid=p_sid and o.school_year=yr and o.currency=curr and o.active
        group by o.id,o.due_date,o.installment_no,o.amount_due
      )
      select id,greatest(amount_due-paid,0)::numeric(14,2) as outstanding
      from balances where amount_due-paid>0
      order by due_date nulls last,installment_no,id
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
    'contract_version',2,'transaction_id',txid,'receipt_no',receipt,'student_id',p_sid,
    'amount',p_amount,'currency',curr,'payment_date',v_payment_date,'school_year',yr,
    'status','confirmed','recorded_by',uid,'recorded_by_name',actor_name,
    'recorded_by_role',role_code,'created_at',now()
  );
end;
$$;

revoke all on function public.record_payment_transaction(text,numeric,text,text,text,text,date,jsonb) from public;
revoke all on function public.record_payment_transaction(text,numeric,text,text,text,text,date,jsonb) from anon;
grant execute on function public.record_payment_transaction(text,numeric,text,text,text,text,date,jsonb) to authenticated;
grant execute on function public.record_payment_transaction(text,numeric,text,text,text,text,date,jsonb) to service_role;

create or replace function public.reverse_payment_transaction(p_transaction_id text,p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := private.current_app_role();
  v_uid text := private.current_app_user_id();
  v_actor_name text;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_tx public.payment_transactions%rowtype;
  v_reversed_at timestamptz := now();
begin
  if v_role not in ('direction','direction3') or v_uid is null then
    raise exception 'Accès refusé' using errcode='42501';
  end if;
  select u.name into v_actor_name from public.users u
  where u.id=v_uid and u.status='active';
  if nullif(btrim(coalesce(v_actor_name,'')),'') is null then
    raise exception 'Profil SchoolSafe actif introuvable' using errcode='42501';
  end if;
  if nullif(btrim(coalesce(p_transaction_id,'')),'') is null then
    raise exception 'Transaction requise' using errcode='22023';
  end if;
  if length(v_reason)<5 or length(v_reason)>500 then
    raise exception 'Motif de contrepassation invalide' using errcode='22023';
  end if;

  select * into v_tx from public.payment_transactions
  where id=p_transaction_id for update;
  if not found then raise exception 'Transaction introuvable' using errcode='P0002'; end if;
  if v_tx.status<>'confirmed' then
    raise exception 'Transaction déjà annulée ou indisponible' using errcode='23514';
  end if;

  update public.payment_transactions
  set status='reversed',reversed_at=v_reversed_at,reversed_by=v_uid,
      reversed_by_name=v_actor_name,reversed_by_role=v_role,
      reversal_reason=v_reason,updated_at=v_reversed_at
  where id=v_tx.id;

  return jsonb_build_object(
    'contract_version',2,'transaction_id',v_tx.id,'student_id',v_tx.sid,
    'receipt_no',v_tx.receipt_no,'amount',v_tx.amount,'currency',v_tx.currency,
    'status','reversed','reversed_by',v_uid,'reversed_by_name',v_actor_name,
    'reversed_by_role',v_role,'reversed_at',v_reversed_at,'reason',v_reason
  );
end;
$$;

revoke all on function public.reverse_payment_transaction(text,text) from public;
revoke all on function public.reverse_payment_transaction(text,text) from anon;
grant execute on function public.reverse_payment_transaction(text,text) to authenticated;
grant execute on function public.reverse_payment_transaction(text,text) to service_role;

comment on function public.record_payment_transaction(text,numeric,text,text,text,text,date,jsonb) is
  'Contract v2: confirmed payment with immutable author snapshot and annual sequential receipt.';
comment on function public.reverse_payment_transaction(text,text) is
  'Contract v2: reversal without deletion, with immutable reversal author snapshot.';
