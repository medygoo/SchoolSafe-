create or replace function private.enforce_school_file_archive_audit()
returns trigger
language plpgsql
security invoker
set search_path=''
as $$
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
$$;

revoke all on function private.enforce_school_file_archive_audit() from public;

drop trigger if exists school_files_enforce_archive_audit on public.school_files;
create trigger school_files_enforce_archive_audit
before insert or update of archived_at, archived_by, restored_at, restored_by
on public.school_files
for each row execute function private.enforce_school_file_archive_audit();
