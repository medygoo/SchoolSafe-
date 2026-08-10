-- SchoolSafe VPS baseline - 04f pickup identity RPCs

BEGIN;

CREATE OR REPLACE FUNCTION public.get_student_pickup_context(p_sid text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text := private.current_app_role();
  v_student public.students%rowtype;
  v_parent public.users%rowtype;
  v_people jsonb;
  v_full_phone boolean;
begin
  if not (private.can_scan() or private.owns_student(p_sid)) then
    raise exception 'Accès refusé' using errcode='42501';
  end if;
  select * into v_student from public.students
  where id=p_sid and not coalesce(archived,false);
  if not found then return jsonb_build_object('ok',false,'code','STUDENT_NOT_FOUND'); end if;

  if v_student.pid is not null then
    select * into v_parent from public.users where id=v_student.pid and role='parent';
  end if;
  v_full_phone := v_role in ('direction','direction2','gardien');

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',a.id,'kind','accredited','name',a.name,'relation',a.relation,
    'phone',case when v_full_phone then a.phone else regexp_replace(a.phone,'^(\+[0-9]{3})[0-9]+([0-9]{2})$','\1••••••\2') end,
    'photo_portrait',a.photo,'photo_full_body',a.photo_full_body,
    'id_doc_type',a.id_doc_type,'id_doc_last4',a.id_doc_last4,
    'valid_from',a.valid_from,'valid_until',a.valid_until
  ) order by a.name),'[]'::jsonb) into v_people
  from public.aps a
  where a.sid=p_sid and a.active and a.approval_status='approved'
    and a.valid_from<=timezone('Africa/Kinshasa',now())::date
    and (a.valid_until is null or a.valid_until>=timezone('Africa/Kinshasa',now())::date);

  return jsonb_build_object(
    'ok',true,
    'student',jsonb_build_object('id',v_student.id,'name',v_student.name,'photo',v_student.photo,'class_id',v_student.cid),
    'primary_parent',case when v_parent.id is null then null else jsonb_build_object(
      'id',v_parent.id,'kind','primary','name',v_parent.name,'relation','Parent principal',
      'phone',case when v_full_phone then v_parent.phone else null end,
      'photo_portrait',v_parent.photo_url,
      'photo_full_body',v_parent.identity_full_body_photo_url,
      'id_doc_type',v_parent.identity_document_type,
      'id_doc_last4',v_parent.identity_document_last4,
      'ready_for_pickup',v_parent.status='active' and v_parent.photo_url is not null and v_parent.identity_full_body_photo_url is not null
    ) end,
    'authorized_people',v_people,
    'authorized_count',jsonb_array_length(v_people)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_authorized_pickup_person(p_person jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text := private.current_app_role();
  v_actor_id text := private.current_app_user_id();
  v_actor_name text;
  v_id text := nullif(btrim(coalesce(p_person->>'id','')),'');
  v_sid text := nullif(btrim(coalesce(p_person->>'sid','')),'');
  v_name text := nullif(btrim(coalesce(p_person->>'name','')),'');
  v_relation text := nullif(btrim(coalesce(p_person->>'relation','')),'');
  v_phone text := private.normalize_phone_e164(p_person->>'phone');
  v_photo text := nullif(btrim(coalesce(p_person->>'photo_portrait',p_person->>'photo','')),'');
  v_photo_full text := nullif(btrim(coalesce(p_person->>'photo_full_body','')),'');
  v_doc_type text := nullif(btrim(coalesce(p_person->>'id_doc_type','')),'');
  v_doc_last4 text := nullif(btrim(coalesce(p_person->>'id_doc_last4','')),'');
  v_valid_from date;
  v_valid_until date;
  v_existing public.aps%rowtype;
  v_saved public.aps%rowtype;
  v_count integer;
begin
  if p_person is null or jsonb_typeof(p_person)<>'object' then return jsonb_build_object('ok',false,'code','INVALID_PAYLOAD'); end if;
  if v_role not in ('direction','direction2') then return jsonb_build_object('ok',false,'code','FORBIDDEN'); end if;
  select name into v_actor_name from public.users where id=v_actor_id and status='active' limit 1;
  if not found then return jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); end if;

  if v_sid is null or not exists(select 1 from public.students s where s.id=v_sid and not coalesce(s.archived,false)) then
    return jsonb_build_object('ok',false,'code','STUDENT_NOT_FOUND');
  end if;
  if v_name is null or length(v_name)>200 then return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','name'); end if;
  if v_relation is null or length(v_relation)>100 then return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','relation'); end if;
  if v_phone is null then return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','phone'); end if;
  if v_photo is null or lower(v_photo) like 'data:%' or length(v_photo)>2048 then return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','photo_portrait'); end if;
  if v_photo_full is null or lower(v_photo_full) like 'data:%' or length(v_photo_full)>2048 then return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','photo_full_body'); end if;
  if v_doc_type is null or length(v_doc_type)>80 then return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','id_doc_type'); end if;
  if v_doc_last4 is null or length(v_doc_last4) not between 2 and 12 then return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','id_doc_last4'); end if;

  begin
    v_valid_from := coalesce(nullif(btrim(coalesce(p_person->>'valid_from','')),'')::date,timezone('Africa/Kinshasa',now())::date);
    v_valid_until := nullif(btrim(coalesce(p_person->>'valid_until','')),'')::date;
  exception when invalid_datetime_format or datetime_field_overflow then
    return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','validity');
  end;
  if v_valid_until is not null and v_valid_until<v_valid_from then return jsonb_build_object('ok',false,'code','INVALID_VALIDITY_PERIOD'); end if;

  if v_id is null then v_id := 'aps_'||replace(gen_random_uuid()::text,'-',''); end if;
  perform pg_advisory_xact_lock(hashtext('aps:'||v_sid));
  select * into v_existing from public.aps where id=v_id for update;
  if found and v_existing.sid<>v_sid then return jsonb_build_object('ok',false,'code','STUDENT_CHANGE_FORBIDDEN'); end if;

  select count(*) into v_count from public.aps a
  where a.sid=v_sid and a.id<>v_id and a.active and a.approval_status='approved'
    and (a.valid_until is null or a.valid_until>=timezone('Africa/Kinshasa',now())::date);
  if v_count>=3 then return jsonb_build_object('ok',false,'code','MAX_THREE_AUTHORIZED'); end if;

  insert into public.aps(
    id,sid,name,relation,photo,photo_full_body,active,phone,approval_status,
    proposed_by,proposed_at,approved_by,approved_at,rejection_reason,
    id_doc_type,id_doc_last4,valid_from,valid_until,created_by,created_by_name,
    updated_at,suspended_by,suspended_at,status_note
  ) values (
    v_id,v_sid,v_name,v_relation,v_photo,v_photo_full,true,v_phone,'approved',
    v_actor_id,now(),v_actor_id,now(),null,
    v_doc_type,v_doc_last4,v_valid_from,v_valid_until,v_actor_id,v_actor_name,
    now(),null,null,null
  )
  on conflict(id) do update set
    name=excluded.name,relation=excluded.relation,photo=excluded.photo,photo_full_body=excluded.photo_full_body,
    phone=excluded.phone,approval_status='approved',active=true,approved_by=v_actor_id,approved_at=now(),
    rejection_reason=null,id_doc_type=excluded.id_doc_type,id_doc_last4=excluded.id_doc_last4,
    valid_from=excluded.valid_from,valid_until=excluded.valid_until,updated_at=now(),
    suspended_by=null,suspended_at=null,status_note=null
  returning * into v_saved;

  perform private.write_audit_event(
    v_actor_id,v_actor_name,
    case when v_existing.id is null then 'authorized_pickup_person_created' else 'authorized_pickup_person_updated' end,
    jsonb_build_object('student_id',v_sid,'person_id',v_saved.id,'relation',v_relation,'valid_until',v_valid_until),v_sid
  );
  return jsonb_build_object('ok',true,'code',case when v_existing.id is null then 'AUTHORIZED_PERSON_CREATED' else 'AUTHORIZED_PERSON_UPDATED' end,'person',to_jsonb(v_saved));
exception
  when check_violation then return jsonb_build_object('ok',false,'code','VALIDATION_ERROR');
  when foreign_key_violation then return jsonb_build_object('ok',false,'code','REFERENCE_NOT_FOUND');
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_authorized_pickup_person_status(p_person_id text, p_action text, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text := private.current_app_role();
  v_actor_id text := private.current_app_user_id();
  v_actor_name text;
  v_person public.aps%rowtype;
  v_action text := lower(btrim(coalesce(p_action,'')));
  v_reason text := nullif(btrim(coalesce(p_reason,'')),'');
  v_count integer;
begin
  if v_role not in ('direction','direction2') then return jsonb_build_object('ok',false,'code','FORBIDDEN'); end if;
  select name into v_actor_name from public.users where id=v_actor_id and status='active';
  if not found then return jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); end if;
  select * into v_person from public.aps where id=p_person_id for update;
  if not found then return jsonb_build_object('ok',false,'code','AUTHORIZED_PERSON_NOT_FOUND'); end if;

  if v_action='suspend' then
    if v_reason is null or length(v_reason)<3 then return jsonb_build_object('ok',false,'code','REASON_REQUIRED'); end if;
    update public.aps set active=false,approval_status='suspended',suspended_by=v_actor_id,suspended_at=now(),status_note=left(v_reason,500),updated_at=now()
    where id=v_person.id returning * into v_person;
  elsif v_action='reactivate' then
    if v_person.photo is null or v_person.photo_full_body is null or v_person.id_doc_type is null or v_person.id_doc_last4 is null then
      return jsonb_build_object('ok',false,'code','IDENTITY_INCOMPLETE');
    end if;
    perform pg_advisory_xact_lock(hashtext('aps:'||v_person.sid));
    select count(*) into v_count from public.aps a
    where a.sid=v_person.sid and a.id<>v_person.id and a.active and a.approval_status='approved'
      and (a.valid_until is null or a.valid_until>=timezone('Africa/Kinshasa',now())::date);
    if v_count>=3 then return jsonb_build_object('ok',false,'code','MAX_THREE_AUTHORIZED'); end if;
    update public.aps set active=true,approval_status='approved',approved_by=v_actor_id,approved_at=now(),suspended_by=null,suspended_at=null,status_note=null,updated_at=now()
    where id=v_person.id returning * into v_person;
  else
    return jsonb_build_object('ok',false,'code','UNSUPPORTED_ACTION');
  end if;

  perform private.write_audit_event(v_actor_id,v_actor_name,
    case when v_action='suspend' then 'authorized_pickup_person_suspended' else 'authorized_pickup_person_reactivated' end,
    jsonb_build_object('person_id',v_person.id,'student_id',v_person.sid,'reason',v_reason),v_person.sid);
  return jsonb_build_object('ok',true,'code',case when v_action='suspend' then 'AUTHORIZED_PERSON_SUSPENDED' else 'AUTHORIZED_PERSON_REACTIVATED' end,'person',to_jsonb(v_person));
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_primary_parent_pickup_identity(p_parent_id text, p_photo_portrait text, p_photo_full_body text, p_id_doc_type text, p_id_doc_last4 text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_role text:=private.current_app_role();
  v_actor_id text:=private.current_app_user_id();
  v_actor_name text;
  v_parent public.users%rowtype;
  v_portrait text:=nullif(btrim(coalesce(p_photo_portrait,'')),'');
  v_full text:=nullif(btrim(coalesce(p_photo_full_body,'')),'');
  v_doc_type text:=nullif(btrim(coalesce(p_id_doc_type,'')),'');
  v_doc_last4 text:=nullif(btrim(coalesce(p_id_doc_last4,'')),'');
begin
  if v_role not in ('direction','direction2') then return jsonb_build_object('ok',false,'code','FORBIDDEN'); end if;
  select name into v_actor_name from public.users where id=v_actor_id and status='active';
  if not found then return jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); end if;
  if v_portrait is null or lower(v_portrait) like 'data:%' or length(v_portrait)>2048 then return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','photo_portrait'); end if;
  if v_full is null or lower(v_full) like 'data:%' or length(v_full)>2048 then return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','photo_full_body'); end if;
  if v_doc_type is null or length(v_doc_type)>80 then return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','id_doc_type'); end if;
  if v_doc_last4 is null or length(v_doc_last4) not between 2 and 12 then return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','id_doc_last4'); end if;
  update public.users set photo_url=v_portrait,identity_full_body_photo_url=v_full,
    identity_document_type=v_doc_type,identity_document_last4=v_doc_last4,updated_at=now()
  where id=p_parent_id and role='parent' returning * into v_parent;
  if not found then return jsonb_build_object('ok',false,'code','PARENT_NOT_FOUND'); end if;
  perform private.write_audit_event(v_actor_id,v_actor_name,'primary_parent_pickup_identity_updated',
    jsonb_build_object('parent_id',v_parent.id,'has_portrait',true,'has_full_body',true),v_parent.id);
  return jsonb_build_object('ok',true,'code','PRIMARY_PARENT_IDENTITY_SAVED','parent',to_jsonb(v_parent));
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_student_primary_parent(p_sid text, p_parent_id text)
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
  v_parent_id text:=nullif(btrim(coalesce(p_parent_id,'')),'');
begin
  if v_role not in ('direction','direction2') then return jsonb_build_object('ok',false,'code','FORBIDDEN'); end if;
  select name into v_actor_name from public.users where id=v_actor_id and status='active';
  if not found then return jsonb_build_object('ok',false,'code','ACTOR_NOT_FOUND'); end if;
  select * into s from public.students where id=p_sid and not coalesce(archived,false) for update;
  if not found then return jsonb_build_object('ok',false,'code','STUDENT_NOT_FOUND'); end if;
  if v_parent_id is not null then
    select * into p from public.users where id=v_parent_id and role='parent' and status='active';
    if not found then return jsonb_build_object('ok',false,'code','PARENT_NOT_FOUND'); end if;
  end if;
  update public.students set pid=v_parent_id where id=s.id returning * into s;
  perform private.write_audit_event(v_actor_id,v_actor_name,'student_primary_parent_changed',
    jsonb_build_object('student_id',s.id,'new_parent_id',v_parent_id),s.id);
  return jsonb_build_object('ok',true,'code','PRIMARY_PARENT_UPDATED','student',to_jsonb(s));
end;
$function$;

COMMIT;
