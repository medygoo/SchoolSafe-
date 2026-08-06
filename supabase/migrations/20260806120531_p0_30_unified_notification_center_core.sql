-- P0-30: unified in-app notification center and secure device registration.

alter table public.notifs
  add column if not exists category text,
  add column if not exists title text,
  add column if not exists student_id text,
  add column if not exists action_url text,
  add column if not exists priority text,
  add column if not exists privacy_level text,
  add column if not exists requires_ack boolean,
  add column if not exists created_at timestamptz,
  add column if not exists created_by_user_id text,
  add column if not exists created_by_name text,
  add column if not exists created_by_role text,
  add column if not exists opened_at timestamptz,
  add column if not exists read_at timestamptz,
  add column if not exists acknowledged_at timestamptz,
  add column if not exists archived_at timestamptz,
  add column if not exists source_type text,
  add column if not exists source_id text,
  add column if not exists dedupe_key text,
  add column if not exists data jsonb,
  add column if not exists push_requested boolean;

update public.notifs
set category=coalesce(nullif(category,''),'information'),
    title=coalesce(nullif(title,''),nullif("from",''),'SchoolSafe'),
    priority=coalesce(nullif(priority,''),'normal'),
    privacy_level=coalesce(nullif(privacy_level,''),'normal'),
    requires_ack=coalesce(requires_ack,false),
    created_at=coalesce(created_at,
      case when nullif(date,'') is not null then
        (date||' '||coalesce(nullif(time,''),'00:00'))::timestamp at time zone 'Africa/Kinshasa'
      else now() end),
    data=coalesce(data,'{}'::jsonb),
    push_requested=coalesce(push_requested,true),
    read=coalesce(read,false),
    read_at=case when coalesce(read,false) then coalesce(read_at,created_at,now()) else read_at end;

alter table public.notifs
  alter column category set default 'information',
  alter column category set not null,
  alter column priority set default 'normal',
  alter column priority set not null,
  alter column privacy_level set default 'normal',
  alter column privacy_level set not null,
  alter column requires_ack set default false,
  alter column requires_ack set not null,
  alter column created_at set default now(),
  alter column created_at set not null,
  alter column data set default '{}'::jsonb,
  alter column data set not null,
  alter column push_requested set default true,
  alter column push_requested set not null,
  alter column read set default false,
  alter column read set not null;

alter table public.notifs drop constraint if exists notifs_category_check;
alter table public.notifs add constraint notifs_category_check check (category in (
  'information','emergency','convocation','exit_prepared','exit_confirmed','exit_cancelled','exit_refused','exit_expired',
  'absence','lateness','homework','assessment','result_available','teacher_message','direction_message','announcement',
  'administrative_reminder','payment','receipt_available','schedule_change','document_available','security'
));
alter table public.notifs drop constraint if exists notifs_priority_check;
alter table public.notifs add constraint notifs_priority_check check (priority in ('low','normal','high','urgent'));
alter table public.notifs drop constraint if exists notifs_privacy_level_check;
alter table public.notifs add constraint notifs_privacy_level_check check (privacy_level in ('normal','sensitive'));
alter table public.notifs drop constraint if exists notifs_text_limits_check;
alter table public.notifs add constraint notifs_text_limits_check check (
  length(coalesce(title,''))<=200 and length(coalesce(msg,''))<=4000 and
  length(coalesce(action_url,''))<=1000 and length(coalesce(source_type,''))<=100 and
  length(coalesce(source_id,''))<=200 and length(coalesce(dedupe_key,''))<=300
);

do $$
begin
  if not exists(select 1 from pg_constraint where conrelid='public.notifs'::regclass and conname='notifs_uid_fkey') then
    alter table public.notifs add constraint notifs_uid_fkey foreign key(uid) references public.users(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conrelid='public.notifs'::regclass and conname='notifs_student_id_fkey') then
    alter table public.notifs add constraint notifs_student_id_fkey foreign key(student_id) references public.students(id) on delete restrict;
  end if;
  if not exists(select 1 from pg_constraint where conrelid='public.notifs'::regclass and conname='notifs_created_by_user_id_fkey') then
    alter table public.notifs add constraint notifs_created_by_user_id_fkey foreign key(created_by_user_id) references public.users(id) on delete restrict;
  end if;
end $$;

create index if not exists idx_notifs_recipient_created on public.notifs(uid,created_at desc);
create index if not exists idx_notifs_recipient_unread on public.notifs(uid,read,created_at desc) where archived_at is null;
create index if not exists idx_notifs_student_created on public.notifs(student_id,created_at desc) where student_id is not null;
create unique index if not exists uq_notifs_recipient_dedupe on public.notifs(uid,dedupe_key) where dedupe_key is not null;

create or replace function private.stamp_notification_record()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_actor_id text;
  v_actor_name text;
  v_actor_role text;
begin
  new.id:=coalesce(nullif(btrim(coalesce(new.id,'')),''),'notif_'||replace(gen_random_uuid()::text,'-',''));
  new.created_at:=coalesce(new.created_at,now());
  new.date:=coalesce(nullif(new.date,''),to_char(timezone('Africa/Kinshasa',new.created_at),'YYYY-MM-DD'));
  new.time:=coalesce(nullif(new.time,''),to_char(timezone('Africa/Kinshasa',new.created_at),'HH24:MI'));
  new.category:=coalesce(nullif(lower(btrim(coalesce(new.category,''))),''),'information');
  new.title:=left(coalesce(nullif(btrim(coalesce(new.title,'')),''),nullif(btrim(coalesce(new."from",'')),''),'SchoolSafe'),200);
  new.priority:=coalesce(nullif(lower(btrim(coalesce(new.priority,''))),''),
    case when new.category in ('emergency','security') then 'urgent'
         when new.category in ('convocation','exit_refused','exit_expired') then 'high'
         else 'normal' end);
  new.privacy_level:=coalesce(nullif(lower(btrim(coalesce(new.privacy_level,''))),''),
    case when new.category in ('emergency','security','convocation','payment','receipt_available','result_available','exit_prepared','exit_confirmed','exit_refused')
         then 'sensitive' else 'normal' end);
  if new.category in ('emergency','convocation','security') then new.requires_ack:=true;
  else new.requires_ack:=coalesce(new.requires_ack,false); end if;
  new.data:=coalesce(new.data,'{}'::jsonb);
  new.push_requested:=coalesce(new.push_requested,true);
  new.read:=coalesce(new.read,false);

  v_actor_id:=private.current_app_user_id();
  if v_actor_id is null then v_actor_id:=coalesce(new.created_by_user_id,new.by); end if;
  if v_actor_id is not null then
    select u.name,
      case u.role when 'direction_pedagogique' then 'direction2' when 'caisse' then 'direction3' else u.role end
    into v_actor_name,v_actor_role from public.users u where u.id=v_actor_id limit 1;
  end if;
  new.created_by_user_id:=coalesce(new.created_by_user_id,v_actor_id);
  new.created_by_name:=coalesce(nullif(new.created_by_name,''),v_actor_name);
  new.created_by_role:=coalesce(nullif(new.created_by_role,''),v_actor_role);
  new.by:=coalesce(new.by,new.created_by_user_id);
  if new.read then new.read_at:=coalesce(new.read_at,new.created_at); end if;
  return new;
end;
$$;

drop trigger if exists notifs_stamp_metadata on public.notifs;
create trigger notifs_stamp_metadata before insert on public.notifs
for each row execute function private.stamp_notification_record();

create or replace function private.protect_notification_update()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_actor_id text:=private.current_app_user_id();
  v_allowed text[]:=array['read','opened_at','read_at','acknowledged_at','archived_at'];
begin
  if current_user='postgres' or auth.role()='service_role' then return new; end if;
  if v_actor_id is null then raise exception 'Accès refusé' using errcode='42501'; end if;
  if old.uid<>v_actor_id and not private.is_direction() then raise exception 'Accès refusé' using errcode='42501'; end if;
  if (to_jsonb(new)-v_allowed) is distinct from (to_jsonb(old)-v_allowed) then
    raise exception 'Les données de la notification sont immuables' using errcode='42501';
  end if;
  if coalesce(old.read,false) and not coalesce(new.read,false) then
    raise exception 'Une notification lue ne peut pas redevenir non lue' using errcode='23514';
  end if;
  if new.opened_at is not null and old.opened_at is null then new.opened_at:=now(); end if;
  if coalesce(new.read,false) and not coalesce(old.read,false) then new.read_at:=now(); end if;
  if new.acknowledged_at is not null and old.acknowledged_at is null then
    if not old.requires_ack then raise exception 'Accusé non requis' using errcode='23514'; end if;
    new.acknowledged_at:=now(); new.read:=true; new.read_at:=coalesce(new.read_at,now());
  end if;
  if new.archived_at is not null and old.archived_at is null then new.archived_at:=now(); end if;
  return new;
end;
$$;

drop trigger if exists notifs_protect_update on public.notifs;
create trigger notifs_protect_update before update on public.notifs
for each row execute function private.protect_notification_update();

-- Keep compatible direct inserts for old screens, but stamp the true actor server-side.
drop policy if exists notifs_read on public.notifs;
create policy notifs_read on public.notifs for select to authenticated using (
  uid=private.current_app_user_id() or private.is_direction() or created_by_user_id=private.current_app_user_id()
);
drop policy if exists notifs_insert on public.notifs;
create policy notifs_insert on public.notifs for insert to authenticated with check (private.can_notify(uid));
drop policy if exists notifs_update on public.notifs;
create policy notifs_update on public.notifs for update to authenticated using (
  uid=private.current_app_user_id() or private.is_direction()
) with check (
  uid=private.current_app_user_id() or private.is_direction()
);
drop policy if exists notifs_delete on public.notifs;
revoke delete,truncate,references,trigger on public.notifs from authenticated;
grant select,insert,update on public.notifs to authenticated;

-- Upgrade the empty legacy Web Push table into a provider-neutral device registry.
delete from public.push_subscriptions where uid is null;
alter table public.push_subscriptions
  add column if not exists provider text,
  add column if not exists token text,
  add column if not exists platform text,
  add column if not exists app_instance_id text,
  add column if not exists device_label text,
  add column if not exists active boolean,
  add column if not exists created_at timestamptz,
  add column if not exists last_seen_at timestamptz,
  add column if not exists last_success_at timestamptz,
  add column if not exists disabled_at timestamptz,
  add column if not exists disabled_reason text,
  add column if not exists failure_count integer;

alter table public.push_subscriptions alter column updated_at type timestamptz
  using case when nullif(updated_at,'') is null then now() else updated_at::timestamptz end;
update public.push_subscriptions set
  provider=coalesce(provider,'fcm'), platform=coalesce(platform,'unknown'),
  active=coalesce(active,true), created_at=coalesce(created_at,now()),
  last_seen_at=coalesce(last_seen_at,now()), failure_count=coalesce(failure_count,0),
  updated_at=coalesce(updated_at,now());
alter table public.push_subscriptions
  alter column id set default ('push_'||replace(gen_random_uuid()::text,'-','')),
  alter column uid set not null,
  alter column provider set default 'fcm',
  alter column provider set not null,
  alter column platform set default 'unknown',
  alter column platform set not null,
  alter column active set default true,
  alter column active set not null,
  alter column created_at set default now(),
  alter column created_at set not null,
  alter column last_seen_at set default now(),
  alter column last_seen_at set not null,
  alter column failure_count set default 0,
  alter column failure_count set not null,
  alter column updated_at set default now(),
  alter column updated_at set not null;

do $$ begin
  if not exists(select 1 from pg_constraint where conrelid='public.push_subscriptions'::regclass and conname='push_subscriptions_uid_fkey') then
    alter table public.push_subscriptions add constraint push_subscriptions_uid_fkey foreign key(uid) references public.users(id) on delete restrict;
  end if;
end $$;
alter table public.push_subscriptions drop constraint if exists push_subscriptions_provider_check;
alter table public.push_subscriptions add constraint push_subscriptions_provider_check check (provider in ('fcm','webpush'));
alter table public.push_subscriptions drop constraint if exists push_subscriptions_platform_check;
alter table public.push_subscriptions add constraint push_subscriptions_platform_check check (platform in ('web','android','ios','unknown'));
alter table public.push_subscriptions drop constraint if exists push_subscriptions_address_check;
alter table public.push_subscriptions add constraint push_subscriptions_address_check check (
  (provider='fcm' and token is not null and length(token) between 20 and 4096)
  or (provider='webpush' and endpoint is not null and auth is not null and p256dh is not null)
);
create unique index if not exists uq_push_subscriptions_provider_token on public.push_subscriptions(provider,token) where token is not null;
create index if not exists idx_push_subscriptions_user_active on public.push_subscriptions(uid,active,last_seen_at desc);

drop policy if exists push_subscriptions_direction_all on public.push_subscriptions;
drop policy if exists push_subscriptions_read on public.push_subscriptions;
create policy push_subscriptions_read on public.push_subscriptions for select to authenticated using (
  uid=private.current_app_user_id() or private.is_direction()
);
revoke insert,update,delete,truncate,references,trigger on public.push_subscriptions from authenticated;
grant select on public.push_subscriptions to authenticated;

create or replace function public.register_push_device(
  p_provider text,
  p_token text,
  p_platform text default 'web',
  p_app_instance_id text default null,
  p_device_label text default null,
  p_user_agent text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid text:=private.current_app_user_id();
  v_provider text:=lower(btrim(coalesce(p_provider,'fcm')));
  v_token text:=nullif(btrim(coalesce(p_token,'')),'');
  v_platform text:=lower(btrim(coalesce(p_platform,'unknown')));
  v_instance text:=nullif(btrim(coalesce(p_app_instance_id,'')),'');
  v_saved public.push_subscriptions%rowtype;
begin
  if v_uid is null then return jsonb_build_object('ok',false,'code','AUTH_REQUIRED'); end if;
  if v_provider<>'fcm' then return jsonb_build_object('ok',false,'code','UNSUPPORTED_PROVIDER'); end if;
  if v_token is null or length(v_token) not between 20 and 4096 then return jsonb_build_object('ok',false,'code','INVALID_PUSH_TOKEN'); end if;
  if v_platform not in ('web','android','ios','unknown') then return jsonb_build_object('ok',false,'code','INVALID_PLATFORM'); end if;
  if length(coalesce(v_instance,''))>200 or length(coalesce(p_device_label,''))>200 or length(coalesce(p_user_agent,''))>1000 then
    return jsonb_build_object('ok',false,'code','VALIDATION_ERROR');
  end if;
  update public.push_subscriptions set active=false,disabled_at=now(),disabled_reason='TOKEN_REPLACED',updated_at=now()
   where uid=v_uid and provider=v_provider and v_instance is not null and app_instance_id=v_instance and token is distinct from v_token and active;
  insert into public.push_subscriptions(id,uid,provider,token,platform,app_instance_id,device_label,ua,active,created_at,last_seen_at,updated_at,failure_count)
  values('push_'||replace(gen_random_uuid()::text,'-',''),v_uid,v_provider,v_token,v_platform,v_instance,
    nullif(left(btrim(coalesce(p_device_label,'')),200),''),nullif(left(btrim(coalesce(p_user_agent,'')),1000),''),true,now(),now(),now(),0)
  on conflict(provider,token) where token is not null do update set
    uid=excluded.uid,platform=excluded.platform,app_instance_id=excluded.app_instance_id,
    device_label=excluded.device_label,ua=excluded.ua,active=true,last_seen_at=now(),updated_at=now(),
    disabled_at=null,disabled_reason=null,failure_count=0
  returning * into v_saved;
  return jsonb_build_object('ok',true,'code','PUSH_DEVICE_REGISTERED','device_id',v_saved.id,'provider',v_saved.provider,'platform',v_saved.platform);
end;
$$;

create or replace function public.disable_my_push_device(p_device_id text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid text:=private.current_app_user_id(); v_count integer;
begin
  if v_uid is null then return jsonb_build_object('ok',false,'code','AUTH_REQUIRED'); end if;
  update public.push_subscriptions set active=false,disabled_at=now(),disabled_reason='USER_DISABLED',updated_at=now()
  where id=p_device_id and uid=v_uid and active;
  get diagnostics v_count=row_count;
  return jsonb_build_object('ok',v_count=1,'code',case when v_count=1 then 'PUSH_DEVICE_DISABLED' else 'DEVICE_NOT_FOUND' end);
end; $$;

create or replace function private.disable_push_devices_for_inactive_user()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if old.status is distinct from new.status and new.status<>'active' then
    update public.push_subscriptions set active=false,disabled_at=now(),disabled_reason='ACCOUNT_'||upper(new.status),updated_at=now()
    where uid=new.id and active;
  end if;
  return new;
end; $$;
drop trigger if exists users_disable_push_devices on public.users;
create trigger users_disable_push_devices after update of status on public.users
for each row execute function private.disable_push_devices_for_inactive_user();

create or replace function public.mark_my_notification_opened(p_notification_id text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid text:=private.current_app_user_id(); v_count integer;
begin
  update public.notifs set opened_at=coalesce(opened_at,now()) where id=p_notification_id and uid=v_uid and archived_at is null;
  get diagnostics v_count=row_count;
  return jsonb_build_object('ok',v_count=1,'code',case when v_count=1 then 'NOTIFICATION_OPENED' else 'NOTIFICATION_NOT_FOUND' end);
end; $$;
create or replace function public.mark_my_notification_read(p_notification_id text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid text:=private.current_app_user_id(); v_count integer;
begin
  update public.notifs set read=true,opened_at=coalesce(opened_at,now()),read_at=coalesce(read_at,now()) where id=p_notification_id and uid=v_uid and archived_at is null;
  get diagnostics v_count=row_count;
  return jsonb_build_object('ok',v_count=1,'code',case when v_count=1 then 'NOTIFICATION_READ' else 'NOTIFICATION_NOT_FOUND' end);
end; $$;
create or replace function public.acknowledge_my_notification(p_notification_id text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid text:=private.current_app_user_id(); v_count integer;
begin
  update public.notifs set acknowledged_at=coalesce(acknowledged_at,now()),read=true,opened_at=coalesce(opened_at,now()),read_at=coalesce(read_at,now())
  where id=p_notification_id and uid=v_uid and archived_at is null and requires_ack;
  get diagnostics v_count=row_count;
  return jsonb_build_object('ok',v_count=1,'code',case when v_count=1 then 'NOTIFICATION_ACKNOWLEDGED' else 'ACK_NOT_AVAILABLE' end);
end; $$;
create or replace function public.archive_my_notification(p_notification_id text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_uid text:=private.current_app_user_id(); v_count integer;
begin
  update public.notifs set archived_at=coalesce(archived_at,now()) where id=p_notification_id and uid=v_uid;
  get diagnostics v_count=row_count;
  return jsonb_build_object('ok',v_count=1,'code',case when v_count=1 then 'NOTIFICATION_ARCHIVED' else 'NOTIFICATION_NOT_FOUND' end);
end; $$;

create or replace function public.send_school_notification(p_notification jsonb)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_actor_id text:=private.current_app_user_id();
  v_actor_role text:=private.current_app_role();
  v_actor_name text;
  v_category text:=lower(btrim(coalesce(p_notification->>'category','information')));
  v_title text:=nullif(btrim(coalesce(p_notification->>'title','')),'');
  v_message text:=nullif(btrim(coalesce(p_notification->>'message','')),'');
  v_student_id text:=nullif(btrim(coalesce(p_notification->>'student_id','')),'');
  v_class_id text:=nullif(btrim(coalesce(p_notification->>'class_id','')),'');
  v_target_role text:=nullif(lower(btrim(coalesce(p_notification->>'target_role',''))),'');
  v_recipient text;
  v_recipients text[]:=array[]::text[];
  v_more text[];
  v_count integer:=0;
  v_ids jsonb:='[]'::jsonb;
  v_id text;
  v_dedupe text:=nullif(btrim(coalesce(p_notification->>'dedupe_key','')),'');
  v_target public.users%rowtype;
  v_student public.students%rowtype;
  v_priority text:=lower(btrim(coalesce(p_notification->>'priority','normal')));
  v_privacy text:=lower(btrim(coalesce(p_notification->>'privacy_level','normal')));
  v_requires_ack boolean:=coalesce((p_notification->>'requires_ack')::boolean,false);
begin
  if p_notification is null or jsonb_typeof(p_notification)<>'object' then return jsonb_build_object('ok',false,'code','INVALID_PAYLOAD'); end if;
  if v_actor_id is null or v_actor_role not in ('direction','direction2','direction3','enseignant','gardien') then return jsonb_build_object('ok',false,'code','FORBIDDEN'); end if;
  select name into v_actor_name from public.users where id=v_actor_id and status='active';
  if v_title is null or length(v_title)>200 then return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','title'); end if;
  if v_message is null or length(v_message)>4000 then return jsonb_build_object('ok',false,'code','VALIDATION_ERROR','field','message'); end if;
  if v_category not in ('information','emergency','convocation','exit_prepared','exit_confirmed','exit_cancelled','exit_refused','exit_expired','absence','lateness','homework','assessment','result_available','teacher_message','direction_message','announcement','administrative_reminder','payment','receipt_available','schedule_change','document_available','security') then
    return jsonb_build_object('ok',false,'code','INVALID_CATEGORY');
  end if;
  if v_priority not in ('low','normal','high','urgent') or v_privacy not in ('normal','sensitive') then return jsonb_build_object('ok',false,'code','VALIDATION_ERROR'); end if;
  if p_notification ? 'recipient_user_id' then v_recipients:=array_append(v_recipients,nullif(btrim(p_notification->>'recipient_user_id'),'')); end if;
  if p_notification ? 'recipient_user_ids' then
    if jsonb_typeof(p_notification->'recipient_user_ids')<>'array' then return jsonb_build_object('ok',false,'code','INVALID_RECIPIENTS'); end if;
    select coalesce(array_agg(nullif(btrim(value),'')),'{}'::text[]) into v_more from jsonb_array_elements_text(p_notification->'recipient_user_ids');
    v_recipients:=v_recipients||v_more;
  end if;
  if v_student_id is not null then
    select * into v_student from public.students where id=v_student_id and not coalesce(archived,false);
    if not found then return jsonb_build_object('ok',false,'code','STUDENT_NOT_FOUND'); end if;
    if v_student.pid is not null then v_recipients:=array_append(v_recipients,v_student.pid); end if;
  end if;
  if v_class_id is not null then
    select coalesce(array_agg(distinct s.pid),'{}'::text[]) into v_more from public.students s
    where s.cid=v_class_id and not coalesce(s.archived,false) and s.pid is not null;
    v_recipients:=v_recipients||v_more;
  end if;
  if v_target_role is not null then
    if v_actor_role<>'direction' then return jsonb_build_object('ok',false,'code','DIRECTION1_REQUIRED_FOR_ROLE_BROADCAST'); end if;
    select coalesce(array_agg(u.id),'{}'::text[]) into v_more from public.users u where u.status='active' and
      (case u.role when 'direction_pedagogique' then 'direction2' when 'caisse' then 'direction3' else u.role end)=v_target_role;
    v_recipients:=v_recipients||v_more;
  end if;
  v_recipients:=array(select distinct x from unnest(v_recipients) x where x is not null);
  if cardinality(v_recipients)=0 then return jsonb_build_object('ok',false,'code','RECIPIENT_REQUIRED'); end if;
  if cardinality(v_recipients)>500 then return jsonb_build_object('ok',false,'code','TOO_MANY_RECIPIENTS'); end if;

  if v_actor_role='direction2' and v_category in ('payment','receipt_available') then return jsonb_build_object('ok',false,'code','FINANCIAL_NOTIFICATION_FORBIDDEN'); end if;
  if v_actor_role='enseignant' and v_category not in ('information','absence','lateness','homework','assessment','result_available','teacher_message','schedule_change','exit_prepared') then return jsonb_build_object('ok',false,'code','FORBIDDEN_CATEGORY'); end if;
  if v_actor_role='gardien' and v_category not in ('information','emergency','security','exit_confirmed','exit_refused') then return jsonb_build_object('ok',false,'code','FORBIDDEN_CATEGORY'); end if;
  if v_actor_role='direction3' and v_category not in ('information','administrative_reminder','payment','receipt_available') then return jsonb_build_object('ok',false,'code','FORBIDDEN_CATEGORY'); end if;

  foreach v_recipient in array v_recipients loop
    select * into v_target from public.users where id=v_recipient and status='active';
    if not found then continue; end if;
    if v_actor_role='enseignant' and not exists(
      select 1 from public.students s where s.pid=v_target.id and not coalesce(s.archived,false) and private.teaches_class(s.cid)
    ) then return jsonb_build_object('ok',false,'code','RECIPIENT_OUTSIDE_TEACHER_CLASSES','recipient',v_recipient); end if;
    if v_actor_role='gardien' and (v_student_id is null or v_student.pid is distinct from v_target.id) then
      return jsonb_build_object('ok',false,'code','STUDENT_PARENT_REQUIRED');
    end if;
    if v_actor_role='direction3' and (case v_target.role when 'parent' then 'parent' else v_target.role end)<>'parent' then
      return jsonb_build_object('ok',false,'code','PARENT_RECIPIENT_REQUIRED');
    end if;
    v_id:='notif_'||replace(gen_random_uuid()::text,'-','');
    insert into public.notifs(id,uid,"from",msg,type,date,time,read,status,to_role,by,category,title,student_id,action_url,
      priority,privacy_level,requires_ack,created_by_user_id,created_by_name,created_by_role,source_type,source_id,dedupe_key,data,push_requested)
    values(v_id,v_target.id,v_actor_name,v_message,
      case when v_priority in ('high','urgent') then 'warning' else 'info' end,
      to_char(timezone('Africa/Kinshasa',now()),'YYYY-MM-DD'),to_char(timezone('Africa/Kinshasa',now()),'HH24:MI'),false,v_category,v_target.role,v_actor_id,
      v_category,v_title,v_student_id,nullif(btrim(coalesce(p_notification->>'action_url','')),''),v_priority,v_privacy,v_requires_ack,
      v_actor_id,v_actor_name,v_actor_role,nullif(btrim(coalesce(p_notification->>'source_type','')),''),nullif(btrim(coalesce(p_notification->>'source_id','')),''),
      case when v_dedupe is null then null else left(v_dedupe,260) end,coalesce(p_notification->'data','{}'::jsonb),true)
    on conflict(uid,dedupe_key) where dedupe_key is not null do nothing;
    if found then v_count:=v_count+1; v_ids:=v_ids||to_jsonb(v_id); end if;
  end loop;
  return jsonb_build_object('ok',true,'code','NOTIFICATIONS_CREATED','created_count',v_count,'notification_ids',v_ids,'recipient_count',cardinality(v_recipients));
exception when invalid_text_representation then return jsonb_build_object('ok',false,'code','VALIDATION_ERROR');
end;
$$;

create or replace function public.get_my_notification_center(p_limit integer default 50,p_before timestamptz default null,p_category text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_uid text:=private.current_app_user_id(); v_items jsonb; v_limit integer:=greatest(1,least(coalesce(p_limit,50),100));
begin
  if v_uid is null then return jsonb_build_object('ok',false,'code','AUTH_REQUIRED'); end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_items from (
    select n.id,n.category,n.title,n.msg as message,n.type,n.student_id,n.action_url,n.priority,n.privacy_level,n.requires_ack,
      n.created_at,n.opened_at,n.read,n.read_at,n.acknowledged_at,n.created_by_name,n.created_by_role,n.source_type,n.source_id,n.data
    from public.notifs n where n.uid=v_uid and n.archived_at is null
      and (p_before is null or n.created_at<p_before)
      and (nullif(btrim(coalesce(p_category,'')),'') is null or n.category=lower(btrim(p_category)))
    order by n.created_at desc limit v_limit
  ) x;
  return jsonb_build_object('ok',true,'items',v_items,
    'unread_count',(select count(*) from public.notifs where uid=v_uid and archived_at is null and not read),
    'ack_required_count',(select count(*) from public.notifs where uid=v_uid and archived_at is null and requires_ack and acknowledged_at is null));
end; $$;

revoke all on function public.register_push_device(text,text,text,text,text,text) from public,anon;
grant execute on function public.register_push_device(text,text,text,text,text,text) to authenticated,service_role;
revoke all on function public.disable_my_push_device(text) from public,anon;
grant execute on function public.disable_my_push_device(text) to authenticated,service_role;
revoke all on function public.mark_my_notification_opened(text) from public,anon;
grant execute on function public.mark_my_notification_opened(text) to authenticated,service_role;
revoke all on function public.mark_my_notification_read(text) from public,anon;
grant execute on function public.mark_my_notification_read(text) to authenticated,service_role;
revoke all on function public.acknowledge_my_notification(text) from public,anon;
grant execute on function public.acknowledge_my_notification(text) to authenticated,service_role;
revoke all on function public.archive_my_notification(text) from public,anon;
grant execute on function public.archive_my_notification(text) to authenticated,service_role;
revoke all on function public.send_school_notification(jsonb) from public,anon;
grant execute on function public.send_school_notification(jsonb) to authenticated,service_role;
revoke all on function public.get_my_notification_center(integer,timestamptz,text) from public,anon;
grant execute on function public.get_my_notification_center(integer,timestamptz,text) to authenticated,service_role;

comment on function public.send_school_notification(jsonb) is 'Unified server-side notification creation with role, class, student and financial boundaries.';
comment on function public.register_push_device(text,text,text,text,text,text) is 'Registers the current signed-in user device token. The browser never writes push_subscriptions directly.';
comment on table public.notifs is 'Immutable SchoolSafe notification inbox; recipients may read, acknowledge or archive, never delete history.';
