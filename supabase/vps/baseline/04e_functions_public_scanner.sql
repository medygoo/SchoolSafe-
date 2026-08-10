-- SchoolSafe VPS baseline - 04e scanner and QR RPCs

BEGIN;

CREATE OR REPLACE FUNCTION public.get_scanner_aps()
 RETURNS TABLE(id text, sid text, name text, relation text, photo text, phone text, valid_until date, approval_status text, active boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text := private.current_app_role();
begin
  if not private.can_scan() then raise exception 'Accès refusé' using errcode='42501'; end if;
  return query
  select a.id,a.sid,a.name,a.relation,a.photo,
         case when v_role in ('direction','gardien') then a.phone else null end,
         a.valid_until,a.approval_status,a.active
  from public.aps a
  where a.approval_status='approved'
    and a.active
    and (a.valid_until is null or a.valid_until>=timezone('Africa/Kinshasa',now())::date);
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_scanner_students()
 RETURNS TABLE(id text, mat text, name text, photo text, cid text, blocked boolean, access_blocked boolean, may_leave_alone boolean, leave_alone_until date, pid text, primary_guardian_name text, primary_guardian_phone text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text := private.current_app_role();
begin
  if not private.can_scan() then raise exception 'Accès refusé' using errcode='42501'; end if;
  return query
  select s.id,s.mat,s.name,s.photo,s.cid,
         coalesce(s.blocked,false),coalesce(s.access_blocked,false),
         s.may_leave_alone,s.leave_alone_until,
         s.pid,u.name,
         case when v_role in ('direction','gardien') then u.phone else null end
  from public.students s
  left join public.users u on u.id=s.pid and u.status='active'
  where not coalesce(s.archived,false);
end;
$function$;

CREATE OR REPLACE FUNCTION public.issue_student_qr(p_sid text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_student public.students%rowtype;
  v_day text := to_char(timezone('Africa/Kinshasa', now()), 'YYYYMMDD');
  v_secret bytea;
  v_payload text;
  v_sig text;
begin
  if not (private.can_scan() or private.owns_student(p_sid)) then
    raise exception 'Accès refusé';
  end if;
  select * into v_student from public.students where id = p_sid and not archived;
  if not found then raise exception 'Élève introuvable'; end if;
  select secret into v_secret from private.qr_keys where id = 'student_daily_v1';
  v_payload := v_student.mat || '|' || v_day;
  v_sig := encode(extensions.hmac(convert_to(v_payload, 'UTF8'), v_secret, 'sha256'), 'hex');
  return jsonb_build_object(
    'sid', v_student.id,
    'mat', v_student.mat,
    'date', v_day,
    'signature', v_sig,
    'payload', 'schoolsafe://student/' || v_student.mat || '/' || v_day || '/' || v_sig,
    'expires_at', v_day || ' 23:59 Africa/Kinshasa'
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.verify_student_qr(p_mat text, p_date text, p_signature text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_student public.students%rowtype;
  v_today text := to_char(timezone('Africa/Kinshasa', now()), 'YYYYMMDD');
  v_secret bytea;
  v_expected text;
begin
  if not private.can_scan() then raise exception 'Accès refusé'; end if;
  select * into v_student
  from public.students
  where lower(mat) = lower(btrim(p_mat)) and not archived
  limit 1;
  if not found then
    return jsonb_build_object('valid', false, 'reason', 'unknown_student');
  end if;
  if p_date is distinct from v_today then
    return jsonb_build_object('valid', false, 'reason', 'expired');
  end if;
  select secret into v_secret from private.qr_keys where id = 'student_daily_v1';
  v_expected := encode(
    extensions.hmac(convert_to(v_student.mat || '|' || p_date, 'UTF8'), v_secret, 'sha256'),
    'hex'
  );
  if lower(coalesce(p_signature, '')) <> lower(v_expected) then
    return jsonb_build_object('valid', false, 'reason', 'invalid_signature');
  end if;
  return jsonb_build_object(
    'valid', true, 'sid', v_student.id, 'mat', v_student.mat, 'date', p_date
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.record_entry_scan(p_sid text, p_status text, p_arr_time text, p_manual boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION public.record_scan_incident(p_sid text, p_type text, p_code text, p_note text, p_manual boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  s public.students%rowtype;
  u public.users%rowtype;
  role_code text := private.current_app_role();
  v_date text := to_char(timezone('Africa/Kinshasa', now()), 'YYYY-MM-DD');
  v_time text := to_char(timezone('Africa/Kinshasa', now()), 'HH24:MI');
  v_type text := case when p_type = 'exit' then 'exit' else 'entry' end;
  v_note text;
begin
  if not private.can_scan() then raise exception 'Accès refusé'; end if;
  select * into s from public.students where id = p_sid and not coalesce(archived, false);
  if not found then return jsonb_build_object('recorded', false, 'reason', 'unknown_student'); end if;
  select * into u from public.users where id = private.current_app_user_id() and status = 'active';
  if not found then raise exception 'Profil scanner introuvable'; end if;

  if role_code in ('direction', 'direction3') then
    v_note := left(coalesce(nullif(btrim(coalesce(p_note, '')), ''),nullif(btrim(coalesce(p_code, '')), ''),'Décision de sécurité'),250);
  else
    v_note := case coalesce(p_code, '')
      when 'invalid_escort' then 'Accompagnateur non autorisé'
      when 'missing_entry' then 'Entrée du jour introuvable'
      when 'invalid_qr' then 'QR invalide'
      when 'expired_qr' then 'QR expiré'
      when 'unknown_student' then 'Élève introuvable'
      else 'Décision administrative — contrôle manuel requis'
    end;
  end if;

  insert into public.scan_log(id,sid,type,status,date,time,name,label,by_uid,by_name,by_role,manual,description,note)
  values(
    'scan_' || replace(gen_random_uuid()::text, '-', ''),s.id,v_type,
    case when v_type = 'exit' then 'unauthorized' else 'refused_access' end,
    v_date,v_time,s.name,case when v_type = 'exit' then 'Sortie refusée' else 'Accès refusé' end,
    u.id,u.name,role_code,coalesce(p_manual, false),'Décision de sécurité',v_note
  );
  return jsonb_build_object('recorded', true);
end;
$function$;

CREATE OR REPLACE FUNCTION public.record_exit_scan(p_sid text, p_escort_kind text, p_escort_id text, p_escort_name text, p_manual boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text:=private.current_app_role();
  scanned jsonb;
  validated jsonb;
  v_reason text;
begin
  v_reason:=case when v_role='enseignant' then 'Enseignant au poste de sortie — parcours compatible' else null end;
  scanned:=public.scan_student_exit_at_gate(
    p_sid,null,p_escort_kind,p_escort_id,'Portail principal',v_reason,p_manual
  );
  if scanned->>'ok'<>'true' then
    return jsonb_build_object('contract_version',3,'recorded',false,'allowed',false,
      'reason',lower(coalesce(scanned->>'code','exit_failed')),'details',scanned);
  end if;
  validated:=public.validate_student_exit(scanned->>'exit_event_id','authorized',null);
  if validated->>'ok'<>'true' then
    return jsonb_build_object('contract_version',3,'recorded',false,'allowed',false,
      'reason',lower(coalesce(validated->>'code','validation_failed')),'details',validated);
  end if;
  return jsonb_build_object('contract_version',3,'recorded',true,'allowed',true,
    'status','authorized','date',to_char(timezone('Africa/Kinshasa',now()),'YYYY-MM-DD'),
    'time',to_char(timezone('Africa/Kinshasa',now()),'HH24:MI'),
    'escort_name',validated->>'escort_name','exit_event_id',validated->>'exit_event_id',
    'prepared_by',validated->>'prepared_by','scanned_by',validated->>'scanned_by',
    'validated_by',validated->>'validated_by');
end;
$function$;

COMMIT;
