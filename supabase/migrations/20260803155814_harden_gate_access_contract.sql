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
  if not private.can_scan() then
    raise exception 'Accès refusé';
  end if;

  if nullif(btrim(coalesce(p_sid, '')), '') is null then
    return jsonb_build_object(
      'student_id', null,
      'student_name', null,
      'matricule', null,
      'class_id', null,
      'class_name', null,
      'photo_url', null,
      'access_status', 'unavailable',
      'allowed', false,
      'instruction', 'Contrôle manuel requis',
      'checked_at', now()
    );
  end if;

  select * into stu
  from public.students
  where id = p_sid
    and not coalesce(archived, false);

  if not found then
    return jsonb_build_object(
      'student_id', p_sid,
      'student_name', null,
      'matricule', null,
      'class_id', null,
      'class_name', null,
      'photo_url', null,
      'access_status', 'unavailable',
      'allowed', false,
      'instruction', 'Élève introuvable — contrôle manuel requis',
      'checked_at', now()
    );
  end if;

  st := private.compute_payment_state(p_sid);

  if not coalesce((st->>'student_found')::boolean, false) then
    return jsonb_build_object(
      'student_id', p_sid,
      'student_name', stu.name,
      'matricule', stu.mat,
      'class_id', stu.cid,
      'class_name', null,
      'photo_url', stu.photo,
      'access_status', 'unavailable',
      'allowed', false,
      'instruction', 'Contrôle manuel requis',
      'checked_at', now()
    );
  end if;

  select name into cls
  from public.classes
  where id = stu.cid;

  code := coalesce(st->>'access_status', 'unavailable');
  instruction := case code
    when 'allowed' then 'Accès autorisé'
    when 'exception' then 'Accès temporairement autorisé'
    when 'orient' then 'Accès autorisé — suivi administratif requis'
    when 'blocked' then 'Accès non autorisé — orienter vers la Caisse'
    else 'Contrôle manuel requis'
  end;

  return jsonb_build_object(
    'student_id', stu.id,
    'student_name', stu.name,
    'matricule', stu.mat,
    'class_id', stu.cid,
    'class_name', cls,
    'photo_url', stu.photo,
    'access_status', code,
    'allowed', coalesce((st->>'allowed')::boolean, false),
    'instruction', instruction,
    'checked_at', now()
  );
end;
$$;

revoke all on function public.get_gate_access_status(text) from public;
revoke all on function public.get_gate_access_status(text) from anon;
grant execute on function public.get_gate_access_status(text) to authenticated, service_role;

comment on function public.get_gate_access_status(text) is
'Contrat portail SchoolSafe v1 : identité minimale, décision serveur et instruction générique sans détail financier.';
