-- Recovered verbatim from supabase_migrations.schema_migrations.
-- This migration was already applied to project lcnronymkccgyltttqry.

create table public.student_fee_obligations (
  id text primary key default ('sfo_' || replace(gen_random_uuid()::text, '-', '')),
  sid text not null references public.students(id) on delete cascade,
  fee_type_id text not null references public.fee_types(id) on delete restrict,
  school_year text not null,
  label text not null,
  installment_no integer not null default 1 check (installment_no > 0),
  amount_due numeric(14,2) not null check (amount_due >= 0),
  currency text not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
  due_date date,
  active boolean not null default true,
  created_by text references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (sid, fee_type_id, school_year, installment_no)
);

create table public.payment_transactions (
  id text primary key default ('ptx_' || replace(gen_random_uuid()::text, '-', '')),
  sid text not null references public.students(id) on delete restrict,
  school_year text not null,
  amount numeric(14,2) not null check (amount > 0),
  currency text not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
  payment_date date not null default (timezone('Africa/Kinshasa', now())::date),
  payment_method text not null default 'cash' check (payment_method in ('cash','bank','mobile_money','other')),
  external_reference text,
  receipt_no text not null unique,
  status text not null default 'confirmed' check (status in ('confirmed','reversed','voided')),
  recorded_by text not null references public.users(id) on delete restrict,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  reversed_at timestamptz,
  reversed_by text references public.users(id) on delete restrict,
  reversal_reason text
);

create table public.payment_allocations (
  id text primary key default ('pal_' || replace(gen_random_uuid()::text, '-', '')),
  transaction_id text not null references public.payment_transactions(id) on delete restrict,
  obligation_id text not null references public.student_fee_obligations(id) on delete restrict,
  amount numeric(14,2) not null check (amount > 0),
  created_at timestamptz not null default now(),
  unique (transaction_id, obligation_id)
);

create table public.payment_access_exceptions (
  id text primary key default ('pae_' || replace(gen_random_uuid()::text, '-', '')),
  sid text not null references public.students(id) on delete cascade,
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null,
  reason text not null check (length(btrim(reason)) >= 3),
  granted_by text not null references public.users(id) on delete restrict,
  revoked_at timestamptz,
  revoked_by text references public.users(id) on delete restrict,
  revoke_reason text,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create table public.payment_scan_log (
  id text primary key default ('psc_' || replace(gen_random_uuid()::text, '-', '')),
  sid text not null references public.students(id) on delete cascade,
  checked_by text references public.users(id) on delete set null,
  checked_role text not null,
  source text not null default 'qr' check (source in ('qr','manual')),
  result_code text not null check (result_code in ('allowed','orient','blocked','exception','unavailable')),
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index idx_sfo_sid_year on public.student_fee_obligations(sid, school_year);
create index idx_sfo_due_active on public.student_fee_obligations(due_date, active) where active;
create index idx_ptx_sid_year_date on public.payment_transactions(sid, school_year, payment_date desc);
create index idx_pal_transaction on public.payment_allocations(transaction_id);
create index idx_pal_obligation on public.payment_allocations(obligation_id);
create index idx_pae_sid_dates on public.payment_access_exceptions(sid, starts_at, ends_at) where revoked_at is null;
create index idx_psc_sid_created on public.payment_scan_log(sid, created_at desc);

create or replace function private.touch_payment_updated_at()
returns trigger language plpgsql security invoker set search_path = '' as $$
begin new.updated_at := now(); return new; end $$;
revoke all on function private.touch_payment_updated_at() from public, anon;

create trigger trg_sfo_touch_updated_at before update on public.student_fee_obligations
for each row execute function private.touch_payment_updated_at();
create trigger trg_ptx_touch_updated_at before update on public.payment_transactions
for each row execute function private.touch_payment_updated_at();

create or replace function private.validate_payment_allocation()
returns trigger language plpgsql security definer set search_path = '' as $$
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
end $$;
revoke all on function private.validate_payment_allocation() from public, anon;
create trigger trg_validate_payment_allocation before insert or update on public.payment_allocations
for each row execute function private.validate_payment_allocation();

alter table public.student_fee_obligations enable row level security;
alter table public.payment_transactions enable row level security;
alter table public.payment_allocations enable row level security;
alter table public.payment_access_exceptions enable row level security;
alter table public.payment_scan_log enable row level security;

revoke all on public.student_fee_obligations, public.payment_transactions, public.payment_allocations, public.payment_access_exceptions, public.payment_scan_log from anon;
grant select,insert,update,delete on public.student_fee_obligations, public.payment_transactions, public.payment_allocations, public.payment_access_exceptions to authenticated;
grant select,insert on public.payment_scan_log to authenticated;

create policy sfo_read on public.student_fee_obligations for select to authenticated
using ((select private.current_app_role()) in ('direction','direction3') or private.owns_student(sid));
create policy sfo_write on public.student_fee_obligations for all to authenticated
using ((select private.current_app_role())='direction')
with check ((select private.current_app_role())='direction');

create policy ptx_read on public.payment_transactions for select to authenticated
using ((select private.current_app_role()) in ('direction','direction3') or private.owns_student(sid));
create policy ptx_insert on public.payment_transactions for insert to authenticated
with check ((select private.current_app_role()) in ('direction','direction3') and recorded_by=(select private.current_app_user_id()) and status='confirmed');
create policy ptx_update on public.payment_transactions for update to authenticated
using ((select private.current_app_role())='direction')
with check ((select private.current_app_role())='direction');

create policy pal_read on public.payment_allocations for select to authenticated
using (exists(select 1 from public.payment_transactions t where t.id=transaction_id and ((select private.current_app_role()) in ('direction','direction3') or private.owns_student(t.sid))));
create policy pal_insert on public.payment_allocations for insert to authenticated
with check ((select private.current_app_role()) in ('direction','direction3'));
create policy pal_update on public.payment_allocations for update to authenticated
using ((select private.current_app_role())='direction') with check ((select private.current_app_role())='direction');
create policy pal_delete on public.payment_allocations for delete to authenticated
using ((select private.current_app_role())='direction');

create policy pae_read on public.payment_access_exceptions for select to authenticated
using ((select private.current_app_role()) in ('direction','direction3') or private.owns_student(sid));
create policy pae_write on public.payment_access_exceptions for all to authenticated
using ((select private.current_app_role())='direction') with check ((select private.current_app_role())='direction');

create policy psc_read on public.payment_scan_log for select to authenticated
using ((select private.current_app_role()) in ('direction','direction3'));
create policy psc_insert on public.payment_scan_log for insert to authenticated
with check (private.can_scan() and checked_by=(select private.current_app_user_id()) and checked_role=(select private.current_app_role()));

create or replace function private.compute_payment_state(p_sid text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
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
  if not found then return jsonb_build_object('student_found',false,'status','unavailable','access_status','unavailable','allowed',false); end if;
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
  select max(ends_at) into exception_until from public.payment_access_exceptions
   where sid=p_sid and revoked_at is null and starts_at<=now() and ends_at>=now();
  with b as (
    select o.id,o.due_date,o.amount_due,coalesce(sum(a.amount) filter(where t.status='confirmed'),0)::numeric as paid
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
  if exception_until is not null then status_code:='exception'; access_code:='exception'; allowed_flag:=true;
  elsif obligation_count=0 then
    if control_active then
      select exists(select 1 from public.payments p where p.sid=p_sid and p.t=term_code and p.paid) into legacy_paid;
      if legacy_paid then status_code:='up_to_date'; access_code:='allowed'; allowed_flag:=true;
      else status_code:='overdue'; access_code:='blocked'; allowed_flag:=false; end if;
    else status_code:='up_to_date'; access_code:='allowed'; allowed_flag:=true; end if;
  elsif overdue_count>0 then status_code:='overdue';
    if control_active and block_overdue then access_code:='blocked'; allowed_flag:=false;
    else access_code:='orient'; allowed_flag:=true; end if;
  elsif due_soon_count>0 then status_code:='due_soon'; access_code:='allowed'; allowed_flag:=true;
  elsif open_count>0 then status_code:=case when partial_count>0 then 'partial' else 'pending' end; access_code:='allowed'; allowed_flag:=true;
  else status_code:='up_to_date'; access_code:='allowed'; allowed_flag:=true; end if;
  return jsonb_build_object('student_found',true,'school_year',yr,'status',status_code,'access_status',access_code,'allowed',allowed_flag,'control_enabled',control_active,'legacy_mode',obligation_count=0,'obligation_count',obligation_count,'open_obligation_count',open_count,'overdue_obligation_count',overdue_count,'due_soon_obligation_count',due_soon_count,'next_due_date',next_due,'exception_until',exception_until);
end $$;
revoke all on function private.compute_payment_state(text) from public,anon;
grant execute on function private.compute_payment_state(text) to authenticated,service_role;

create or replace function private.build_fee_summary(p_sid text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  st jsonb;
  stu public.students%rowtype;
  yr text;
  totals jsonb;
  obligations jsonb;
  receipts jsonb;
  today_date date:=timezone('Africa/Kinshasa',now())::date;
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
    select currency,sum(amount_due)::numeric(14,2) due,sum(least(amount_due,paid))::numeric(14,2) paid,sum(greatest(amount_due-paid,0))::numeric(14,2) balance
    from b group by currency
  )
  select coalesce(jsonb_agg(jsonb_build_object('currency',currency,'amount_due',due,'amount_paid',paid,'balance',balance) order by currency),'[]'::jsonb) into totals from agg;
  with b as (
    select o.id,o.fee_type_id,o.label,o.installment_no,o.amount_due,o.currency,o.due_date,
      coalesce(sum(a.amount) filter(where t.status='confirmed'),0)::numeric as paid
    from public.student_fee_obligations o
    left join public.payment_allocations a on a.obligation_id=o.id
    left join public.payment_transactions t on t.id=a.transaction_id
    where o.sid=p_sid and o.school_year=yr and o.active
    group by o.id,o.fee_type_id,o.label,o.installment_no,o.amount_due,o.currency,o.due_date
  )
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'fee_type_id',fee_type_id,'label',label,'installment_no',installment_no,'due_date',due_date,'amount_due',amount_due,'amount_paid',least(amount_due,paid),'balance',greatest(amount_due-paid,0),'currency',currency,'status',case when greatest(amount_due-paid,0)=0 then 'paid' when due_date<today_date then 'overdue' when paid>0 then 'partial' else 'pending' end) order by due_date nulls last,installment_no),'[]'::jsonb) into obligations from b;
  select coalesce(jsonb_agg(jsonb_build_object('id',id,'receipt_no',receipt_no,'payment_date',payment_date,'amount',amount,'currency',currency,'payment_method',payment_method,'external_reference',external_reference,'status',status) order by payment_date desc,created_at desc),'[]'::jsonb) into receipts
  from public.payment_transactions where sid=p_sid and school_year=yr;
  return st||jsonb_build_object('student_id',stu.id,'student_name',stu.name,'matricule',stu.mat,'class_id',stu.cid,'totals_by_currency',totals,'obligations',obligations,'receipts',receipts);
end $$;
revoke all on function private.build_fee_summary(text) from public,anon;
grant execute on function private.build_fee_summary(text) to authenticated,service_role;

create or replace function public.get_parent_fee_summary(p_sid text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
begin
 if private.current_app_role()<>'parent' or not private.owns_student(p_sid) then raise exception 'Accès refusé'; end if;
 return private.build_fee_summary(p_sid);
end $$;

create or replace function public.get_cashier_student_fee_detail(p_sid text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
begin
 if private.current_app_role() not in ('direction','direction3') then raise exception 'Accès refusé'; end if;
 return private.build_fee_summary(p_sid);
end $$;

create or replace function public.get_gate_access_status(p_sid text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
 st jsonb; stu public.students%rowtype; cls text; code text; instruction text;
begin
 if not private.can_scan() then raise exception 'Accès refusé'; end if;
 st:=private.compute_payment_state(p_sid);
 if not coalesce((st->>'student_found')::boolean,false) then return jsonb_build_object('student_id',p_sid,'access_status','unavailable','instruction','Contrôle manuel requis','checked_at',now()); end if;
 select * into stu from public.students where id=p_sid;
 select name into cls from public.classes where id=stu.cid;
 code:=coalesce(st->>'access_status','unavailable');
 instruction:=case code when 'allowed' then 'Accès autorisé' when 'exception' then 'Accès temporairement autorisé' when 'orient' then 'Accès autorisé — suivi administratif requis' when 'blocked' then 'Accès non autorisé — contactez la Direction générale' else 'Contrôle manuel requis' end;
 return jsonb_build_object('student_id',stu.id,'student_name',stu.name,'matricule',stu.mat,'class_id',stu.cid,'class_name',cls,'photo_url',stu.photo,'access_status',code,'instruction',instruction,'checked_at',now());
end $$;

create or replace function public.check_gate_access_status(p_sid text,p_source text default 'qr')
returns jsonb language plpgsql security invoker set search_path='' as $$
declare r jsonb; code text; src text:=case when p_source='manual' then 'manual' else 'qr' end;
begin
 if not private.can_scan() then raise exception 'Accès refusé'; end if;
 r:=public.get_gate_access_status(p_sid); code:=coalesce(r->>'access_status','unavailable');
 insert into public.payment_scan_log(sid,checked_by,checked_role,source,result_code,details)
 values(p_sid,private.current_app_user_id(),private.current_app_role(),src,case when code in ('allowed','orient','blocked','exception') then code else 'unavailable' end,jsonb_build_object('instruction',r->>'instruction'));
 return r;
end $$;

create or replace function public.record_payment_transaction(p_sid text,p_amount numeric,p_currency text default 'USD',p_payment_method text default 'cash',p_external_reference text default null,p_note text default null,p_payment_date date default null,p_allocations jsonb default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare
 role_code text:=private.current_app_role(); uid text:=private.current_app_user_id(); yr text; txid text:='ptx_'||replace(gen_random_uuid()::text,'-',''); receipt text:='SS-'||to_char(timezone('Africa/Kinshasa',now()),'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)); curr text:=upper(btrim(coalesce(p_currency,'USD'))); method text:=lower(btrim(coalesce(p_payment_method,'cash'))); remaining numeric(14,2):=p_amount; allocated numeric(14,2):=0; rec record; piece numeric(14,2); item jsonb;
begin
 if role_code not in ('direction','direction3') then raise exception 'Accès refusé'; end if;
 if p_amount is null or p_amount<=0 then raise exception 'Montant invalide'; end if;
 if curr!~'^[A-Z]{3}$' or method not in ('cash','bank','mobile_money','other') then raise exception 'Paramètres de paiement invalides'; end if;
 if not exists(select 1 from public.students where id=p_sid and not coalesce(archived,false)) then raise exception 'Élève introuvable'; end if;
 select coalesce(nullif(year,''),to_char(timezone('Africa/Kinshasa',now()),'YYYY')) into yr from public.settings order by id limit 1;
 insert into public.payment_transactions(id,sid,school_year,amount,currency,payment_date,payment_method,external_reference,receipt_no,status,recorded_by,note)
 values(txid,p_sid,yr,p_amount,curr,coalesce(p_payment_date,timezone('Africa/Kinshasa',now())::date),method,nullif(btrim(p_external_reference),''),receipt,'confirmed',uid,nullif(btrim(p_note),''));
 if p_allocations is not null and jsonb_typeof(p_allocations)='array' and jsonb_array_length(p_allocations)>0 then
  for item in select value from jsonb_array_elements(p_allocations) loop
   piece:=(item->>'amount')::numeric; if piece is null or piece<=0 then raise exception 'Allocation invalide'; end if;
   insert into public.payment_allocations(transaction_id,obligation_id,amount) values(txid,item->>'obligation_id',piece); allocated:=allocated+piece;
  end loop;
  if allocated<>p_amount then raise exception 'Somme des allocations incorrecte'; end if;
 else
  for rec in
   with b as(select o.id,o.due_date,o.installment_no,o.amount_due,coalesce(sum(a.amount) filter(where t.status='confirmed'),0)::numeric paid from public.student_fee_obligations o left join public.payment_allocations a on a.obligation_id=o.id left join public.payment_transactions t on t.id=a.transaction_id where o.sid=p_sid and o.school_year=yr and o.currency=curr and o.active group by o.id,o.due_date,o.installment_no,o.amount_due)
   select id,greatest(amount_due-paid,0)::numeric(14,2) outstanding from b where amount_due-paid>0 order by due_date nulls last,installment_no,id
  loop exit when remaining<=0; piece:=least(remaining,rec.outstanding); insert into public.payment_allocations(transaction_id,obligation_id,amount) values(txid,rec.id,piece); remaining:=remaining-piece; end loop;
  if remaining<>0 then raise exception 'Montant supérieur au solde exigible ou aucune obligation configurée'; end if;
 end if;
 return jsonb_build_object('transaction_id',txid,'receipt_no',receipt,'student_id',p_sid,'amount',p_amount,'currency',curr,'payment_date',coalesce(p_payment_date,timezone('Africa/Kinshasa',now())::date),'status','confirmed');
end $$;

create or replace function public.grant_payment_access_exception(p_sid text,p_ends_at timestamptz,p_reason text,p_starts_at timestamptz default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare idv text:='pae_'||replace(gen_random_uuid()::text,'-',''); startv timestamptz:=coalesce(p_starts_at,now());
begin
 if private.current_app_role()<>'direction' then raise exception 'Accès refusé'; end if;
 if p_ends_at is null or p_ends_at<=startv or length(btrim(coalesce(p_reason,'')))<3 then raise exception 'Dérogation invalide'; end if;
 insert into public.payment_access_exceptions(id,sid,starts_at,ends_at,reason,granted_by) values(idv,p_sid,startv,p_ends_at,btrim(p_reason),private.current_app_user_id());
 return jsonb_build_object('exception_id',idv,'student_id',p_sid,'starts_at',startv,'ends_at',p_ends_at);
end $$;

create or replace function public.revoke_payment_access_exception(p_exception_id text,p_reason text)
returns jsonb language plpgsql security invoker set search_path='' as $$
begin
 if private.current_app_role()<>'direction' then raise exception 'Accès refusé'; end if;
 if length(btrim(coalesce(p_reason,'')))<3 then raise exception 'Motif obligatoire'; end if;
 update public.payment_access_exceptions set revoked_at=now(),revoked_by=private.current_app_user_id(),revoke_reason=btrim(p_reason) where id=p_exception_id and revoked_at is null;
 if not found then raise exception 'Dérogation introuvable ou déjà révoquée'; end if;
 return jsonb_build_object('exception_id',p_exception_id,'status','revoked');
end $$;

revoke all on function public.get_parent_fee_summary(text), public.get_cashier_student_fee_detail(text), public.get_gate_access_status(text), public.check_gate_access_status(text,text), public.record_payment_transaction(text,numeric,text,text,text,text,date,jsonb), public.grant_payment_access_exception(text,timestamptz,text,timestamptz), public.revoke_payment_access_exception(text,text) from public,anon;
grant execute on function public.get_parent_fee_summary(text), public.get_cashier_student_fee_detail(text), public.get_gate_access_status(text), public.check_gate_access_status(text,text), public.record_payment_transaction(text,numeric,text,text,text,text,date,jsonb), public.grant_payment_access_exception(text,timestamptz,text,timestamptz), public.revoke_payment_access_exception(text,text) to authenticated;

create or replace function public.evaluate_student_access(p_sid text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare st jsonb; role_code text:=private.current_app_role(); code text; public_reason text; financial_reason text;
begin
 if not private.can_scan() then raise exception 'Accès refusé'; end if;
 st:=private.compute_payment_state(p_sid); code:=coalesce(st->>'access_status','unavailable');
 public_reason:=case code when 'allowed' then 'Accès autorisé' when 'exception' then 'Accès temporairement autorisé' when 'orient' then 'Accès autorisé — suivi administratif requis' when 'blocked' then 'Accès non autorisé — contactez la Direction générale' else 'Contrôle manuel requis' end;
 if role_code in ('direction','direction3') then financial_reason:=case coalesce(st->>'status','unavailable') when 'overdue' then 'Frais en retard' when 'partial' then 'Paiement partiel' when 'pending' then 'Échéancier non couvert' when 'due_soon' then 'Échéance proche' when 'exception' then 'Dérogation temporaire active' when 'blocked' then 'Blocage administratif actif' else null end; end if;
 return jsonb_build_object('allowed',coalesce((st->>'allowed')::boolean,false),'public_reason',public_reason,'financial_reason',financial_reason,'access_status',code);
end $$;
revoke all on function public.evaluate_student_access(text) from public,anon;
grant execute on function public.evaluate_student_access(text) to authenticated,service_role;
