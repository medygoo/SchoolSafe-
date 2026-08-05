create or replace function private.current_school_year()
returns text
language plpgsql
stable
security definer
set search_path = ''
as $$
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
$$;

revoke all on function private.current_school_year() from public;
grant execute on function private.current_school_year() to authenticated, service_role;

create or replace function private.teacher_has_class_access(p_cid text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
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
$$;

create or replace function private.parent_has_child_in_class(p_cid text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    private.current_app_role() = 'parent'
    and exists (
      select 1
      from public.students s
      where s.cid = p_cid
        and s.pid = private.current_app_user_id()
        and coalesce(s.archived, false) = false
        and coalesce(s.access_parent, true) = true
    ),
    false
  )
$$;

revoke all on function private.teacher_has_class_access(text) from public;
revoke all on function private.parent_has_child_in_class(text) from public;
grant execute on function private.teacher_has_class_access(text) to authenticated, service_role;
grant execute on function private.parent_has_child_in_class(text) to authenticated, service_role;

create or replace function private.validate_school_file_metadata()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_expected_year text;
  v_exists boolean := false;
begin
  if new.owner_id is null or btrim(new.owner_id) = '' then
    raise exception 'school_files owner_id is required';
  end if;

  case new.owner_type
    when 'student' then
      select exists(select 1 from public.students s where s.id = new.owner_id) into v_exists;
    when 'user' then
      select exists(select 1 from public.users u where u.id = new.owner_id) into v_exists;
    when 'authorized_person' then
      select exists(select 1 from public.aps a where a.id = new.owner_id) into v_exists;
    when 'class' then
      select exists(select 1 from public.classes c where c.id = new.owner_id) into v_exists;
    when 'school' then
      select exists(select 1 from public.settings s where s.id = new.owner_id) into v_exists;
    when 'devoir' then
      select exists(select 1 from public.devoirs d where d.id = new.owner_id) into v_exists;
    when 'cahier_prep' then
      select exists(select 1 from public.cahier_prep c where c.id = new.owner_id) into v_exists;
    when 'administrative_document' then
      select exists(select 1 from public.administrative_documents d where d.id = new.owner_id) into v_exists;
    else
      raise exception 'Unsupported school_files owner_type: %', new.owner_type;
  end case;

  if not v_exists then
    raise exception 'school_files owner does not exist: %/%', new.owner_type, new.owner_id;
  end if;

  if not (
    (new.owner_type = 'student' and new.category in ('document','photo','identity','card','receipt','homework','report')) or
    (new.owner_type = 'user' and new.category in ('document','photo','identity')) or
    (new.owner_type = 'authorized_person' and new.category in ('document','photo','identity')) or
    (new.owner_type = 'class' and new.category in ('document','homework','report')) or
    (new.owner_type = 'school' and new.category in ('document','report','archive')) or
    (new.owner_type = 'devoir' and new.category in ('document','homework')) or
    (new.owner_type = 'cahier_prep' and new.category = 'teacher_preparation') or
    (new.owner_type = 'administrative_document' and new.category = 'administrative_document')
  ) then
    raise exception 'Invalid owner/category combination: %/%', new.owner_type, new.category;
  end if;

  if new.owner_type = 'cahier_prep' then
    new.cahier_prep_id := new.owner_id;
    new.administrative_document_id := null;
  elsif new.owner_type = 'administrative_document' then
    new.administrative_document_id := new.owner_id;
    new.cahier_prep_id := null;
  else
    new.cahier_prep_id := null;
    new.administrative_document_id := null;
  end if;

  if new.category = 'receipt' then
    if new.owner_type <> 'student' or new.payment_transaction_id is null then
      raise exception 'Receipt requires a student owner and payment transaction';
    end if;

    select p.school_year into v_expected_year
    from public.payment_transactions p
    where p.id = new.payment_transaction_id
      and p.sid = new.owner_id
      and p.status = 'confirmed';

    if v_expected_year is null then
      raise exception 'Receipt transaction is missing, mismatched or not confirmed';
    end if;
  elsif new.payment_transaction_id is not null then
    raise exception 'payment_transaction_id is only allowed for receipt files';
  elsif new.owner_type = 'administrative_document' then
    select d.school_year into v_expected_year
    from public.administrative_documents d
    where d.id = new.owner_id;
  else
    v_expected_year := private.current_school_year();
  end if;

  if v_expected_year is null or v_expected_year !~ '^\d{4}-\d{4}$' then
    raise exception 'Unable to resolve a valid academic year';
  end if;

  if new.academic_year is null or btrim(new.academic_year) = '' then
    new.academic_year := v_expected_year;
  elsif new.academic_year <> v_expected_year then
    raise exception 'Academic year mismatch: expected %, received %', v_expected_year, new.academic_year;
  end if;

  return new;
end;
$$;

revoke all on function private.validate_school_file_metadata() from public;

drop trigger if exists school_files_validate_metadata on public.school_files;
create trigger school_files_validate_metadata
before insert or update of owner_type, owner_id, category, academic_year, payment_transaction_id, cahier_prep_id, administrative_document_id
on public.school_files
for each row execute function private.validate_school_file_metadata();

alter table public.school_files
  alter column academic_year set not null;

alter table public.school_files
  drop constraint if exists school_files_academic_year_format_check;
alter table public.school_files
  add constraint school_files_academic_year_format_check
  check (academic_year ~ '^\d{4}-\d{4}$');

drop policy if exists devoirs_direction_all on public.devoirs;
drop policy if exists devoirs_select on public.devoirs;
drop policy if exists devoirs_insert on public.devoirs;
drop policy if exists devoirs_update on public.devoirs;
drop policy if exists devoirs_delete on public.devoirs;

create policy devoirs_select
on public.devoirs
for select
to authenticated
using (
  private.current_app_role() in ('direction','direction2')
  or (
    private.current_app_role() = 'enseignant'
    and (
      teacher_id = private.current_app_user_id()
      or private.teacher_has_class_access(cid)
    )
  )
  or private.parent_has_child_in_class(cid)
);

create policy devoirs_insert
on public.devoirs
for insert
to authenticated
with check (
  private.current_app_role() = 'direction'
  or (
    private.current_app_role() = 'enseignant'
    and teacher_id = private.current_app_user_id()
    and private.teacher_has_class_access(cid)
  )
);

create policy devoirs_update
on public.devoirs
for update
to authenticated
using (
  private.current_app_role() in ('direction','direction2')
  or (
    private.current_app_role() = 'enseignant'
    and teacher_id = private.current_app_user_id()
    and private.teacher_has_class_access(cid)
  )
)
with check (
  private.current_app_role() in ('direction','direction2')
  or (
    private.current_app_role() = 'enseignant'
    and teacher_id = private.current_app_user_id()
    and private.teacher_has_class_access(cid)
  )
);

create policy devoirs_delete
on public.devoirs
for delete
to authenticated
using (
  private.current_app_role() = 'direction'
  or (
    private.current_app_role() = 'enseignant'
    and teacher_id = private.current_app_user_id()
    and private.teacher_has_class_access(cid)
    and coalesce(status, 'brouillon') in ('brouillon','draft')
  )
);
