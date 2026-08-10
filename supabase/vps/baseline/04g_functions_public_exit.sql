-- SchoolSafe VPS baseline - 04g two-stage exit RPCs

BEGIN;

CREATE OR REPLACE FUNCTION public.prepare_student_exit(p_sid text, p_gate_label text DEFAULT NULL::text, p_manual boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text:=private.current_app_role();
  v_actor_id text:=private.current_app_user_id();
  v_actor_name text;
  s public.students%rowtype;
  p public.users%rowtype;
  e public.student_exit_events%rowtype;
  v_date date:=timezone('Africa/Kinshasa',now())::date;
  v_notify jsonb;
begin
  if not private.can_prepare_student_exit() then return jsonb_build_object('ok',false,'code','FORBIDDEN'); end if;
  perform private.expire_student_exit_events();
  select name into v_actor_name from public.users where id=v_actor_id and status='active';
  if not found then return jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); end if;
  select * into s from public.students where id=p_sid and not coalesce(archived,false);
  if not found then return jsonb_build_object('ok',false,'code','STUDENT_NOT_FOUND'); end if;
  if not exists(select 1 from public.attendance a where a.sid=s.id and a.date=v_date::text) then
    return jsonb_build_object('ok',false,'code','MISSING_ENTRY');
  end if;
  if exists(select 1 from public.student_exit_events x where x.sid=s.id and x.school_date=v_date and x.status='confirmed') then
    return jsonb_build_object('ok',false,'code','ALREADY_EXITED');
  end if;
  if s.pid is null then return jsonb_build_object('ok',false,'code','PRIMARY_PARENT_REQUIRED'); end if;
  select * into p from public.users where id=s.pid and role='parent' and status='active';
  if not found then return jsonb_build_object('ok',false,'code','PRIMARY_PARENT_INACTIVE'); end if;

  perform pg_advisory_xact_lock(hashtext('student-exit:'||s.id||':'||v_date::text));
  select * into e from public.student_exit_events
  where sid=s.id and school_date=v_date and status in ('prepared','gate_scanned')
  order by created_at desc limit 1 for update;
  if found then
    return jsonb_build_object('ok',true,'code','EXIT_ALREADY_PREPARED','exit_event_id',e.id,
      'status',e.status,'expires_at',e.expires_at);
  end if;

  insert into public.student_exit_events(
    sid,student_name_snapshot,student_class_id_snapshot,school_date,status,quick_flow,
    prepared_at,expires_at,prepared_by_user_id,prepared_by_name,prepared_by_role,preparation_gate,
    parent_id_snapshot,parent_name_snapshot,parent_phone_snapshot,parent_email_snapshot,manual
  ) values (
    s.id,s.name,s.cid,v_date,'prepared',false,
    now(),now()+interval '30 minutes',v_actor_id,v_actor_name,v_role,nullif(btrim(coalesce(p_gate_label,'')),''),
    p.id,p.name,p.phone,p.email,coalesce(p_manual,false)
  ) returning * into e;

  v_notify:=private.queue_student_exit_notification(e.id,'exit_prepared');
  perform private.write_audit_event(v_actor_id,v_actor_name,'student_exit_prepared',
    jsonb_build_object('exit_event_id',e.id,'student_id',s.id,'expires_at',e.expires_at,'channels',v_notify->'channels'),s.id);

  return jsonb_build_object('ok',true,'code','EXIT_PREPARED','exit_event_id',e.id,
    'status',e.status,'prepared_at',e.prepared_at,'expires_at',e.expires_at,
    'notification',v_notify);
exception when unique_violation then
  select * into e from public.student_exit_events
  where sid=p_sid and school_date=v_date and status in ('prepared','gate_scanned') order by created_at desc limit 1;
  return jsonb_build_object('ok',true,'code','EXIT_ALREADY_PREPARED','exit_event_id',e.id,'status',e.status,'expires_at',e.expires_at);
end;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_student_exit_preparation(p_exit_event_id text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text:=private.current_app_role();
  v_actor_id text:=private.current_app_user_id();
  v_actor_name text;
  v_reason text:=nullif(btrim(coalesce(p_reason,'')),'');
  e public.student_exit_events%rowtype;
  v_notify jsonb;
begin
  if not private.can_prepare_student_exit() then return jsonb_build_object('ok',false,'code','FORBIDDEN'); end if;
  if v_reason is null or length(v_reason)<3 then return jsonb_build_object('ok',false,'code','REASON_REQUIRED'); end if;
  select name into v_actor_name from public.users where id=v_actor_id and status='active';
  if not found then return jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); end if;
  select * into e from public.student_exit_events where id=p_exit_event_id for update;
  if not found then return jsonb_build_object('ok',false,'code','EXIT_EVENT_NOT_FOUND'); end if;
  if e.status not in ('prepared','gate_scanned') then return jsonb_build_object('ok',false,'code','EXIT_ALREADY_FINALIZED'); end if;
  if v_role='enseignant' and e.prepared_by_user_id<>v_actor_id then return jsonb_build_object('ok',false,'code','FORBIDDEN'); end if;
  update public.student_exit_events set status='cancelled',decision_note=left(v_reason,500),finalized_at=now()
  where id=e.id returning * into e;
  v_notify:=private.queue_student_exit_notification(e.id,'exit_cancelled');
  perform private.write_audit_event(v_actor_id,v_actor_name,'student_exit_cancelled',
    jsonb_build_object('exit_event_id',e.id,'student_id',e.sid,'reason',v_reason,'notification',v_notify->'channels'),e.sid);
  return jsonb_build_object('ok',true,'code','EXIT_PREPARATION_CANCELLED','exit_event_id',e.id,'notification',v_notify);
end;
$function$;

CREATE OR REPLACE FUNCTION public.scan_student_exit_at_gate(p_sid text, p_exit_event_id text DEFAULT NULL::text, p_escort_kind text DEFAULT NULL::text, p_escort_id text DEFAULT NULL::text, p_gate_label text DEFAULT NULL::text, p_teacher_gate_reason text DEFAULT NULL::text, p_manual boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text:=private.current_app_role();
  v_actor_id text:=private.current_app_user_id();
  v_actor_name text;
  v_gate text:=nullif(btrim(coalesce(p_gate_label,'')),'');
  v_reason text:=nullif(btrim(coalesce(p_teacher_gate_reason,'')),'');
  v_kind text:=lower(btrim(coalesce(p_escort_kind,'')));
  v_date date:=timezone('Africa/Kinshasa',now())::date;
  s public.students%rowtype;
  p public.users%rowtype;
  a public.aps%rowtype;
  e public.student_exit_events%rowtype;
  prep jsonb;
  v_escort_id text;
  v_escort_name text;
  v_escort_relation text;
  v_escort_phone text;
  v_portrait text;
  v_full_body text;
  v_doc_type text;
  v_doc_last4 text;
begin
  if not private.can_confirm_student_exit() then return jsonb_build_object('ok',false,'code','FORBIDDEN'); end if;
  perform private.expire_student_exit_events();
  select name into v_actor_name from public.users where id=v_actor_id and status='active';
  if not found then return jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); end if;
  if v_gate is null or length(v_gate)>120 then return jsonb_build_object('ok',false,'code','GATE_REQUIRED'); end if;
  if v_role='enseignant' and (v_reason is null or length(v_reason)<5) then return jsonb_build_object('ok',false,'code','TEACHER_GATE_REASON_REQUIRED'); end if;
  select * into s from public.students where id=p_sid and not coalesce(archived,false);
  if not found then return jsonb_build_object('ok',false,'code','STUDENT_NOT_FOUND'); end if;

  perform pg_advisory_xact_lock(hashtext('student-exit:'||s.id||':'||v_date::text));
  if exists(select 1 from public.student_exit_events x where x.sid=s.id and x.school_date=v_date and x.status='confirmed') then
    return jsonb_build_object('ok',false,'code','ALREADY_EXITED');
  end if;

  if nullif(btrim(coalesce(p_exit_event_id,'')),'') is not null then
    select * into e from public.student_exit_events where id=p_exit_event_id and sid=s.id and school_date=v_date for update;
  else
    select * into e from public.student_exit_events where sid=s.id and school_date=v_date and status in ('prepared','gate_scanned')
    order by created_at desc limit 1 for update;
  end if;

  if not found then
    prep:=public.prepare_student_exit(s.id,v_gate,p_manual);
    if prep->>'ok'<>'true' then return prep; end if;
    select * into e from public.student_exit_events where id=prep->>'exit_event_id' for update;
    update public.student_exit_events set quick_flow=true where id=e.id returning * into e;
  end if;
  if e.status='gate_scanned' then return jsonb_build_object('ok',true,'code','EXIT_ALREADY_SCANNED','exit_event_id',e.id,'status',e.status); end if;
  if e.status<>'prepared' or e.expires_at<=now() then return jsonb_build_object('ok',false,'code','PREPARATION_EXPIRED'); end if;

  if v_kind='primary' then
    select * into p from public.users where id=s.pid and role='parent' and status='active';
    if not found or (p_escort_id is not null and p_escort_id<>p.id) then return jsonb_build_object('ok',false,'code','INVALID_ESCORT'); end if;
    if p.photo_url is null or p.identity_full_body_photo_url is null then return jsonb_build_object('ok',false,'code','PRIMARY_PARENT_IDENTITY_INCOMPLETE'); end if;
    v_escort_id:=p.id; v_escort_name:=p.name; v_escort_relation:='Parent principal';
    v_escort_phone:=p.phone; v_portrait:=p.photo_url; v_full_body:=p.identity_full_body_photo_url;
    v_doc_type:=p.identity_document_type; v_doc_last4:=p.identity_document_last4;
  elsif v_kind='accredited' then
    select * into a from public.aps where id=p_escort_id and sid=s.id and active and approval_status='approved'
      and valid_from<=v_date and (valid_until is null or valid_until>=v_date);
    if not found then return jsonb_build_object('ok',false,'code','INVALID_ESCORT'); end if;
    v_escort_id:=a.id; v_escort_name:=a.name; v_escort_relation:=a.relation;
    v_escort_phone:=a.phone; v_portrait:=a.photo; v_full_body:=a.photo_full_body;
    v_doc_type:=a.id_doc_type; v_doc_last4:=a.id_doc_last4;
  elsif v_kind='self' then
    if not s.may_leave_alone or (s.leave_alone_until is not null and s.leave_alone_until<v_date) then return jsonb_build_object('ok',false,'code','SELF_EXIT_NOT_ALLOWED'); end if;
    v_escort_id:=s.id; v_escort_name:=s.name||' — sortie autonome'; v_escort_relation:='Élève'; v_portrait:=s.photo;
  else
    return jsonb_build_object('ok',false,'code','ESCORT_REQUIRED');
  end if;

  update public.student_exit_events set
    status='gate_scanned',gate_scanned_at=now(),gate_scanned_by_user_id=v_actor_id,
    gate_scanned_by_name=v_actor_name,gate_scanned_by_role=v_role,gate_label=v_gate,
    teacher_gate_reason=case when v_role='enseignant' then left(v_reason,500) else null end,
    manual=coalesce(p_manual,false),expires_at=greatest(expires_at,now()+interval '10 minutes'),
    escort_kind=v_kind,escort_id_snapshot=v_escort_id,escort_name_snapshot=v_escort_name,
    escort_relation_snapshot=v_escort_relation,escort_phone_snapshot=v_escort_phone,
    escort_photo_portrait_snapshot=v_portrait,escort_photo_full_body_snapshot=v_full_body,
    escort_id_doc_type_snapshot=v_doc_type,escort_id_doc_last4_snapshot=v_doc_last4
  where id=e.id returning * into e;

  perform private.write_audit_event(v_actor_id,v_actor_name,'student_exit_gate_scanned',
    jsonb_build_object('exit_event_id',e.id,'student_id',s.id,'gate',v_gate,'escort_kind',v_kind,'teacher_gate_reason',e.teacher_gate_reason),s.id);

  return jsonb_build_object('ok',true,'code','EXIT_GATE_SCANNED','exit_event_id',e.id,
    'status',e.status,'gate_scanned_at',e.gate_scanned_at,'escort_name',e.escort_name_snapshot,
    'photo_portrait',e.escort_photo_portrait_snapshot,'photo_full_body',e.escort_photo_full_body_snapshot,
    'id_doc_type',e.escort_id_doc_type_snapshot,'id_doc_last4',e.escort_id_doc_last4_snapshot);
end;
$function$;

CREATE OR REPLACE FUNCTION public.validate_student_exit(p_exit_event_id text, p_decision text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text:=private.current_app_role();
  v_actor_id text:=private.current_app_user_id();
  v_actor_name text;
  v_decision text:=lower(btrim(coalesce(p_decision,'')));
  v_note text:=nullif(btrim(coalesce(p_note,'')),'');
  e public.student_exit_events%rowtype;
  v_notify jsonb;
  v_scan_id text;
begin
  if not private.can_confirm_student_exit() then return jsonb_build_object('ok',false,'code','FORBIDDEN'); end if;
  perform private.expire_student_exit_events();
  select name into v_actor_name from public.users where id=v_actor_id and status='active';
  if not found then return jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); end if;
  if v_decision not in ('authorized','refused') then return jsonb_build_object('ok',false,'code','UNSUPPORTED_DECISION'); end if;
  if v_decision='refused' and (v_note is null or length(v_note)<3) then return jsonb_build_object('ok',false,'code','REFUSAL_REASON_REQUIRED'); end if;

  select * into e from public.student_exit_events where id=p_exit_event_id for update;
  if not found then return jsonb_build_object('ok',false,'code','EXIT_EVENT_NOT_FOUND'); end if;
  if e.status<>'gate_scanned' then return jsonb_build_object('ok',false,'code','EXIT_NOT_READY_FOR_VALIDATION'); end if;
  perform pg_advisory_xact_lock(hashtext('student-exit:'||e.sid||':'||e.school_date::text));
  if v_decision='authorized' and exists(
    select 1 from public.student_exit_events x where x.sid=e.sid and x.school_date=e.school_date and x.status='confirmed' and x.id<>e.id
  ) then return jsonb_build_object('ok',false,'code','ALREADY_EXITED'); end if;

  update public.student_exit_events set
    status=case when v_decision='authorized' then 'confirmed' else 'refused' end,
    validated_at=now(),validated_by_user_id=v_actor_id,validated_by_name=v_actor_name,
    validated_by_role=v_role,decision_note=left(v_note,500),finalized_at=now()
  where id=e.id returning * into e;

  v_scan_id:='scan_'||replace(gen_random_uuid()::text,'-','');
  insert into public.scan_log(
    id,sid,type,status,date,time,name,label,by_uid,by_name,by_role,manual,description,note,
    escort_kind,escort_id,escort_name,exit_event_id,
    prepared_by_uid,prepared_by_name,prepared_by_role,
    validated_by_uid,validated_by_name,validated_by_role,gate_label,
    preparation_time,gate_scan_time,validation_time,escort_relation,
    escort_photo_portrait,escort_photo_full_body,escort_id_doc_type,escort_id_doc_last4
  ) values (
    v_scan_id,e.sid,'exit',case when v_decision='authorized' then 'authorized' else 'unauthorized' end,
    e.school_date::text,to_char(timezone('Africa/Kinshasa',e.validated_at),'HH24:MI'),e.student_name_snapshot,
    case when v_decision='authorized' then 'Sortie autorisée' else 'Sortie refusée' end,
    e.gate_scanned_by_user_id,e.gate_scanned_by_name,e.gate_scanned_by_role,e.manual,
    'Contrôle de sortie en deux étapes',e.decision_note,e.escort_kind,e.escort_id_snapshot,e.escort_name_snapshot,e.id,
    e.prepared_by_user_id,e.prepared_by_name,e.prepared_by_role,
    e.validated_by_user_id,e.validated_by_name,e.validated_by_role,e.gate_label,
    e.prepared_at,e.gate_scanned_at,e.validated_at,e.escort_relation_snapshot,
    e.escort_photo_portrait_snapshot,e.escort_photo_full_body_snapshot,e.escort_id_doc_type_snapshot,e.escort_id_doc_last4_snapshot
  );

  v_notify:=private.queue_student_exit_notification(e.id,case when v_decision='authorized' then 'exit_confirmed' else 'exit_refused' end);
  perform private.write_audit_event(v_actor_id,v_actor_name,
    case when v_decision='authorized' then 'student_exit_confirmed' else 'student_exit_refused' end,
    jsonb_build_object('exit_event_id',e.id,'student_id',e.sid,'scanner_id',e.gate_scanned_by_user_id,
      'validator_id',v_actor_id,'escort_name',e.escort_name_snapshot,'gate',e.gate_label,'notification',v_notify->'channels'),e.sid);

  return jsonb_build_object('ok',true,'code',case when v_decision='authorized' then 'EXIT_CONFIRMED' else 'EXIT_REFUSED' end,
    'exit_event_id',e.id,'scan_log_id',v_scan_id,'status',e.status,
    'prepared_by',e.prepared_by_name,'scanned_by',e.gate_scanned_by_name,'validated_by',e.validated_by_name,
    'escort_name',e.escort_name_snapshot,'notification',v_notify);
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_student_exit_status(p_sid text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  e public.student_exit_events%rowtype;
  v_date date:=timezone('Africa/Kinshasa',now())::date;
begin
  if not (private.can_prepare_student_exit() or private.owns_student(p_sid)) then
    raise exception 'Accès refusé' using errcode='42501';
  end if;
  perform private.expire_student_exit_events();
  select * into e from public.student_exit_events
  where sid=p_sid and school_date=v_date order by created_at desc limit 1;
  return jsonb_build_object('ok',true,'event',case when e.id is null then null else to_jsonb(e) end,
    'pickup_context',public.get_student_pickup_context(p_sid));
end;
$function$;

COMMIT;
