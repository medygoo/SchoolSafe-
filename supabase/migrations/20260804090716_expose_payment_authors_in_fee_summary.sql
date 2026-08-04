-- Include immutable payment and reversal author snapshots in fee summaries.

create or replace function private.build_fee_summary(p_sid text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  st jsonb;
  stu public.students%rowtype;
  yr text;
  totals jsonb;
  obligations jsonb;
  receipts jsonb;
  today_date date := timezone('Africa/Kinshasa',now())::date;
begin
  st:=private.compute_payment_state(p_sid);
  if not coalesce((st->>'student_found')::boolean,false) then return st; end if;
  select * into stu from public.students where id=p_sid;
  yr:=st->>'school_year';

  with b as (
    select o.id,o.fee_type_id,o.label,o.installment_no,o.amount_due,o.currency,o.due_date,
      coalesce(sum(a.amount) filter(where t.status='confirmed'),0)::numeric as paid
    from public.student_fee_obligations o
    left join public.payment_allocations a on a.obligation_id=o.id
    left join public.payment_transactions t on t.id=a.transaction_id
    where o.sid=p_sid and o.school_year=yr and o.active
    group by o.id,o.fee_type_id,o.label,o.installment_no,o.amount_due,o.currency,o.due_date
  ), agg as (
    select currency,sum(amount_due)::numeric(14,2) due,
      sum(least(amount_due,paid))::numeric(14,2) paid,
      sum(greatest(amount_due-paid,0))::numeric(14,2) balance
    from b group by currency
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'currency',currency,'amount_due',due,'amount_paid',paid,'balance',balance
  ) order by currency),'[]'::jsonb) into totals from agg;

  with b as (
    select o.id,o.fee_type_id,o.label,o.installment_no,o.amount_due,o.currency,o.due_date,
      coalesce(sum(a.amount) filter(where t.status='confirmed'),0)::numeric as paid
    from public.student_fee_obligations o
    left join public.payment_allocations a on a.obligation_id=o.id
    left join public.payment_transactions t on t.id=a.transaction_id
    where o.sid=p_sid and o.school_year=yr and o.active
    group by o.id,o.fee_type_id,o.label,o.installment_no,o.amount_due,o.currency,o.due_date
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',id,'fee_type_id',fee_type_id,'label',label,'installment_no',installment_no,
    'due_date',due_date,'amount_due',amount_due,'amount_paid',least(amount_due,paid),
    'balance',greatest(amount_due-paid,0),'currency',currency,
    'status',case when greatest(amount_due-paid,0)=0 then 'paid'
      when due_date<today_date then 'overdue' when paid>0 then 'partial' else 'pending' end
  ) order by due_date nulls last,installment_no),'[]'::jsonb) into obligations from b;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',id,'receipt_no',receipt_no,'payment_date',payment_date,'amount',amount,
    'currency',currency,'payment_method',payment_method,
    'external_reference',external_reference,'status',status,
    'recorded_by',recorded_by,'recorded_by_name',recorded_by_name,
    'recorded_by_role',recorded_by_role,'created_at',created_at,
    'reversed_at',reversed_at,'reversed_by',reversed_by,
    'reversed_by_name',reversed_by_name,'reversed_by_role',reversed_by_role,
    'reversal_reason',reversal_reason
  ) order by payment_date desc,created_at desc),'[]'::jsonb) into receipts
  from public.payment_transactions where sid=p_sid and school_year=yr;

  return st||jsonb_build_object(
    'contract_version',2,'student_id',stu.id,'student_name',stu.name,
    'matricule',stu.mat,'class_id',stu.cid,
    'totals_by_currency',totals,'obligations',obligations,'receipts',receipts
  );
end;
$$;

comment on function private.build_fee_summary(text) is
  'Fee summary contract v2 with immutable payment and reversal author snapshots.';
