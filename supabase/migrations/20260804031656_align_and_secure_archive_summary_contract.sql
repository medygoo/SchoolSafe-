drop function if exists public.get_archive_summary();

create function public.get_archive_summary()
returns table(
  academic_year text,
  file_count bigint,
  total_bytes bigint,
  archived_count bigint,
  active_count bigint
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if private.current_app_role() <> 'direction' then
    raise exception 'Accès refusé' using errcode = '42501';
  end if;

  return query
  select
    sf.academic_year,
    count(*)::bigint as file_count,
    coalesce(sum(sf.size_bytes), 0)::bigint as total_bytes,
    count(*) filter (where sf.archived_at is not null)::bigint as archived_count,
    count(*) filter (where sf.archived_at is null)::bigint as active_count
  from public.school_files sf
  where sf.deleted_at is null
  group by sf.academic_year
  order by sf.academic_year desc;
end;
$$;

revoke all on function public.get_archive_summary() from public;
revoke all on function public.get_archive_summary() from anon;
grant execute on function public.get_archive_summary() to authenticated;
grant execute on function public.get_archive_summary() to service_role;

comment on function public.get_archive_summary() is
  'Direction 1 archive summary by academic year. Returns all non-deleted files split into archived and active counts.';
