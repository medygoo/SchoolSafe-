-- SchoolSafe VPS baseline - 03g files/administration helpers

BEGIN;

CREATE OR REPLACE FUNCTION private.enforce_school_file_archive_audit()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  if new.archived_at is not null and new.archived_by is null then
    raise exception 'archived_by is required when a file is archived';
  end if;
  if tg_op='UPDATE' and old.archived_at is null and new.archived_at is not null then
    new.restored_at := null;
    new.restored_by := null;
  end if;
  if tg_op='UPDATE' and old.archived_at is not null and new.archived_at is null then
    if new.restored_at is null or new.restored_by is null then
      raise exception 'restored_at and restored_by are required when a file is restored';
    end if;
    new.archived_by := null;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.stamp_school_file_uploader()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_user public.users%rowtype;
  v_role text;
begin
  if tg_op='UPDATE' then
    new.uploaded_by := old.uploaded_by;
    new.uploaded_by_app_user_id := old.uploaded_by_app_user_id;
    new.uploaded_by_name := old.uploaded_by_name;
    new.uploaded_by_role := old.uploaded_by_role;
    return new;
  end if;
  if new.uploaded_by is null then raise exception 'Identité du téléverseur requise.' using errcode='23502'; end if;
  select * into v_user from public.users where auth_user_id=new.uploaded_by and status='active' limit 1;
  if not found then raise exception 'Profil SchoolSafe actif du téléverseur introuvable.' using errcode='42501'; end if;
  v_role := case v_user.role when 'direction_pedagogique' then 'direction2' when 'caisse' then 'direction3' else v_user.role end;
  new.uploaded_by_app_user_id := v_user.id;
  new.uploaded_by_name := v_user.name;
  new.uploaded_by_role := v_role;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.validate_school_file_metadata()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_expected_year text;
  v_exists boolean := false;
begin
  if new.owner_id is null or btrim(new.owner_id) = '' then raise exception 'school_files owner_id is required'; end if;
  case new.owner_type
    when 'student' then select exists(select 1 from public.students s where s.id = new.owner_id) into v_exists;
    when 'user' then select exists(select 1 from public.users u where u.id = new.owner_id) into v_exists;
    when 'authorized_person' then select exists(select 1 from public.aps a where a.id = new.owner_id) into v_exists;
    when 'class' then select exists(select 1 from public.classes c where c.id = new.owner_id) into v_exists;
    when 'school' then select exists(select 1 from public.settings s where s.id = new.owner_id) into v_exists;
    when 'devoir' then select exists(select 1 from public.devoirs d where d.id = new.owner_id) into v_exists;
    when 'cahier_prep' then select exists(select 1 from public.cahier_prep c where c.id = new.owner_id) into v_exists;
    when 'administrative_document' then select exists(select 1 from public.administrative_documents d where d.id = new.owner_id) into v_exists;
    else raise exception 'Unsupported school_files owner_type: %', new.owner_type;
  end case;
  if not v_exists then raise exception 'school_files owner does not exist: %/%', new.owner_type, new.owner_id; end if;

  if not (
    (new.owner_type = 'student' and new.category in ('document','photo','identity','card','receipt','homework','report')) or
    (new.owner_type = 'user' and new.category in ('document','photo','identity')) or
    (new.owner_type = 'authorized_person' and new.category in ('document','photo','identity')) or
    (new.owner_type = 'class' and new.category in ('document','homework','report')) or
    (new.owner_type = 'school' and new.category in ('document','report','archive')) or
    (new.owner_type = 'devoir' and new.category in ('document','homework')) or
    (new.owner_type = 'cahier_prep' and new.category = 'teacher_preparation') or
    (new.owner_type = 'administrative_document' and new.category = 'administrative_document')
  ) then raise exception 'Invalid owner/category combination: %/%', new.owner_type, new.category; end if;

  if new.owner_type = 'cahier_prep' then
    new.cahier_prep_id := new.owner_id; new.administrative_document_id := null;
  elsif new.owner_type = 'administrative_document' then
    new.administrative_document_id := new.owner_id; new.cahier_prep_id := null;
  else
    new.cahier_prep_id := null; new.administrative_document_id := null;
  end if;

  if new.category = 'receipt' then
    if new.owner_type <> 'student' or new.payment_transaction_id is null then raise exception 'Receipt requires a student owner and payment transaction'; end if;
    select p.school_year into v_expected_year from public.payment_transactions p
    where p.id = new.payment_transaction_id and p.sid = new.owner_id and p.status = 'confirmed';
    if v_expected_year is null then raise exception 'Receipt transaction is missing, mismatched or not confirmed'; end if;
  elsif new.payment_transaction_id is not null then
    raise exception 'payment_transaction_id is only allowed for receipt files';
  elsif new.owner_type = 'administrative_document' then
    select d.school_year into v_expected_year from public.administrative_documents d where d.id = new.owner_id;
  else
    v_expected_year := private.current_school_year();
  end if;

  if v_expected_year is null or v_expected_year !~ '^\d{4}-\d{4}$' then raise exception 'Unable to resolve a valid academic year'; end if;
  if new.academic_year is null or btrim(new.academic_year) = '' then new.academic_year := v_expected_year;
  elsif new.academic_year <> v_expected_year then raise exception 'Academic year mismatch: expected %, received %', v_expected_year, new.academic_year; end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.set_administrative_document_fields()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_financial boolean;
begin
  select t.is_financial into v_financial from public.administrative_document_types t where t.id = new.document_type_id and t.active = true;
  if v_financial is null then raise exception 'Administrative document type is missing or inactive'; end if;
  new.is_financial := v_financial;
  new.currency := coalesce(nullif(upper(btrim(new.currency)), ''), 'USD');
  if v_financial then
    new.confidentiality := case when new.confidentiality = 'restricted' then 'restricted' else 'financial' end;
  elsif new.confidentiality = 'financial' then
    new.confidentiality := 'administrative';
  end if;
  new.updated_at := now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.set_administrative_document_archive_state(p_document_id text, p_archive boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_doc public.administrative_documents;
  v_auth_id uuid := auth.uid();
  v_app_user_id text := private.current_app_user_id();
  v_file_count integer := 0;
begin
  if v_auth_id is null or private.current_app_role() <> 'direction' then raise exception 'Direction 1 access required'; end if;
  if p_archive then
    update public.administrative_documents
      set status='archived', archived_at=now(), archived_by=v_app_user_id, restored_at=null, restored_by=null, updated_at=now()
      where id=p_document_id and status in ('draft','active') returning * into v_doc;
    if v_doc.id is null then raise exception 'Administrative document not found or unavailable for archive'; end if;
    update public.school_files
      set archived_at=coalesce(archived_at,now()), archived_by=v_auth_id, restored_at=null, restored_by=null,
          metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('status','archived','archive_scope','administrative_document')
      where administrative_document_id=p_document_id and deleted_at is null;
    get diagnostics v_file_count=row_count;
  else
    update public.administrative_documents
      set status='active', archived_at=null, archived_by=null, restored_at=now(), restored_by=v_app_user_id, updated_at=now()
      where id=p_document_id and status='archived' returning * into v_doc;
    if v_doc.id is null then raise exception 'Administrative document not found or not archived'; end if;
    update public.school_files
      set archived_at=null, archived_by=null, restored_at=now(), restored_by=v_auth_id,
          metadata=(coalesce(metadata,'{}'::jsonb)-'archive_scope')||jsonb_build_object('status','ready')
      where administrative_document_id=p_document_id and deleted_at is null;
    get diagnostics v_file_count=row_count;
  end if;
  return to_jsonb(v_doc)||jsonb_build_object('file_count',v_file_count,'archive_action',case when p_archive then 'archived' else 'restored' end);
end;
$function$;

CREATE OR REPLACE FUNCTION private.touch_administrative_document_type()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  new.updated_at := now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.sync_payroll_user_reference()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private'
AS $function$
declare
  v_teacher_is_user boolean;
begin
  if tg_op = 'UPDATE' and old.user_id is not null and new.user_id is null and new.teacher_id is not distinct from old.teacher_id then return new; end if;
  if new.user_id is not null then
    if not exists (select 1 from public.users u where u.id = new.user_id) then raise exception using errcode = '23503', message = 'PAYROLL_USER_NOT_FOUND'; end if;
    v_teacher_is_user := new.teacher_id is not null and exists (select 1 from public.users u where u.id = new.teacher_id);
    if v_teacher_is_user and new.teacher_id <> new.user_id then raise exception using errcode = '23514', message = 'PAYROLL_USER_MISMATCH'; end if;
    new.teacher_id := new.user_id;
  elsif new.teacher_id is not null and exists (select 1 from public.users u where u.id = new.teacher_id) then
    new.user_id := new.teacher_id;
  end if;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION private.stamp_conduct_period()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_year text;
  v_term text;
  v_settings_year text;
  v_settings_term text;
begin
  select nullif(btrim(s.year), ''), upper(nullif(btrim(s.currenttrimestre), '')) into v_settings_year, v_settings_term
  from public.settings s order by s.id limit 1;
  v_year := coalesce(nullif(btrim(new.year), ''), v_settings_year, private.current_school_year());
  v_term := upper(coalesce(nullif(btrim(new.trimestre), ''), v_settings_term));
  if v_year is null or v_year !~ '^\d{4}-\d{4}$' then raise exception 'Année scolaire invalide pour la conduite.' using errcode = '22023'; end if;
  if v_term not in ('T1', 'T2', 'T3') then raise exception 'Trimestre invalide pour la conduite.' using errcode = '22023'; end if;
  if tg_op = 'UPDATE' and (old.year is distinct from v_year or old.trimestre is distinct from v_term) then
    raise exception 'La période d une conduite enregistrée est immuable.' using errcode = '23514';
  end if;
  new.year := v_year;
  new.trimestre := v_term;
  return new;
end;
$function$;

COMMIT;
