-- Direct scanner JSON contracts. Refused and oriented entries create no attendance or entry scan.

create or replace function public.record_entry_scan(
  p_sid text,
  p_status text,
  p_arr_time text,
  p_manual boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.students%rowtype;
  u public.users%rowtype;
  cfg public.settings%rowtype;
  access_result jsonb;
  v_date text := to_char(timezone('Africa/Kinshasa',now()),'YYYY-MM-DD');
  v_time text := coalesce(nullif(p_arr_time,''),to_char(timezone('Africa/Kinshasa',now()),'HH24:MI'));
  v_status text := case when p_status='late' then 'late' else 'ontime' end;
  v_id text;
  v_access_status text;
begin
  if not private.can_scan() then raise exception 'Accès refusé' using errcode='42501'; end if;
  select * into u from public.users where id=private.current_app_user_id() and status='active';
  if not found then raise exception 'Profil SchoolSafe actif introuvable' using errcode='42501'; end if;

  select * into s from public.students where id=p_sid and not coalesce(archived,false);
  if not found then
    return jsonb_build_object('contract_version',2,'recorded',false,'allowed',false,'reason','unknown_student');
  end if;

  access_result:=public.evaluate_student_access(p_sid);
  v_access_status:=coalesce(access_result->>'access_status','unavailable');
  if not coalesce((access_result->>'allowed')::boolean,false) then
    return access_result||jsonb_build_object(
      'recorded',false,
      'reason',case v_access_status
        when 'orient' then 'orientation_required'
        when 'blocked' then 'denied'
        else 'manual_check' end
    );
  end if;

  perform pg_advisory_xact_lock(hashtext('entry:'||p_sid||':'||v_date));
  if exists(select 1 from public.attendance a where a.sid=p_sid and a.date=v_date) then
    return jsonb_build_object('contract_version',2,'recorded',false,'reason','duplicate',
      'allowed',true,'access_status',v_access_status,'date',v_date,'time',v_time);
  end if;

  select * into cfg from public.settings order by id limit 1;
  v_id:='att_'||replace(gen_random_uuid()::text,'-','');
  insert into public.attendance
    (id,sid,cid,date,status,arr_time,manual,marked_by,by,year,trimestre)
  values
    (v_id,s.id,s.cid,v_date,v_status,v_time,coalesce(p_manual,false),
     u.id,u.id,cfg.year,cfg.currenttrimestre);

  insert into public.scan_log
    (id,sid,type,status,date,time,name,label,by_uid,by_name,by_role,manual,description)
  values
    ('scan_'||replace(gen_random_uuid()::text,'-',''),s.id,'entry',v_status,
     v_date,v_time,s.name,
     case when v_status='late' then 'Entrée en retard' else 'Entrée autorisée' end,
     u.id,u.name,private.current_app_role(),coalesce(p_manual,false),
     'Contrôle d’entrée validé');

  return jsonb_build_object('contract_version',2,'recorded',true,'allowed',true,
    'access_status',v_access_status,'status',v_status,'date',v_date,'time',v_time,
    'attendance_id',v_id);
exception when unique_violation then
  return jsonb_build_object('contract_version',2,'recorded',false,'reason','duplicate','allowed',true);
end;
$$;

create or replace function public.record_exit_scan(
  p_sid text,
  p_escort_kind text,
  p_escort_id text,
  p_escort_name text,
  p_manual boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  s public.students%rowtype;
  u public.users%rowtype;
  a public.aps%rowtype;
  v_date text := to_char(timezone('Africa/Kinshasa',now()),'YYYY-MM-DD');
  v_time text := to_char(timezone('Africa/Kinshasa',now()),'HH24:MI');
  v_escort_name text;
  v_valid boolean := false;
begin
  if not private.can_scan() then raise exception 'Accès refusé' using errcode='42501'; end if;
  select * into u from public.users where id=private.current_app_user_id() and status='active';
  if not found then raise exception 'Profil SchoolSafe actif introuvable' using errcode='42501'; end if;

  select * into s from public.students where id=p_sid and not coalesce(archived,false);
  if not found then
    return jsonb_build_object('contract_version',2,'recorded',false,'allowed',false,'reason','unknown_student');
  end if;

  perform pg_advisory_xact_lock(hashtext('exit:'||p_sid||':'||v_date));
  if not exists(select 1 from public.attendance x where x.sid=p_sid and x.date=v_date) then
    return jsonb_build_object('contract_version',2,'recorded',false,'allowed',false,'reason','missing_entry');
  end if;
  if exists(select 1 from public.scan_log x where x.sid=p_sid and x.date=v_date and x.type='exit' and x.status='authorized') then
    return jsonb_build_object('contract_version',2,'recorded',false,'allowed',false,'reason','duplicate');
  end if;

  if p_escort_kind='self' then
    v_valid:=s.may_leave_alone and (s.leave_alone_until is null or s.leave_alone_until>=v_date::date);
    v_escort_name:=s.name||' — sortie autonome';
  elsif p_escort_kind='primary' then
    select p.name into v_escort_name from public.users p
    where p.id=s.pid and p.id=p_escort_id and p.status='active';
    v_valid:=found;
  elsif p_escort_kind='accredited' then
    select * into a from public.aps x
    where x.id=p_escort_id and x.sid=p_sid and x.active
      and x.approval_status='approved'
      and (x.valid_until is null or x.valid_until>=v_date::date);
    v_valid:=found;
    v_escort_name:=a.name;
  end if;

  if not v_valid then
    return jsonb_build_object('contract_version',2,'recorded',false,'allowed',false,'reason','invalid_escort');
  end if;

  insert into public.scan_log
    (id,sid,type,status,date,time,name,label,by_uid,by_name,by_role,manual,
     description,escort_kind,escort_id,escort_name)
  values
    ('scan_'||replace(gen_random_uuid()::text,'-',''),s.id,'exit','authorized',
     v_date,v_time,s.name,'Sortie autorisée',u.id,u.name,
     private.current_app_role(),coalesce(p_manual,false),
     'Contrôle de sortie validé',p_escort_kind,p_escort_id,
     coalesce(v_escort_name,p_escort_name));

  return jsonb_build_object('contract_version',2,'recorded',true,'allowed',true,
    'status','authorized','date',v_date,'time',v_time,
    'escort_name',coalesce(v_escort_name,p_escort_name));
exception when unique_violation then
  return jsonb_build_object('contract_version',2,'recorded',false,'allowed',false,'reason','duplicate');
end;
$$;

revoke all on function public.record_entry_scan(text,text,text,boolean) from public;
revoke all on function public.record_entry_scan(text,text,text,boolean) from anon;
revoke all on function public.record_exit_scan(text,text,text,text,boolean) from public;
revoke all on function public.record_exit_scan(text,text,text,text,boolean) from anon;
grant execute on function public.record_entry_scan(text,text,text,boolean) to authenticated;
grant execute on function public.record_entry_scan(text,text,text,boolean) to service_role;
grant execute on function public.record_exit_scan(text,text,text,text,boolean) to authenticated;
grant execute on function public.record_exit_scan(text,text,text,text,boolean) to service_role;

comment on function public.record_entry_scan(text,text,text,boolean) is
  'Contract v2 direct JSON: denied/orient scans create no attendance or entry log.';
comment on function public.record_exit_scan(text,text,text,text,boolean) is
  'Contract v2 direct JSON with recorded/allowed/reason fields.';
