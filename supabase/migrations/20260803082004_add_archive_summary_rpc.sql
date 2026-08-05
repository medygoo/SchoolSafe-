create or replace function public.get_archive_summary()
returns table(
  academic_year text,
  file_count bigint,
  total_bytes numeric,
  first_archived_at timestamptz,
  last_archived_at timestamptz
)
language sql
stable
security invoker
set search_path=''
as $$
  select sf.academic_year,
         count(*)::bigint,
         coalesce(sum(sf.size_bytes),0)::numeric,
         min(sf.archived_at),
         max(sf.archived_at)
  from public.school_files sf
  where sf.archived_at is not null
    and sf.deleted_at is null
    and private.current_app_role()='direction'
  group by sf.academic_year
  order by sf.academic_year desc
$$;

revoke all on function public.get_archive_summary() from public;
grant execute on function public.get_archive_summary() to authenticated;
