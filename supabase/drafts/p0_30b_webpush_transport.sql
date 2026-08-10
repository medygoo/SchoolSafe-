-- P0-30b WEB PUSH — DRAFT ONLY
-- This file is intentionally NOT under supabase/migrations/.
-- It ends with ROLLBACK so an accidental execution should persist nothing.
-- Review with Claude, then convert to a real migration only after Loms validation.

begin;

-- The real table already supports provider='webpush' with endpoint/auth/p256dh.
-- Add an address uniqueness rule so one browser subscription cannot remain
-- attached to two SchoolSafe users at the same time.
create unique index if not exists uq_push_subscriptions_webpush_endpoint
  on public.push_subscriptions(endpoint)
  where provider='webpush' and endpoint is not null;

-- Public configuration only. The VAPID PRIVATE key must never be stored here.
create or replace function public.get_webpush_public_config()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_uid text := private.current_app_user_id();
  v_key text;
begin
  if v_uid is null then
    return jsonb_build_object('ok',false,'code','AUTH_REQUIRED');
  end if;

  select nullif(btrim(vapid_public_key),'')
    into v_key
  from public.settings
  order by id
  limit 1;

  return jsonb_build_object(
    'ok',true,
    'enabled',v_key is not null,
    'vapid_public_key',v_key
  );
end;
$$;

create or replace function public.register_webpush_device(
  p_endpoint text,
  p_p256dh text,
  p_auth text,
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
  v_uid text := private.current_app_user_id();
  v_endpoint text := nullif(btrim(coalesce(p_endpoint,'')),'');
  v_p256dh text := nullif(btrim(coalesce(p_p256dh,'')),'');
  v_auth text := nullif(btrim(coalesce(p_auth,'')),'');
  v_platform text := lower(btrim(coalesce(p_platform,'web')));
  v_instance text := nullif(btrim(coalesce(p_app_instance_id,'')),'');
  v_saved public.push_subscriptions%rowtype;
  v_backfilled integer := 0;
begin
  if v_uid is null then
    return jsonb_build_object('ok',false,'code','AUTH_REQUIRED');
  end if;

  if v_endpoint is null
     or length(v_endpoint) > 4096
     or v_endpoint !~ '^https://'
  then
    return jsonb_build_object('ok',false,'code','INVALID_WEBPUSH_ENDPOINT');
  end if;

  if v_p256dh is null or length(v_p256dh) not between 40 and 256
     or v_auth is null or length(v_auth) not between 8 and 256
  then
    return jsonb_build_object('ok',false,'code','INVALID_WEBPUSH_KEY');
  end if;

  if v_platform not in ('web','android','ios','unknown') then
    return jsonb_build_object('ok',false,'code','INVALID_PLATFORM');
  end if;

  if length(coalesce(v_instance,'')) > 200
     or length(coalesce(p_device_label,'')) > 200
     or length(coalesce(p_user_agent,'')) > 1000
  then
    return jsonb_build_object('ok',false,'code','VALIDATION_ERROR');
  end if;

  -- Same installed app/browser instance with a rotated endpoint:
  -- disable the old subscription before attaching the new one.
  update public.push_subscriptions
     set active=false,
         disabled_at=now(),
         disabled_reason='ENDPOINT_REPLACED',
         updated_at=now()
   where uid=v_uid
     and provider='webpush'
     and v_instance is not null
     and app_instance_id=v_instance
     and endpoint is distinct from v_endpoint
     and active;

  insert into public.push_subscriptions(
    id,uid,provider,token,endpoint,auth,p256dh,platform,
    app_instance_id,device_label,ua,active,
    created_at,last_seen_at,updated_at,failure_count
  )
  values(
    'push_'||replace(gen_random_uuid()::text,'-',''),
    v_uid,'webpush',null,v_endpoint,v_auth,v_p256dh,v_platform,
    v_instance,
    nullif(left(btrim(coalesce(p_device_label,'')),200),''),
    nullif(left(btrim(coalesce(p_user_agent,'')),1000),''),
    true,now(),now(),now(),0
  )
  on conflict(endpoint) where provider='webpush' and endpoint is not null
  do update set
    uid=excluded.uid,
    auth=excluded.auth,
    p256dh=excluded.p256dh,
    platform=excluded.platform,
    app_instance_id=excluded.app_instance_id,
    device_label=excluded.device_label,
    ua=excluded.ua,
    token=null,
    active=true,
    last_seen_at=now(),
    updated_at=now(),
    disabled_at=null,
    disabled_reason=null,
    failure_count=0
  returning * into v_saved;

  -- Backfill relevant unread notifications so enabling a device does not lose
  -- recent urgent/ack-required notifications already created in SchoolSafe.
  insert into private.notification_push_outbox(
    notification_id,recipient_user_id,device_id,provider,payload
  )
  select
    n.id,n.uid,v_saved.id,'webpush',
    jsonb_build_object(
      'title',case when n.privacy_level='sensitive' then
        case n.category
          when 'emergency' then 'SchoolSafe — Urgence'
          when 'security' then 'SchoolSafe — Sécurité'
          when 'convocation' then 'SchoolSafe — Convocation'
          when 'payment' then 'SchoolSafe — Information administrative'
          when 'receipt_available' then 'SchoolSafe — Document administratif'
          when 'result_available' then 'SchoolSafe — Résultat disponible'
          when 'exit_prepared' then 'SchoolSafe — Sortie'
          when 'exit_confirmed' then 'SchoolSafe — Sortie confirmée'
          else 'SchoolSafe — Information importante'
        end
        else coalesce(n.title,'SchoolSafe')
      end,
      'body',case when n.privacy_level='sensitive'
        then 'Une information concernant votre enfant est disponible. Ouvrez SchoolSafe.'
        else left(coalesce(n.msg,''),240)
      end,
      -- Keep both names during the FCM -> Web Push transition.
      'action_url',coalesce(nullif(n.action_url,''),'./?page=notifications&notification='||n.id),
      'url',coalesce(nullif(n.action_url,''),'./?page=notifications&notification='||n.id),
      'tag','schoolsafe-'||n.id,
      'urgent',(n.priority='urgent'),
      'data',jsonb_build_object(
        'notification_id',n.id,
        'category',n.category,
        'student_id',coalesce(n.student_id,''),
        'action_url',coalesce(nullif(n.action_url,''),'./?page=notifications&notification='||n.id)
      )
    )
  from public.notifs n
  where n.uid=v_uid
    and n.archived_at is null
    and not n.read
    and n.push_requested
    and (
      n.created_at >= now()-interval '24 hours'
      or (n.requires_ack and n.acknowledged_at is null and n.created_at >= now()-interval '30 days')
    )
  on conflict(notification_id,device_id) do nothing;

  get diagnostics v_backfilled=row_count;

  return jsonb_build_object(
    'ok',true,
    'code','WEBPUSH_DEVICE_REGISTERED',
    'device_id',v_saved.id,
    'provider','webpush',
    'platform',v_saved.platform,
    'queued_notifications',v_backfilled
  );
end;
$$;

-- Queue both currently-supported providers. This does not expose any address to
-- normal users; the rows live in the private outbox.
create or replace function private.queue_push_for_notification()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  d public.push_subscriptions%rowtype;
  v_title text;
  v_body text;
  v_link text;
begin
  if not new.push_requested or new.uid is null then return new; end if;

  if new.privacy_level='sensitive' then
    v_title:=case new.category
      when 'emergency' then 'SchoolSafe — Urgence'
      when 'security' then 'SchoolSafe — Sécurité'
      when 'convocation' then 'SchoolSafe — Convocation'
      when 'payment' then 'SchoolSafe — Information administrative'
      when 'receipt_available' then 'SchoolSafe — Document administratif'
      when 'result_available' then 'SchoolSafe — Résultat disponible'
      when 'exit_prepared' then 'SchoolSafe — Sortie'
      when 'exit_confirmed' then 'SchoolSafe — Sortie confirmée'
      else 'SchoolSafe — Information importante'
    end;
    v_body:='Une information concernant votre enfant est disponible. Ouvrez SchoolSafe.';
  else
    v_title:=coalesce(new.title,'SchoolSafe');
    v_body:=left(coalesce(new.msg,''),240);
  end if;

  v_link:=coalesce(nullif(new.action_url,''),'./?page=notifications&notification='||new.id);

  for d in
    select *
    from public.push_subscriptions
    where uid=new.uid
      and active
      and (
        (provider='fcm' and token is not null)
        or
        (provider='webpush' and endpoint is not null and auth is not null and p256dh is not null)
      )
  loop
    insert into private.notification_push_outbox(
      notification_id,recipient_user_id,device_id,provider,payload
    ) values (
      new.id,new.uid,d.id,d.provider,
      jsonb_build_object(
        'title',v_title,
        'body',v_body,
        -- FCM compatibility fields are preserved; Web Push reads url/tag/urgent.
        'action_url',v_link,
        'url',v_link,
        'tag','schoolsafe-'||new.id,
        'urgent',(new.priority='urgent'),
        'data',jsonb_build_object(
          'notification_id',new.id,
          'category',new.category,
          'student_id',coalesce(new.student_id,''),
          'action_url',v_link
        )
      )
    ) on conflict(notification_id,device_id) do nothing;
  end loop;

  return new;
end;
$$;

-- Preserve the existing FCM claim signature but prevent it from accidentally
-- claiming Web Push rows once Web Push devices exist.
create or replace function public.claim_notification_push_batch(p_limit integer default 100)
returns table(
  outbox_id text,
  notification_id text,
  device_id text,
  provider text,
  token text,
  payload jsonb,
  attempt_no integer
)
language plpgsql
security definer
set search_path=''
as $$
declare
  v_limit integer:=greatest(1,least(coalesce(p_limit,100),500));
begin
  if auth.role()<>'service_role' and current_user<>'postgres' then
    raise exception 'Accès refusé' using errcode='42501';
  end if;

  update private.notification_push_outbox
     set status='queued',lease_until=null,next_attempt_at=now(),updated_at=now(),
         last_error=coalesce(last_error,'LEASE_EXPIRED')
   where provider='fcm' and status='sending' and lease_until<now();

  return query
  with picked as (
    select o.id
    from private.notification_push_outbox o
    join public.push_subscriptions d on d.id=o.device_id and d.active
    where o.provider='fcm'
      and d.provider='fcm'
      and d.token is not null
      and o.status in ('queued','failed')
      and o.next_attempt_at<=now()
    order by
      case when (select n.priority from public.notifs n where n.id=o.notification_id)='urgent' then 0 else 1 end,
      o.created_at
    for update of o skip locked
    limit v_limit
  ), claimed as (
    update private.notification_push_outbox o
       set status='sending',attempts=o.attempts+1,
           lease_until=now()+interval '2 minutes',updated_at=now()
      from picked p
     where o.id=p.id
    returning o.*
  )
  select c.id,c.notification_id,c.device_id,c.provider,d.token,c.payload,c.attempts
  from claimed c
  join public.push_subscriptions d on d.id=c.device_id and d.active;
end;
$$;

-- Separate service-only claim for the VPS Web Push worker.
create or replace function public.claim_webpush_notification_batch(p_limit integer default 100)
returns table(
  outbox_id text,
  notification_id text,
  device_id text,
  endpoint text,
  p256dh text,
  auth text,
  payload jsonb,
  attempt_no integer
)
language plpgsql
security definer
set search_path=''
as $$
declare
  v_limit integer:=greatest(1,least(coalesce(p_limit,100),500));
begin
  if auth.role()<>'service_role' and current_user<>'postgres' then
    raise exception 'Accès refusé' using errcode='42501';
  end if;

  update private.notification_push_outbox
     set status='queued',lease_until=null,next_attempt_at=now(),updated_at=now(),
         last_error=coalesce(last_error,'LEASE_EXPIRED')
   where provider='webpush' and status='sending' and lease_until<now();

  return query
  with picked as (
    select o.id
    from private.notification_push_outbox o
    join public.push_subscriptions d on d.id=o.device_id and d.active
    where o.provider='webpush'
      and d.provider='webpush'
      and d.endpoint is not null
      and d.auth is not null
      and d.p256dh is not null
      and o.status in ('queued','failed')
      and o.next_attempt_at<=now()
    order by
      case when (select n.priority from public.notifs n where n.id=o.notification_id)='urgent' then 0 else 1 end,
      o.created_at
    for update of o skip locked
    limit v_limit
  ), claimed as (
    update private.notification_push_outbox o
       set status='sending',attempts=o.attempts+1,
           lease_until=now()+interval '2 minutes',updated_at=now()
      from picked p
     where o.id=p.id
    returning o.*
  )
  select c.id,c.notification_id,c.device_id,d.endpoint,d.p256dh,d.auth,c.payload,c.attempts
  from claimed c
  join public.push_subscriptions d on d.id=c.device_id and d.active;
end;
$$;

revoke all on function public.get_webpush_public_config() from public,anon;
revoke all on function public.register_webpush_device(text,text,text,text,text,text,text) from public,anon;
revoke all on function public.claim_webpush_notification_batch(integer) from public,anon,authenticated;

grant execute on function public.get_webpush_public_config() to authenticated;
grant execute on function public.register_webpush_device(text,text,text,text,text,text,text) to authenticated;
grant execute on function public.claim_webpush_notification_batch(integer) to service_role;

-- Existing direct-table deny policy remains unchanged.
-- Existing disable_my_push_device() and get_my_push_device_status() remain reused.
-- Existing complete_notification_push_delivery() remains reused for both providers.

rollback;
