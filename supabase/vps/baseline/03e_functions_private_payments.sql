-- SchoolSafe VPS baseline - 03e payment helpers

BEGIN;

CREATE OR REPLACE FUNCTION private.compute_payment_state(p_sid text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  s public.students%rowtype;
  cfg public.settings%rowtype;
  yr text;
  control_active boolean := false;
  block_overdue boolean := false;
  warning_days integer := 7;
  grace_days integer := 0;
  obligation_count integer := 0;
  open_count integer := 0;
  partial_count integer := 0;
  overdue_count integer := 0;
  due_soon_count integer := 0;
  next_due date;
  exception_until timestamptz;
  status_code text;
  access_code text;
  allowed_flag boolean;
  term_code text;
  legacy_paid boolean := false;
  today_date date := timezone('Africa/Kinshasa',now())::date;
begin
  select * into s from public.students where id=p_sid and not coalesce(archived,false);
  if not found then
    return jsonb_build_object('student_found',false,'status','unavailable','access_status','unavailable','allowed',false);
  end if;

  if coalesce(s.blocked,false) or coalesce(s.access_blocked,false) then
    return jsonb_build_object('student_found',true,'status','blocked','access_status','blocked','allowed',false,'legacy_mode',false);
  end if;

  select * into cfg from public.settings order by id limit 1;
  yr := coalesce(nullif(cfg.year,''),to_char(today_date,'YYYY'));
  control_active := coalesce((cfg.feescontrol->>'active')::boolean,false);
  block_overdue := coalesce((cfg.feescontrol->>'block_on_overdue')::boolean,false);
  if coalesce(cfg.feescontrol->>'warning_days','') ~ '^\d+$' then warning_days:=greatest((cfg.feescontrol->>'warning_days')::integer,0); end if;
  if coalesce(cfg.feescontrol->>'grace_days','') ~ '^\d+$' then grace_days:=greatest((cfg.feescontrol->>'grace_days')::integer,0); end if;
  term_code := coalesce(cfg.feescontrol->>'t',cfg.currenttrimestre);

  select max(ends_at) into exception_until
  from public.payment_access_exceptions
  where sid=p_sid and revoked_at is null and starts_at<=now() and ends_at>=now();

  with b as (
    select o.id,o.due_date,o.amount_due,
      coalesce(sum(a.amount) filter(where t.status='confirmed'),0)::numeric as paid
    from public.student_fee_obligations o
    left join public.payment_allocations a on a.obligation_id=o.id
    left join public.payment_transactions t on t.id=a.transaction_id
    where o.sid=p_sid and o.school_year=yr and o.active
    group by o.id,o.due_date,o.amount_due
  )
  select count(*)::int,
         count(*) filter(where amount_due-least(amount_due,paid)>0)::int,
         count(*) filter(where paid>0 and amount_due-least(amount_due,paid)>0)::int,
         count(*) filter(where amount_due-least(amount_due,paid)>0 and due_date is not null and due_date+grace_days<today_date)::int,
         count(*) filter(where amount_due-least(amount_due,paid)>0 and due_date between today_date and today_date+warning_days)::int,
         min(due_date) filter(where amount_due-least(amount_due,paid)>0 and due_date>=today_date)
  into obligation_count,open_count,partial_count,overdue_count,due_soon_count,next_due from b;

  if exception_until is not null then
    status_code:='exception'; access_code:='exception'; allowed_flag:=true;
  elsif obligation_count=0 then
    if control_active then
      select exists(select 1 from public.payments p where p.sid=p_sid and p.t=term_code and p.paid) into legacy_paid;
      if legacy_paid then
        status_code:='up_to_date'; access_code:='allowed'; allowed_flag:=true;
      else
        status_code:='overdue'; access_code:='blocked'; allowed_flag:=false;
      end if;
    else
      status_code:='up_to_date'; access_code:='allowed'; allowed_flag:=true;
    end if;
  elsif overdue_count>0 then
    status_code:='overdue';
    if control_active and block_overdue then
      access_code:='blocked'; allowed_flag:=false;
    elsif control_active then
      access_code:='orient'; allowed_flag:=false;
    else
      access_code:='allowed'; allowed_flag:=true;
    end if;
  elsif due_soon_count>0 then
    status_code:='due_soon'; access_code:='allowed'; allowed_flag:=true;
  elsif open_count>0 then
    status_code:=case when partial_count>0 then 'partial' else 'pending' end;
    access_code:='allowed'; allowed_flag:=true;
  else
    status_code:='up_to_date'; access_code:='allowed'; allowed_flag:=true;
  end if;

  return jsonb_build_object(
    'student_found',true,'school_year',yr,'status',status_code,
    'access_status',access_code,'allowed',allowed_flag,
    'control_enabled',control_active,'legacy_mode',obligation_count=0,
    'obligation_count',obligation_count,'open_obligation_count',open_count,
    'overdue_obligation_count',overdue_count,'due_soon_obligation_count',due_soon_count,
    'next_due_date',next_due,'exception_until',exception_until
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.build_fee_summary(p_sid text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION private.touch_payment_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin new.updated_at := now(); return new; end
$function$;

CREATE OR REPLACE FUNCTION private.validate_payment_allocation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  tx public.payment_transactions%rowtype;
  ob public.student_fee_obligations%rowtype;
  tx_alloc numeric(14,2);
  ob_alloc numeric(14,2);
begin
  select * into tx from public.payment_transactions where id = new.transaction_id for update;
  if not found or tx.status <> 'confirmed' then raise exception 'Transaction invalide'; end if;
  select * into ob from public.student_fee_obligations where id = new.obligation_id and active for update;
  if not found then raise exception 'Obligation invalide'; end if;
  if tx.sid <> ob.sid or tx.school_year <> ob.school_year or tx.currency <> ob.currency then
    raise exception 'Allocation incompatible';
  end if;
  select coalesce(sum(amount),0) into tx_alloc from public.payment_allocations where transaction_id=new.transaction_id and id<>new.id;
  if tx_alloc + new.amount > tx.amount then raise exception 'Allocation supérieure au paiement'; end if;
  select coalesce(sum(a.amount),0) into ob_alloc
  from public.payment_allocations a join public.payment_transactions t on t.id=a.transaction_id
  where a.obligation_id=new.obligation_id and a.id<>new.id and t.status='confirmed';
  if ob_alloc + new.amount > ob.amount_due then raise exception 'Allocation supérieure au montant exigible'; end if;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION private.stamp_legacy_payment_provenance()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid text;
  v_role text;
  v_name text;
  v_now timestamptz := now();
begin
  if tg_op = 'DELETE' then
    if coalesce(old.paid, false) then
      raise exception 'Un paiement validé ne peut pas être supprimé directement. Utilisez une contrepassation.' using errcode = '23514';
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE' and coalesce(old.paid, false) then
    if not coalesce(new.paid, false) then
      raise exception 'Un paiement validé ne peut pas être remis à non payé. Utilisez une contrepassation.' using errcode = '23514';
    end if;
    if new.sid is distinct from old.sid or new.t is distinct from old.t then
      raise exception 'L élève et la période d un paiement validé sont immuables.' using errcode = '23514';
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
    select nullif(btrim(u.name), '') into v_name from public.users u where u.id = v_uid and u.status = 'active';
    if v_name is null then raise exception 'Profil SchoolSafe actif introuvable.' using errcode = '42501'; end if;
    new.recorded_by := v_uid;
    new.recorded_by_name := v_name;
    new.recorded_by_role := v_role;
    new.recorded_at := v_now;
    new."by" := v_name;
    new.date := coalesce(nullif(btrim(new.date), ''),to_char(timezone('Africa/Kinshasa', v_now), 'YYYY-MM-DD'));
    perform private.write_audit_event(
      v_uid,v_name,'legacy_payment_confirmed',
      jsonb_build_object('payment_id', new.id,'student_id', new.sid,'term', new.t,'recorded_by_role', v_role,'recorded_at', v_now),
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
$function$;

COMMIT;
