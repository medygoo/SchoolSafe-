-- Parent-only pedagogic context: owned student, class teachers, timetable and approved content.

create or replace function public.get_parent_pedagogic_context(p_sid text)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
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

  select * into v_student
  from public.students
  where id=p_sid and not coalesce(archived,false) and coalesce(access_parent,true);
  if not found then
    raise exception 'Élève introuvable' using errcode='P0002';
  end if;

  select * into v_class from public.classes where id=v_student.cid;
  if not found then
    raise exception 'Classe introuvable' using errcode='P0002';
  end if;

  with assigned as (
    select v_class.titulaire_id as user_id,'titulaire'::text as assignment
    union all select v_class.teacher_id,'enseignant_fr'
    union all select v_class.teacher_id_en,'enseignant_en'
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'assignment',a.assignment,
    'name',u.name,
    'role',case u.role
      when 'direction_pedagogique' then 'direction2'
      when 'caisse' then 'direction3'
      else u.role end
  ) order by a.assignment) filter(where u.id is not null),'[]'::jsonb)
  into v_teachers
  from assigned a
  left join public.users u on u.id=a.user_id and u.status='active';

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',t.id,
    'day',t.day,
    'period',t.period,
    'subject',t.matiere,
    'teacher_name',u.name
  ) order by t.day,t.period,t.id),'[]'::jsonb)
  into v_timetable
  from public.timetables t
  left join public.users u on u.id=t.teacher_id and u.status='active'
  where t.cid=v_student.cid;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',c.id,
    'date',c.date,
    'subject',c.matiere,
    'chapter',c.chapitre,
    'content',c.content,
    'homework',c.devoirs,
    'next_lesson',c.prochain,
    'language',c.lang,
    'teacher_name',u.name
  ) order by c.date desc,c.id desc),'[]'::jsonb)
  into v_cahier
  from public.cahier_texte c
  left join public.users u on u.id=c.by and u.status='active'
  where c.cid=v_student.cid
    and lower(coalesce(c.status,'')) in ('approved','published','validated');

  return jsonb_build_object(
    'contract_version',1,
    'student',jsonb_build_object(
      'id',v_student.id,'name',v_student.name,'matricule',v_student.mat,'photo_url',v_student.photo
    ),
    'class',jsonb_build_object(
      'id',v_class.id,'name',v_class.name,'cycle',v_class.cycle,'option',v_class.option
    ),
    'teachers',v_teachers,
    'timetable',v_timetable,
    'cahier_texte',v_cahier,
    'generated_at',now()
  );
end;
$$;

revoke all on function public.get_parent_pedagogic_context(text) from public;
revoke all on function public.get_parent_pedagogic_context(text) from anon;
grant execute on function public.get_parent_pedagogic_context(text) to authenticated;
grant execute on function public.get_parent_pedagogic_context(text) to service_role;

comment on function public.get_parent_pedagogic_context(text) is
  'Parent-only pedagogic contract for one owned student: class teachers, timetable and approved/published/validated cahier de texte without private contacts.';
