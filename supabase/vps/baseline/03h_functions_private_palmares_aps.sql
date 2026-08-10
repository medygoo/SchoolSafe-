-- SchoolSafe VPS baseline - 03h palmares / accredited-person helpers

BEGIN;

CREATE OR REPLACE FUNCTION private.archive_palmares_revision()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if old.snapshot is distinct from new.snapshot or old.status is distinct from new.status then
    if old.status = 'published'
       and old.snapshot is distinct from new.snapshot
       and length(btrim(coalesce(new.correction_reason, ''))) < 5 then
      raise exception 'Une justification de correction est obligatoire';
    end if;
    insert into public.palmares_publication_history
      (publication_id, cid, year, trimestre, version, snapshot, status, changed_by, change_reason)
    values
      (old.id, old.cid, old.year, old.trimestre, old.version, old.snapshot,
       old.status, new.published_by, new.correction_reason);
    new.version := old.version + 1;
    new.updated_at := now();
  end if;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION private.notify_palmares_publication()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  rec record;
  v_actor_name text;
  v_action text;
  v_changed boolean;
begin
  v_changed := tg_op = 'INSERT'
    or old.status is distinct from new.status
    or old.snapshot is distinct from new.snapshot;
  if not v_changed then return new; end if;

  select name into v_actor_name from public.users where id = new.published_by;
  v_action := case new.status
    when 'draft' then 'a enregistré le brouillon'
    when 'reviewed' then 'a marqué le palmarès comme vérifié'
    when 'published' then
      case when tg_op = 'UPDATE' and old.status = 'published'
        then 'a corrigé et republié le palmarès'
        else 'a publié le palmarès officiel'
      end
    else 'a modifié le palmarès'
  end;

  for rec in
    select id from public.users
    where status = 'active'
      and role in ('direction', 'direction2', 'direction_pedagogique')
      and id is distinct from new.published_by
  loop
    insert into public.notifs(id, uid, "from", msg, type, date, time, read, "by")
    values (
      'notif_' || replace(gen_random_uuid()::text, '-', ''), rec.id,
      'Palmarès', coalesce(v_actor_name, 'La Direction') || ' ' || v_action || ' ' || new.trimestre || '.',
      case when new.status = 'published' then 'success' else 'info' end,
      to_char(timezone('Africa/Kinshasa', now()), 'YYYY-MM-DD'),
      to_char(timezone('Africa/Kinshasa', now()), 'HH24:MI'), false,
      new.published_by
    );
  end loop;

  if new.status = 'published' then
    for rec in
      select distinct u.id
      from public.users u
      join public.students s on s.pid = u.id and s.cid = new.cid
      where u.status = 'active'
        and u.role = 'parent'
        and coalesce(s.access_parent, false)
    loop
      insert into public.notifs(id, uid, "from", msg, type, date, time, read, "by")
      values (
        'notif_' || replace(gen_random_uuid()::text, '-', ''), rec.id,
        'Palmarès officiel',
        'Le résultat officiel ' || new.trimestre || ' de votre enfant est disponible.',
        'success', to_char(timezone('Africa/Kinshasa', now()), 'YYYY-MM-DD'),
        to_char(timezone('Africa/Kinshasa', now()), 'HH24:MI'), false,
        new.published_by
      );
    end loop;
  end if;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION private.notify_aps_decision()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_parent text;
  v_actor_name text;
  rec record;
begin
  if tg_op = 'UPDATE' and old.approval_status is not distinct from new.approval_status then return new; end if;
  if new.approval_status not in ('approved', 'rejected', 'suspended') then return new; end if;
  select pid into v_parent from public.students where id = new.sid;
  select name into v_actor_name from public.users where id = new.approved_by;
  for rec in
    select id from public.users
    where status = 'active'
      and role in ('direction', 'direction2', 'direction_pedagogique')
      and id is distinct from new.approved_by
  loop
    insert into public.notifs(id, uid, "from", msg, type, date, time, read, by)
    values ('notif_' || replace(gen_random_uuid()::text, '-', ''), rec.id,
            'Personnes accréditées',
            coalesce(v_actor_name, 'La Direction') || ' a ' ||
              case new.approval_status when 'approved' then 'approuvé' when 'rejected' then 'refusé' else 'suspendu' end ||
              ' l’accès de ' || new.name || '.',
            'info', to_char(timezone('Africa/Kinshasa', now()), 'YYYY-MM-DD'),
            to_char(timezone('Africa/Kinshasa', now()), 'HH24:MI'), false, new.approved_by);
  end loop;
  if v_parent is not null then
    insert into public.notifs(id, uid, "from", msg, type, date, time, read, by)
    values ('notif_' || replace(gen_random_uuid()::text, '-', ''), v_parent,
            'Personnes accréditées',
            'La demande concernant ' || new.name || ' est maintenant : ' || new.approval_status || '.',
            'info', to_char(timezone('Africa/Kinshasa', now()), 'YYYY-MM-DD'),
            to_char(timezone('Africa/Kinshasa', now()), 'HH24:MI'), false, new.approved_by);
  end if;
  return new;
end
$function$;

COMMIT;
