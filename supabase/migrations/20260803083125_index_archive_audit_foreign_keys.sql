create index if not exists school_files_idx_archived_by
  on public.school_files (archived_by)
  where archived_by is not null;

create index if not exists school_files_idx_restored_by
  on public.school_files (restored_by)
  where restored_by is not null;

create index if not exists administrative_documents_idx_archived_by
  on public.administrative_documents (archived_by)
  where archived_by is not null;

create index if not exists administrative_documents_idx_restored_by
  on public.administrative_documents (restored_by)
  where restored_by is not null;
