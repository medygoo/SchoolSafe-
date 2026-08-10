-- SchoolSafe VPS baseline - 04d payment/access RPCs

BEGIN;

CREATE OR REPLACE FUNCTION public.get_gate_access_status(p_sid text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.check_gate_access_status(p_sid text, p_source text DEFAULT 'qr'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  r jsonb;
  code text;
  src text := case when p_source = 'manual' then 'manual' else 'qr' end;
begin
  if not private.can_scan() then raise exception 'Accès refusé'; end if;
  r := public.get_gate_access_status(p_sid);
  code := coalesce(r->>'access_status', 'unavailable');
  if nullif(r->>'student_name', '') is not null then
    insert into public.payment_scan_log(sid,checked_by,checked_role,source,result_code,details)
    values(r->>'student_id',private.current_app_user_id(),private.current_app_role(),src,
      case when code in ('allowed','orient','blocked','exception') then code else 'unavailable' end,
      jsonb_build_object('instruction', r->>'instruction'));
  end if;
  return r;
end;
$function$;

CREATE OR REPLACE FUNCTION public.evaluate_student_access(p_sid text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.get_cashier_student_fee_detail(p_sid text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
begin
 if private.current_app_role() not in ('direction','direction3') then raise exception 'Accès refusé'; end if;
 return private.build_fee_summary(p_sid);
end
$function$;

CREATE OR REPLACE FUNCTION public.get_parent_fee_summary(p_sid text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
begin
 if private.current_app_role()<>'parent' or not private.owns_student(p_sid) then raise exception 'Accès refusé'; end if;
 return private.build_fee_summary(p_sid);
end
$function$;

CREATE OR REPLACE FUNCTION public.grant_payment_access_exception(p_sid text, p_ends_at timestamp with time zone, p_reason text, p_starts_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare idv text:='pae_'||replace(gen_random_uuid()::text,'-',''); startv timestamptz:=coalesce(p_starts_at,now());
begin
 if private.current_app_role()<>'direction' then raise exception 'Accès refusé'; end if;
 if p_ends_at is null or p_ends_at<=startv or length(btrim(coalesce(p_reason,'')))<3 then raise exception 'Dérogation invalide'; end if;
 insert into public.payment_access_exceptions(id,sid,starts_at,ends_at,reason,granted_by) values(idv,p_sid,startv,p_ends_at,btrim(p_reason),private.current_app_user_id());
 return jsonb_build_object('exception_id',idv,'student_id',p_sid,'starts_at',startv,'ends_at',p_ends_at);
end
$function$;

CREATE OR REPLACE FUNCTION public.revoke_payment_access_exception(p_exception_id text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
 if private.current_app_role()<>'direction' then raise exception 'Accès refusé'; end if;
 if length(btrim(coalesce(p_reason,'')))<3 then raise exception 'Motif obligatoire'; end if;
 update public.payment_access_exceptions set revoked_at=now(),revoked_by=private.current_app_user_id(),revoke_reason=btrim(p_reason) where id=p_exception_id and revoked_at is null;
 if not found then raise exception 'Dérogation introuvable ou déjà révoquée'; end if;
 return jsonb_build_object('exception_id',p_exception_id,'status','revoked');
end
$function$;

CREATE OR REPLACE FUNCTION public.record_payment_transaction(p_sid text, p_amount numeric, p_currency text DEFAULT 'USD'::text, p_payment_method text DEFAULT 'cash'::text, p_external_reference text DEFAULT NULL::text, p_note text DEFAULT NULL::text, p_payment_date date DEFAULT NULL::date, p_allocations jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  if role_code not in ('direction', 'direction3') then raise exception 'Accès refusé' using errcode = '42501'; end if;
  if uid is null then raise exception 'Compte SchoolSafe non relié' using errcode = '42501'; end if;
  select u.name into actor_name from public.users u where u.id = uid and u.status = 'active';
  if nullif(btrim(coalesce(actor_name, '')), '') is null then raise exception 'Profil SchoolSafe actif introuvable' using errcode = '42501'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Montant invalide' using errcode = '22023'; end if;
  if curr !~ '^[A-Z]{3}$' or method not in ('cash', 'bank', 'mobile_money', 'other') then raise exception 'Paramètres de paiement invalides' using errcode = '22023'; end if;
  if not exists(select 1 from public.students where id = p_sid and not coalesce(archived, false)) then raise exception 'Élève introuvable ou archivé' using errcode = 'P0002'; end if;

  yr := private.current_school_year();
  receipt := private.next_payment_receipt_no(yr);
  insert into public.payment_transactions(id,sid,school_year,amount,currency,payment_date,payment_method,external_reference,receipt_no,status,recorded_by,recorded_by_name,recorded_by_role,note)
  values(txid,p_sid,yr,p_amount,curr,v_payment_date,method,nullif(btrim(p_external_reference), ''),receipt,'confirmed',uid,actor_name,role_code,nullif(btrim(p_note), ''));

  if p_allocations is not null and jsonb_typeof(p_allocations) = 'array' and jsonb_array_length(p_allocations) > 0 then
    for item in select value from jsonb_array_elements(p_allocations) loop
      begin piece := (item->>'amount')::numeric; exception when others then raise exception 'Allocation invalide' using errcode = '22023'; end;
      if nullif(btrim(coalesce(item->>'obligation_id', '')), '') is null or piece is null or piece <= 0 then raise exception 'Allocation invalide' using errcode = '22023'; end if;
      if not exists(select 1 from public.student_fee_obligations o where o.id = item->>'obligation_id' and o.sid = p_sid and o.school_year = yr and o.currency = curr and o.active) then raise exception 'Obligation incompatible avec ce paiement' using errcode = '22023'; end if;
      insert into public.payment_allocations(transaction_id, obligation_id, amount) values (txid, item->>'obligation_id', piece);
      allocated := allocated + piece;
    end loop;
    if allocated <> p_amount then raise exception 'Somme des allocations incorrecte' using errcode = '22023'; end if;
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
      from balances where amount_due-paid>0 order by due_date nulls last,installment_no,id
    loop
      exit when remaining <= 0;
      piece := least(remaining, rec.outstanding);
      insert into public.payment_allocations(transaction_id, obligation_id, amount) values (txid, rec.id, piece);
      remaining := remaining - piece;
    end loop;
    if remaining <> 0 then raise exception 'Montant supérieur au solde exigible ou aucune obligation configurée' using errcode = '22023'; end if;
  end if;

  return jsonb_build_object('contract_version',2,'transaction_id',txid,'receipt_no',receipt,'student_id',p_sid,
    'amount',p_amount,'currency',curr,'payment_date',v_payment_date,'school_year',yr,
    'status','confirmed','recorded_by',uid,'recorded_by_name',actor_name,'recorded_by_role',role_code,'created_at',now());
end;
$function$;

CREATE OR REPLACE FUNCTION public.reverse_payment_transaction(p_transaction_id text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text := private.current_app_role();
  v_uid text := private.current_app_user_id();
  v_actor_name text;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_tx public.payment_transactions%rowtype;
  v_reversed_at timestamptz := now();
begin
  if v_role not in ('direction','direction3') or v_uid is null then raise exception 'Accès refusé' using errcode='42501'; end if;
  select u.name into v_actor_name from public.users u where u.id=v_uid and u.status='active';
  if nullif(btrim(coalesce(v_actor_name,'')),'') is null then raise exception 'Profil SchoolSafe actif introuvable' using errcode='42501'; end if;
  if nullif(btrim(coalesce(p_transaction_id,'')),'') is null then raise exception 'Transaction requise' using errcode='22023'; end if;
  if length(v_reason)<5 or length(v_reason)>500 then raise exception 'Motif de contrepassation invalide' using errcode='22023'; end if;
  select * into v_tx from public.payment_transactions where id=p_transaction_id for update;
  if not found then raise exception 'Transaction introuvable' using errcode='P0002'; end if;
  if v_tx.status<>'confirmed' then raise exception 'Transaction déjà annulée ou indisponible' using errcode='23514'; end if;
  update public.payment_transactions
  set status='reversed',reversed_at=v_reversed_at,reversed_by=v_uid,reversed_by_name=v_actor_name,reversed_by_role=v_role,reversal_reason=v_reason,updated_at=v_reversed_at
  where id=v_tx.id;
  return jsonb_build_object('contract_version',2,'transaction_id',v_tx.id,'student_id',v_tx.sid,
    'receipt_no',v_tx.receipt_no,'amount',v_tx.amount,'currency',v_tx.currency,
    'status','reversed','reversed_by',v_uid,'reversed_by_name',v_actor_name,
    'reversed_by_role',v_role,'reversed_at',v_reversed_at,'reason',v_reason);
end;
$function$;

COMMIT;
