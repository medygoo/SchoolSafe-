update public.students set archived = false where archived is null;
update public.students set access_parent = true where access_parent is null;

alter table public.students
  alter column archived set default false,
  alter column archived set not null,
  alter column access_parent set default true,
  alter column access_parent set not null;
