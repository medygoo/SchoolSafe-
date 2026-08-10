-- SchoolSafe VPS baseline - 03a private core functions
-- Depend de 01_schemas_extensions.sql et des fichiers 02* tables.

BEGIN;

CREATE OR REPLACE FUNCTION private.normalize_phone_e164(p_phone text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare
  v_raw text := btrim(coalesce(p_phone, ''));
  v_compact text;
  v_digits text;
  v_result text;
begin
  if v_raw = '' then return null; end if;
  v_compact := regexp_replace(v_raw, '[[:space:]().\-]', '', 'g');
  if left(v_compact, 2) = '00' then v_compact := '+' || substr(v_compact, 3); end if;
  if left(v_compact, 1) = '+' then
    v_digits := substr(v_compact, 2);
    if v_digits !~ '^[1-9][0-9]{7,14}$' then return null; end if;
    return '+' || v_digits;
  end if;
  if v_compact !~ '^[0-9]+$' then return null; end if;
  if v_compact ~ '^0[0-9]{9}$' then
    v_result := '+243' || substr(v_compact, 2);
  elsif v_compact ~ '^243[0-9]{9}$' then
    v_result := '+' || v_compact;
  elsif v_compact ~ '^[89][0-9]{8}$' then
    v_result := '+243' || v_compact;
  else
    return null;
  end if;
  if v_result !~ '^\+[1-9][0-9]{7,14}$' then return null; end if;
  return v_result;
end;
$function$;

CREATE OR REPLACE FUNCTION private.normalize_school_phone(p_phone text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$ select nullif(regexp_replace(coalesce(p_phone, ''), '[^0-9]+', '', 'g'), ''); $function$;

CREATE OR REPLACE FUNCTION private.phone_auth_email(p_phone text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO ''
AS $function$
declare
  v_phone text := private.normalize_phone_e164(p_phone);
begin
  if v_phone is null then return null; end if;
  return 'p_' || pg_catalog.encode(extensions.digest(v_phone, 'sha256'), 'hex') || '@phone.invalid';
end;
$function$;

CREATE OR REPLACE FUNCTION private.current_app_user_id()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select u.id
  from public.users u
  where u.auth_user_id=auth.uid()
    and u.status='active'
    and u.access_ready
    and not u.must_change_password
  limit 1
$function$;

CREATE OR REPLACE FUNCTION private.current_app_role()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case u.role
    when 'direction_pedagogique' then 'direction2'
    when 'caisse' then 'direction3'
    else u.role
  end
  from public.users u
  where u.auth_user_id=auth.uid()
    and u.status='active'
    and u.access_ready
    and not u.must_change_password
  limit 1
$function$;

CREATE OR REPLACE FUNCTION private.current_school_year()
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_year text;
begin
  select s.year into v_year
  from public.settings s
  where s.id = 'main'
  limit 1;

  if v_year is null or v_year !~ '^\d{4}-\d{4}$' then
    raise exception 'Invalid current school year in settings';
  end if;

  return v_year;
end;
$function$;

CREATE OR REPLACE FUNCTION private.is_direction()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ select coalesce(private.current_app_role() = 'direction', false) $function$;

CREATE OR REPLACE FUNCTION private.is_direction_any()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ select coalesce(private.current_app_role() in ('direction', 'direction2'), false) $function$;

CREATE OR REPLACE FUNCTION private.teaches_class(p_cid text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists(
    select 1 from public.classes c
    where c.id = p_cid
      and private.current_app_user_id() in
        (c.teacher_id, c.teacher_id_en, c.titulaire_id)
  )
$function$;

CREATE OR REPLACE FUNCTION private.teacher_has_class_access(p_cid text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(
    private.current_app_role() = 'enseignant'
    and exists (
      select 1
      from public.classes c
      where c.id = p_cid
        and private.current_app_user_id() in (c.teacher_id, c.teacher_id_en, c.titulaire_id)
    ),
    false
  )
$function$;

CREATE OR REPLACE FUNCTION private.owns_student(p_sid text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(
    private.current_app_role() = 'parent'
    and exists (
      select 1
      from public.students s
      where s.id = p_sid
        and s.pid = private.current_app_user_id()
        and coalesce(s.archived, false) = false
        and coalesce(s.access_parent, true) = true
    ),
    false
  )
$function$;

CREATE OR REPLACE FUNCTION private.can_view_class(p_cid text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case private.current_app_role()
    when 'direction' then true
    when 'direction2' then true
    when 'direction3' then true
    when 'gardien' then true
    when 'enseignant' then private.teaches_class(p_cid)
    when 'parent' then exists(
      select 1 from public.students s
      where s.cid = p_cid and s.pid = private.current_app_user_id()
    )
    else false
  end
$function$;

CREATE OR REPLACE FUNCTION private.can_view_student(p_sid text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select case private.current_app_role()
    when 'direction' then true
    when 'direction2' then true
    when 'direction3' then true
    when 'enseignant' then exists(
      select 1 from public.students s
      where s.id = p_sid and private.teaches_class(s.cid)
    )
    when 'parent' then private.owns_student(p_sid)
    else false
  end
$function$;

CREATE OR REPLACE FUNCTION private.can_scan()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(private.current_app_role() in
    ('direction', 'direction2', 'direction3', 'enseignant', 'gardien'), false)
$function$;

CREATE OR REPLACE FUNCTION private.can_prepare_student_exit()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(private.current_app_role() in ('direction','direction2','enseignant','gardien'),false)
$function$;

CREATE OR REPLACE FUNCTION private.can_confirm_student_exit()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(private.current_app_role() in ('direction','direction2','enseignant','gardien'),false)
$function$;

COMMIT;
