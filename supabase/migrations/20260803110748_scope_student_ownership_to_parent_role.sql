create or replace function private.owns_student(p_sid text)
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
      where s.id = p_sid
        and s.pid = private.current_app_user_id()
        and coalesce(s.archived, false) = false
        and coalesce(s.access_parent, true) = true
    ),
    false
  )
$$;
