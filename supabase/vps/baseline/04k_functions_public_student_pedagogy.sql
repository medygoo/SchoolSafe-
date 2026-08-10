-- SchoolSafe VPS baseline - 04k student/pedagogy RPCs

BEGIN;

CREATE OR REPLACE FUNCTION public.get_parent_pedagogic_context(p_sid text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_student public.students%rowtype;
  v_class public.classes%rowtype;
  v_teachers jsonb;
  v_timetable jsonb;
  v_cahier jsonb;
begin
  if private.current_app_role()<>'parent' or not private.owns_student(p_sid) then
    raise exception 'Accès refusé' using errcode='42501';
  end if;
  select * into v_student from public.students where id=p_sid and not coalesce(archived,false) and coalesce(access_parent,true);
  if not found then raise exception 'Élève introuvable' using errcode='P0002'; end if;
  select * into v_class from public.classes where id=v_student.cid;
  if not found then raise exception 'Classe introuvable' using errcode='P0002'; end if;

  with assigned as (
    select v_class.titulaire_id as user_id,'titulaire'::text as assignment
    union all select v_class.teacher_id,'enseignant_fr'
    union all select v_class.teacher_id_en,'enseignant_en'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'assignment',a.assignment,'name',u.name,
    'role',case u.role when 'direction_pedagogique' then 'direction2' when 'caisse' then 'direction3' else u.role end
  ) order by a.assignment) filter(where u.id is not null),'[]'::jsonb)
  into v_teachers from assigned a left join public.users u on u.id=a.user_id and u.status='active';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',t.id,'day',t.day,'period',t.period,'subject',t.matiere,'teacher_name',u.name
  ) order by t.day,t.period,t.id),'[]'::jsonb)
  into v_timetable from public.timetables t
  left join public.users u on u.id=t.teacher_id and u.status='active'
  where t.cid=v_student.cid;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,'date',c.date,'subject',c.matiere,'chapter',c.chapitre,'content',c.content,
    'homework',c.devoirs,'next_lesson',c.prochain,'language',c.lang,'teacher_name',u.name
  ) order by c.date desc,c.id desc),'[]'::jsonb)
  into v_cahier from public.cahier_texte c
  left join public.users u on u.id=c.by and u.status='active'
  where c.cid=v_student.cid and lower(coalesce(c.status,'')) in ('approved','published','validated');

  return jsonb_build_object(
    'contract_version',1,
    'student',jsonb_build_object('id',v_student.id,'name',v_student.name,'matricule',v_student.mat,'photo_url',v_student.photo),
    'class',jsonb_build_object('id',v_class.id,'name',v_class.name,'cycle',v_class.cycle,'option',v_class.option),
    'teachers',v_teachers,'timetable',v_timetable,'cahier_texte',v_cahier,'generated_at',now()
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_student_profile(p_student jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_role text := private.current_app_role();
  v_actor_id text := private.current_app_user_id();
  v_actor_name text;
  v_id text := btrim(coalesce(p_student->>'id', ''));
  v_name text; v_mat text; v_cid text; v_pid text; v_dob text; v_photo text; v_adresse text;
  v_nom_papa text; v_nom_maman text; v_lieu_naissance text; v_num_inscription text;
  v_access_parent boolean := true;
  v_may_leave_alone boolean := false;
  v_leave_alone_until date;
  v_exists boolean;
  v_student public.students%rowtype;
begin
  if p_student is null or jsonb_typeof(p_student) <> 'object' then return jsonb_build_object('ok', false, 'code', 'INVALID_PAYLOAD'); end if;
  if v_role not in ('direction', 'direction2') then return jsonb_build_object('ok', false, 'code', 'FORBIDDEN'); end if;
  select name into v_actor_name from public.users where id = v_actor_id and status = 'active' limit 1;
  if not found then return jsonb_build_object('ok', false, 'code', 'ACTOR_NOT_FOUND'); end if;
  if v_id = '' or length(v_id) > 160 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'id'); end if;
  select exists(select 1 from public.students where id = v_id) into v_exists;

  v_name := case when p_student ? 'name' then nullif(btrim(coalesce(p_student->>'name', '')), '') when v_exists then (select name from public.students where id = v_id) else null end;
  v_cid := case when p_student ? 'cid' then nullif(btrim(coalesce(p_student->>'cid', '')), '') when v_exists then (select cid from public.students where id = v_id) else null end;
  if v_name is null or length(v_name) > 200 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'name'); end if;
  if v_cid is null or length(v_cid) > 160 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'cid'); end if;
  if not exists(select 1 from public.classes where id = v_cid) then return jsonb_build_object('ok', false, 'code', 'CLASS_NOT_FOUND'); end if;

  v_mat := case when p_student ? 'mat' then nullif(btrim(coalesce(p_student->>'mat', '')), '') when v_exists then (select mat from public.students where id = v_id) else null end;
  if v_mat is not null and length(v_mat) > 100 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'mat'); end if;
  if v_mat is not null and exists(select 1 from public.students where id <> v_id and mat is not null and lower(btrim(mat)) = lower(v_mat)) then return jsonb_build_object('ok', false, 'code', 'MATRICULE_IN_USE'); end if;

  v_pid := case when p_student ? 'pid' then nullif(btrim(coalesce(p_student->>'pid', '')), '') when v_exists then (select pid from public.students where id = v_id) else null end;
  if v_pid is not null then
    if length(v_pid) > 160 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'pid'); end if;
    if not exists(select 1 from public.users where id = v_pid and role = 'parent' and status = 'active') then return jsonb_build_object('ok', false, 'code', 'PARENT_NOT_FOUND'); end if;
  end if;

  v_dob := case when p_student ? 'dob' then nullif(btrim(coalesce(p_student->>'dob', '')), '') when v_exists then (select dob from public.students where id = v_id) else null end;
  v_photo := case when p_student ? 'photo' then nullif(btrim(coalesce(p_student->>'photo', '')), '') when v_exists then (select photo from public.students where id = v_id) else null end;
  v_adresse := case when p_student ? 'adresse' then nullif(btrim(coalesce(p_student->>'adresse', '')), '') when v_exists then (select adresse from public.students where id = v_id) else null end;
  v_nom_papa := case when p_student ? 'nom_papa' then nullif(btrim(coalesce(p_student->>'nom_papa', '')), '') when v_exists then (select nom_papa from public.students where id = v_id) else null end;
  v_nom_maman := case when p_student ? 'nom_maman' then nullif(btrim(coalesce(p_student->>'nom_maman', '')), '') when v_exists then (select nom_maman from public.students where id = v_id) else null end;
  v_lieu_naissance := case when p_student ? 'lieu_naissance' then nullif(btrim(coalesce(p_student->>'lieu_naissance', '')), '') when v_exists then (select lieu_naissance from public.students where id = v_id) else null end;
  v_num_inscription := case when p_student ? 'num_inscription' then nullif(btrim(coalesce(p_student->>'num_inscription', '')), '') when v_exists then (select num_inscription from public.students where id = v_id) else null end;

  if length(coalesce(v_dob, '')) > 30 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'dob'); end if;
  if length(coalesce(v_photo, '')) > 2048 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'photo'); end if;
  if v_photo is not null and lower(v_photo) like 'data:%' then return jsonb_build_object('ok', false, 'code', 'PHOTO_MUST_BE_FILE_REFERENCE'); end if;
  if length(coalesce(v_adresse, '')) > 500 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'adresse'); end if;
  if length(coalesce(v_nom_papa, '')) > 200 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'nom_papa'); end if;
  if length(coalesce(v_nom_maman, '')) > 200 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'nom_maman'); end if;
  if length(coalesce(v_lieu_naissance, '')) > 200 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'lieu_naissance'); end if;
  if length(coalesce(v_num_inscription, '')) > 100 then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'num_inscription'); end if;

  if p_student ? 'access_parent' then
    if jsonb_typeof(p_student->'access_parent') <> 'boolean' then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'access_parent'); end if;
    v_access_parent := (p_student->>'access_parent')::boolean;
  elsif v_exists then select access_parent into v_access_parent from public.students where id = v_id; end if;

  if p_student ? 'may_leave_alone' then
    if jsonb_typeof(p_student->'may_leave_alone') <> 'boolean' then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'may_leave_alone'); end if;
    v_may_leave_alone := (p_student->>'may_leave_alone')::boolean;
  elsif v_exists then select may_leave_alone into v_may_leave_alone from public.students where id = v_id; end if;

  if p_student ? 'leave_alone_until' then
    if nullif(btrim(coalesce(p_student->>'leave_alone_until', '')), '') is not null then
      begin v_leave_alone_until := (p_student->>'leave_alone_until')::date;
      exception when invalid_datetime_format or datetime_field_overflow then return jsonb_build_object('ok', false, 'code', 'VALIDATION_ERROR', 'field', 'leave_alone_until'); end;
    end if;
  elsif v_exists then select leave_alone_until into v_leave_alone_until from public.students where id = v_id; end if;
  if v_may_leave_alone and v_leave_alone_until is null then return jsonb_build_object('ok', false, 'code', 'LEAVE_AUTHORIZATION_DATE_REQUIRED'); end if;
  if not v_may_leave_alone then v_leave_alone_until := null; end if;

  if v_exists then
    update public.students set name=v_name,mat=v_mat,cid=v_cid,pid=v_pid,dob=v_dob,photo=v_photo,adresse=v_adresse,
      nom_papa=v_nom_papa,nom_maman=v_nom_maman,lieu_naissance=v_lieu_naissance,num_inscription=v_num_inscription,
      access_parent=v_access_parent,may_leave_alone=v_may_leave_alone,leave_alone_until=v_leave_alone_until,
      leave_alone_authorized_by=case when v_may_leave_alone then v_actor_id else null end,
      leave_alone_authorized_at=case when v_may_leave_alone then now() else null end
    where id=v_id returning * into v_student;
    return jsonb_build_object('ok', true, 'code', 'STUDENT_UPDATED', 'student', to_jsonb(v_student));
  end if;

  insert into public.students(id,name,mat,cid,pid,dob,photo,adresse,nom_papa,nom_maman,created_by,created_by_name,
    access_parent,archived,created_at,lieu_naissance,num_inscription,may_leave_alone,leave_alone_until,leave_alone_authorized_by,leave_alone_authorized_at)
  values(v_id,v_name,v_mat,v_cid,v_pid,v_dob,v_photo,v_adresse,v_nom_papa,v_nom_maman,v_actor_id,v_actor_name,
    v_access_parent,false,to_char(timezone('Africa/Kinshasa', now()), 'YYYY-MM-DD"T"HH24:MI:SS'),v_lieu_naissance,v_num_inscription,
    v_may_leave_alone,v_leave_alone_until,case when v_may_leave_alone then v_actor_id else null end,
    case when v_may_leave_alone then now() else null end)
  returning * into v_student;
  return jsonb_build_object('ok', true, 'code', 'STUDENT_CREATED', 'student', to_jsonb(v_student));
exception
  when foreign_key_violation then return jsonb_build_object('ok', false, 'code', 'REFERENCE_NOT_FOUND');
  when unique_violation then return jsonb_build_object('ok', false, 'code', 'DUPLICATE_STUDENT');
end;
$function$;

COMMIT;
