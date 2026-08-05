-- Scanner contract v2: `orient` means allowed=false and no entry may be recorded.

create or replace function private.compute_payment_state(p_sid text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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
$$;

create or replace function public.evaluate_student_access(p_sid text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  st jsonb;
  role_code text := private.current_app_role();
  code text;
  public_reason text;
  financial_reason text;
begin
  if not private.can_scan() then raise exception 'Accès refusé' using errcode='42501'; end if;
  st := private.compute_payment_state(p_sid);
  code := coalesce(st->>'access_status','unavailable');
  public_reason := case code
    when 'allowed' then 'Accès autorisé'
    when 'exception' then 'Accès temporairement autorisé'
    when 'orient' then 'Accès en attente — orienter vers la Caisse'
    when 'blocked' then 'Accès non autorisé — orienter vers la Caisse'
    else 'Contrôle manuel requis'
  end;
  if role_code in ('direction','direction3') then
    financial_reason := case coalesce(st->>'status','unavailable')
      when 'overdue' then 'Frais en retard'
      when 'partial' then 'Paiement partiel'
      when 'pending' then 'Échéancier non couvert'
      when 'due_soon' then 'Échéance proche'
      when 'exception' then 'Dérogation temporaire active'
      when 'blocked' then 'Blocage administratif actif'
      else null end;
  end if;
  return jsonb_build_object(
    'contract_version',2,'allowed',coalesce((st->>'allowed')::boolean,false),
    'public_reason',public_reason,'financial_reason',financial_reason,
    'access_status',code,'checked_at',now()
  );
end;
$$;

create or replace function public.get_gate_access_status(p_sid text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  st jsonb;
  stu public.students%rowtype;
  cls text;
  code text;
  instruction text;
begin
  if not private.can_scan() then raise exception 'Accès refusé' using errcode='42501'; end if;
  if nullif(btrim(coalesce(p_sid,'')),'') is null then
    return jsonb_build_object('contract_version',2,'student_id',null,'student_name',null,'matricule',null,
      'class_id',null,'class_name',null,'photo_url',null,'access_status','unavailable',
      'allowed',false,'instruction','Contrôle manuel requis','checked_at',now());
  end if;
  select * into stu from public.students where id=p_sid and not coalesce(archived,false);
  if not found then
    return jsonb_build_object('contract_version',2,'student_id',p_sid,'student_name',null,'matricule',null,
      'class_id',null,'class_name',null,'photo_url',null,'access_status','unavailable',
      'allowed',false,'instruction','Élève introuvable — contrôle manuel requis','checked_at',now());
  end if;
  st:=private.compute_payment_state(p_sid);
  select name into cls from public.classes where id=stu.cid;
  code:=coalesce(st->>'access_status','unavailable');
  instruction:=case code
    when 'allowed' then 'Accès autorisé'
    when 'exception' then 'Accès temporairement autorisé'
    when 'orient' then 'Accès en attente — orienter vers la Caisse'
    when 'blocked' then 'Accès non autorisé — orienter vers la Caisse'
    else 'Contrôle manuel requis' end;
  return jsonb_build_object('contract_version',2,'student_id',stu.id,'student_name',stu.name,
    'matricule',stu.mat,'class_id',stu.cid,'class_name',cls,'photo_url',stu.photo,
    'access_status',code,'allowed',coalesce((st->>'allowed')::boolean,false),
    'instruction',instruction,'checked_at',now());
end;
$$;

revoke all on function public.evaluate_student_access(text) from public;
revoke all on function public.evaluate_student_access(text) from anon;
revoke all on function public.get_gate_access_status(text) from public;
revoke all on function public.get_gate_access_status(text) from anon;
grant execute on function public.evaluate_student_access(text) to authenticated;
grant execute on function public.evaluate_student_access(text) to service_role;
grant execute on function public.get_gate_access_status(text) to authenticated;
grant execute on function public.get_gate_access_status(text) to service_role;

comment on function public.get_gate_access_status(text) is
  'Contract v2: orient is not an authorized passage and no financial amount or installment is returned.';
