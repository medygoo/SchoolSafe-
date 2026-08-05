alter table public.school_files
  add column if not exists archived_by uuid,
  add column if not exists restored_at timestamptz,
  add column if not exists restored_by uuid;

alter table public.administrative_documents
  add column if not exists archived_by text,
  add column if not exists restored_at timestamptz,
  add column if not exists restored_by text;

do $$ begin
  if not exists (select 1 from pg_constraint where conname='school_files_archived_by_fkey') then
    alter table public.school_files add constraint school_files_archived_by_fkey foreign key (archived_by) references auth.users(id) on delete set null;
  end if;
  if not exists (select 1 from pg_constraint where conname='school_files_restored_by_fkey') then
    alter table public.school_files add constraint school_files_restored_by_fkey foreign key (restored_by) references auth.users(id) on delete set null;
  end if;
  if not exists (select 1 from pg_constraint where conname='administrative_documents_archived_by_fkey') then
    alter table public.administrative_documents add constraint administrative_documents_archived_by_fkey foreign key (archived_by) references public.users(id) on update cascade on delete set null;
  end if;
  if not exists (select 1 from pg_constraint where conname='administrative_documents_restored_by_fkey') then
    alter table public.administrative_documents add constraint administrative_documents_restored_by_fkey foreign key (restored_by) references public.users(id) on update cascade on delete set null;
  end if;
end $$;

create index if not exists school_files_idx_archive_lookup on public.school_files (academic_year, archived_at desc) where archived_at is not null and deleted_at is null;
create index if not exists administrative_documents_idx_archive_lookup on public.administrative_documents (school_year, archived_at desc) where status='archived';

alter table public.administrative_documents alter column school_year set default private.current_school_year();

create or replace function public.create_administrative_document(
  p_document_type_id text,
  p_title text,
  p_document_number text default null,
  p_document_date date default null,
  p_period_start date default null,
  p_period_end date default null,
  p_provider text default null,
  p_amount numeric default null,
  p_currency text default 'USD',
  p_notes text default null,
  p_school_year text default null,
  p_confidentiality text default 'administrative'
)
returns jsonb
language plpgsql
security invoker
set search_path=''
as $$
declare
  v_doc public.administrative_documents;
  v_year text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  v_year := coalesce(nullif(btrim(p_school_year),''), private.current_school_year());
  if v_year !~ '^\d{4}-\d{4}$' then raise exception 'Invalid school year'; end if;
  insert into public.administrative_documents(document_type_id,title,document_number,document_date,period_start,period_end,provider,amount,currency,notes,school_year,confidentiality,created_by)
  values(p_document_type_id,btrim(p_title),nullif(btrim(p_document_number),''),p_document_date,p_period_start,p_period_end,nullif(btrim(p_provider),''),p_amount,upper(coalesce(nullif(btrim(p_currency),''),'USD')),nullif(btrim(p_notes),''),v_year,p_confidentiality,private.current_app_user_id())
  returning * into v_doc;
  return to_jsonb(v_doc);
end;
$$;
revoke all on function public.create_administrative_document(text,text,text,date,date,date,text,numeric,text,text,text,text) from public;
grant execute on function public.create_administrative_document(text,text,text,date,date,date,text,numeric,text,text,text,text) to authenticated;

create or replace function private.set_administrative_document_archive_state(p_document_id text,p_archive boolean)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
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
      where id=p_document_id and status in ('draft','active')
      returning * into v_doc;
    if v_doc.id is null then raise exception 'Administrative document not found or unavailable for archive'; end if;
    update public.school_files
      set archived_at=coalesce(archived_at,now()), archived_by=v_auth_id, restored_at=null, restored_by=null,
          metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('status','archived','archive_scope','administrative_document')
      where administrative_document_id=p_document_id and deleted_at is null;
    get diagnostics v_file_count=row_count;
  else
    update public.administrative_documents
      set status='active', archived_at=null, archived_by=null, restored_at=now(), restored_by=v_app_user_id, updated_at=now()
      where id=p_document_id and status='archived'
      returning * into v_doc;
    if v_doc.id is null then raise exception 'Administrative document not found or not archived'; end if;
    update public.school_files
      set archived_at=null, archived_by=null, restored_at=now(), restored_by=v_auth_id,
          metadata=(coalesce(metadata,'{}'::jsonb)-'archive_scope')||jsonb_build_object('status','ready')
      where administrative_document_id=p_document_id and deleted_at is null;
    get diagnostics v_file_count=row_count;
  end if;
  return to_jsonb(v_doc)||jsonb_build_object('file_count',v_file_count,'archive_action',case when p_archive then 'archived' else 'restored' end);
end;
$$;
revoke all on function private.set_administrative_document_archive_state(text,boolean) from public;
grant execute on function private.set_administrative_document_archive_state(text,boolean) to authenticated, service_role;

create or replace function public.archive_administrative_document(p_document_id text)
returns jsonb language sql security invoker set search_path='' as $$ select private.set_administrative_document_archive_state(p_document_id,true) $$;
create or replace function public.restore_administrative_document(p_document_id text)
returns jsonb language sql security invoker set search_path='' as $$ select private.set_administrative_document_archive_state(p_document_id,false) $$;
revoke all on function public.archive_administrative_document(text) from public;
revoke all on function public.restore_administrative_document(text) from public;
grant execute on function public.archive_administrative_document(text) to authenticated;
grant execute on function public.restore_administrative_document(text) to authenticated;

drop policy if exists administrative_documents_update on public.administrative_documents;
create policy administrative_documents_update on public.administrative_documents for update to authenticated
using (
 status in ('draft','active') and (
  private.current_app_role()='direction' or
  (private.current_app_role()='direction2' and not is_financial and confidentiality='administrative') or
  (private.current_app_role()='direction3' and is_financial)
 )
)
with check (
 status in ('draft','active') and (
  private.current_app_role()='direction' or
  (private.current_app_role()='direction2' and confidentiality='administrative' and exists(select 1 from public.administrative_document_types t where t.id=document_type_id and t.active and not t.is_financial)) or
  (private.current_app_role()='direction3' and exists(select 1 from public.administrative_document_types t where t.id=document_type_id and t.active and t.is_financial))
 )
);

revoke insert,update,delete on table public.school_files from authenticated;
drop policy if exists school_files_direction_all on public.school_files;
drop policy if exists school_files_direction_select on public.school_files;
create policy school_files_direction_select on public.school_files for select to authenticated using ((select private.is_direction()));
