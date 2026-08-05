-- Scanner contact privacy: only Direction 1 and Gardien receive pickup phone numbers.

create or replace function public.get_scanner_students()
returns table(
  id text, mat text, name text, photo text, cid text,
  blocked boolean, access_blocked boolean,
  may_leave_alone boolean, leave_alone_until date,
  pid text, primary_guardian_name text, primary_guardian_phone text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := private.current_app_role();
begin
  if not private.can_scan() then raise exception 'Accès refusé' using errcode='42501'; end if;
  return query
  select s.id,s.mat,s.name,s.photo,s.cid,
         coalesce(s.blocked,false),coalesce(s.access_blocked,false),
         s.may_leave_alone,s.leave_alone_until,
         s.pid,u.name,
         case when v_role in ('direction','gardien') then u.phone else null end
  from public.students s
  left join public.users u on u.id=s.pid and u.status='active'
  where not coalesce(s.archived,false);
end;
$$;

create or replace function public.get_scanner_aps()
returns table(
  id text, sid text, name text, relation text, photo text, phone text,
  valid_until date, approval_status text, active boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_role text := private.current_app_role();
begin
  if not private.can_scan() then raise exception 'Accès refusé' using errcode='42501'; end if;
  return query
  select a.id,a.sid,a.name,a.relation,a.photo,
         case when v_role in ('direction','gardien') then a.phone else null end,
         a.valid_until,a.approval_status,a.active
  from public.aps a
  where a.approval_status='approved'
    and a.active
    and (a.valid_until is null or a.valid_until>=timezone('Africa/Kinshasa',now())::date);
end;
$$;

revoke all on function public.get_scanner_students() from public;
revoke all on function public.get_scanner_students() from anon;
revoke all on function public.get_scanner_aps() from public;
revoke all on function public.get_scanner_aps() from anon;
grant execute on function public.get_scanner_students() to authenticated;
grant execute on function public.get_scanner_students() to service_role;
grant execute on function public.get_scanner_aps() to authenticated;
grant execute on function public.get_scanner_aps() to service_role;

comment on function public.get_scanner_students() is
  'Scanner roster: guardian phone is returned only to Direction 1 and Gardien.';
comment on function public.get_scanner_aps() is
  'Accredited pickup roster: phone is returned only to Direction 1 and Gardien.';
