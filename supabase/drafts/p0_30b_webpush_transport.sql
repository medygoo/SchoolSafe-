-- P0-30b WEB PUSH — DRAFT ONLY
-- Collaborative v2 after Claude PR #79.
-- NOT a migration. Final ROLLBACK is intentional.

begin;

-- One Web Push endpoint must identify only one device registry row.
create unique index if not exists uq_push_subscriptions_webpush_endpoint
  on public.push_subscriptions(endpoint)
  where provider='webpush' and endpoint is not null;

-- Keep the existing settings RPC and expose only the PUBLIC VAPID key.
create or replace function public.get_safe_settings()
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  s public.settings%rowtype;
  r text := private.current_app_role();
begin
  if r is null then
    raise exception 'Session inactive' using errcode = '42501';
  end if;

  select * into s from public.settings order by id limit 1;
  if not found then
    return '{}'::jsonb;
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'id', s.id,
    'year', s.year,
    'school', s.school,
    'toggles', s.toggles,
    'horaires', s.horaires,
    'lockdown', s.lockdown,
    'retention', s.retention,
    'trimlocks', s.trimlocks,
    'currenttrimestre', s.currenttrimestre,
    'school_type', s.school_type,
    'session_timeout_min', s.session_timeout_min,
    'rattrapage_rate', s.rattrapage_rate,
    'rattrapage_threshold', s.rattrapage_threshold,
    'vapid_public_key', s.vapid_public_key,
    'fees', case when r in ('direction', 'direction3', 'parent') then s.fees else null end,
    'feescontrol', case when r in ('direction', 'direction3', 'parent') then s.feescontrol else null end
  ));
end;
$function$;

-- Preserve the frontend signature already used by Claude #79.
-- FCM p_token remains the raw FCM token.
-- Web Push p_token is JSON: {"endpoint":"...","p256dh":"...","auth":"..."}.
create or replace function public.register_push_device(
  p_provider text,
  p_token text,
  p_platform text default 'web'::text,
  p_app_instance_id text default null::text,
  p_device_label text default null::text,
  p_user_agent text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid text := private.current_app_user_id();
  v_provider text := lower(btrim(coalesce(p_provider,'fcm')));
  v_token text := nullif(btrim(coalesce(p_token,'')),'');
  v_platform text := lower(btrim(coalesce(p_platform,'unknown')));
  v_instance text := nullif(btrim(coalesce(p_app_instance_id,'')),'');
  v_saved public.push_subscriptions%rowtype;
  v_backfilled integer := 0;

  v_webpush jsonb;
  v_endpoint text;
  v_p256dh text;
  v_auth text;

  v_existing_device_id text;
  v_existing_uid text;
  v_rotated_ids text[] := array[]::text[];
begin
  if v_uid is null then
    return jsonb_build_object('ok',false,'code','AUTH_REQUIRED');
  end if;

  if v_provider not in ('fcm','webpush') then
    return jsonb_build_object('ok',false,'code','UNSUPPORTED_PROVIDER');
  end if;

  if v_platform not in ('web','android','ios','unknown') then
    return jsonb_build_object('ok',false,'code','INVALID_PLATFORM');
  end if;

  if length(coalesce(v_instance,''))>200
     or length(coalesce(p_device_label,''))>200
     or length(coalesce(p_user_agent,''))>1000
  then
    return jsonb_build_object('ok',false,'code','VALIDATION_ERROR');
  end if;

  if v_provider='fcm' then
    if v_token is null or length(v_token) not between 20 and 4096 then
      return jsonb_build_object('ok',false,'code','INVALID_PUSH_TOKEN');
    end if;

    -- If the same FCM token is moving to another SchoolSafe account, pending
    -- messages for the previous account must never follow it.
    select d.id,d.uid
      into v_existing_device_id,v_existing_uid
    from public.push_subscriptions d
    where d.provider='fcm' and d.token=v_token
    for update;

    if v_existing_device_id is not null and v_existing_uid is distinct from v_uid then
      update private.notification_push_outbox
         set status='dead',
             last_error='DEVICE_OWNER_CHANGED',
             lease_until=null,
             updated_at=now()
       where device_id=v_existing_device_id
         and recipient_user_id is distinct from v_uid
         and status in ('queued','failed','sending');
    end if;

    -- A stable app_instance_id lets the same installation rotate its token.
    if v_instance is not null then
      select coalesce(array_agg(d.id),'{}'::text[])
        into v_rotated_ids
      from public.push_subscriptions d
      where d.uid=v_uid
        and d.provider='fcm'
        and d.app_instance_id=v_instance
        and d.token is distinct from v_token
        and d.active;

      if cardinality(v_rotated_ids)>0 then
        update public.push_subscriptions
           set active=false,
               disabled_at=now(),
               disabled_reason='TOKEN_REPLACED',
               updated_at=now()
         where id=any(v_rotated_ids);

        update private.notification_push_outbox
           set status='dead',
               last_error='DEVICE_ADDRESS_REPLACED',
               lease_until=null,
               updated_at=now()
         where device_id=any(v_rotated_ids)
           and status in ('queued','failed','sending');
      end if;
    end if;

    insert into public.push_subscriptions(
      id,uid,provider,token,endpoint,auth,p256dh,platform,app_instance_id,
      device_label,ua,active,created_at,last_seen_at,updated_at,failure_count
    ) values (
      'push_'||replace(gen_random_uuid()::text,'-',''),v_uid,'fcm',v_token,
      null,null,null,v_platform,v_instance,
      nullif(left(btrim(coalesce(p_device_label,'')),200),''),
      nullif(left(btrim(coalesce(p_user_agent,'')),1000),''),
      true,now(),now(),now(),0
    )
    on conflict(provider,token) where token is not null do update set
      uid=excluded.uid,
      platform=excluded.platform,
      app_instance_id=excluded.app_instance_id,
      device_label=excluded.device_label,
      ua=excluded.ua,
      endpoint=null,
      auth=null,
      p256dh=null,
      active=true,
      last_seen_at=now(),
      updated_at=now(),
      disabled_at=null,
      disabled_reason=null,
      failure_count=0
    returning * into v_saved;

  else
    -- Web Push: p_token is a compact transport envelope chosen by Claude #79.
    if v_token is null or length(v_token) not between 20 and 4096 then
      return jsonb_build_object('ok',false,'code','INVALID_PUSH_TOKEN');
    end if;

    begin
      v_webpush := v_token::jsonb;
    exception when others then
      return jsonb_build_object('ok',false,'code','INVALID_PUSH_TOKEN');
    end;

    if jsonb_typeof(v_webpush)<>'object' then
      return jsonb_build_object('ok',false,'code','INVALID_PUSH_TOKEN');
    end if;

    v_endpoint := nullif(btrim(coalesce(v_webpush->>'endpoint','')),'');
    v_p256dh := nullif(btrim(coalesce(v_webpush->>'p256dh','')),'');
    v_auth := nullif(btrim(coalesce(v_webpush->>'auth','')),'');

    if v_endpoint is null
       or length(v_endpoint)>4096
       or v_endpoint !~ '^https://'
       or v_p256dh is null
       or length(v_p256dh) not between 40 and 256
       or v_auth is null
       or length(v_auth) not between 8 and 256
    then
      return jsonb_build_object('ok',false,'code','INVALID_PUSH_TOKEN');
    end if;

    -- Protect account changes on the same browser subscription.
    select d.id,d.uid
      into v_existing_device_id,v_existing_uid
    from public.push_subscriptions d
    where d.provider='webpush' and d.endpoint=v_endpoint
    for update;

    if v_existing_device_id is not null and v_existing_uid is distinct from v_uid then
      update private.notification_push_outbox
         set status='dead',
             last_error='DEVICE_OWNER_CHANGED',
             lease_until=null,
             updated_at=now()
       where device_id=v_existing_device_id
         and recipient_user_id is distinct from v_uid
         and status in ('queued','failed','sending');
    end if;

    -- With a stable installation ID, endpoint rotation becomes deterministic.
    if v_instance is not null then
      select coalesce(array_agg(d.id),'{}'::text[])
        into v_rotated_ids
      from public.push_subscriptions d
      where d.uid=v_uid
        and d.provider='webpush'
        and d.app_instance_id=v_instance
        and d.endpoint is distinct from v_endpoint
        and d.active;

      if cardinality(v_rotated_ids)>0 then
        update public.push_subscriptions
           set active=false,
               disabled_at=now(),
               disabled_reason='ENDPOINT_REPLACED',
               updated_at=now()
         where id=any(v_rotated_ids);

        update private.notification_push_outbox
           set status='dead',
               last_error='DEVICE_ADDRESS_REPLACED',
               lease_until=null,
               updated_at=now()
         where device_id=any(v_rotated_ids)
           and status in ('queued','failed','sending');
      end if;
    end if;

    insert into public.push_subscriptions(
      id,uid,provider,token,endpoint,auth,p256dh,platform,app_instance_id,
      device_label,ua,active,created_at,last_seen_at,updated_at,failure_count
    ) values (
      'push_'||replace(gen_random_uuid()::text,'-',''),v_uid,'webpush',null,
      v_endpoint,v_auth,v_p256dh,v_platform,v_instance,
      nullif(left(btrim(coalesce(p_device_label,'')),200),''),
      nullif(left(btrim(coalesce(p_user_agent,'')),1000),''),
      true,now(),now(),now(),0
    )
    on conflict(endpoint) where provider='webpush' and endpoint is not null do update set
      uid=excluded.uid,
      token=null,
      auth=excluded.auth,
      p256dh=excluded.p256dh,
      platform=excluded.platform,
      app_instance_id=excluded.app_instance_id,
      device_label=excluded.device_label,
      ua=excluded.ua,
      active=true,
      last_seen_at=now(),
      updated_at=now(),
      disabled_at=null,
      disabled_reason=null,
      failure_count=0
    returning * into v_saved;
  end if;

  -- Backfill recent unread/ack-required notifications for the newly registered
  -- device, without exposing sensitive content on the lock screen.
  insert into private.notification_push_outbox(
    notification_id,recipient_user_id,device_id,provider,payload
  )
  select
    n.id,n.uid,v_saved.id,v_saved.provider,
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
      n.created_at>=now()-interval '24 hours'
      or (n.requires_ack and n.acknowledged_at is null and n.created_at>=now()-interval '30 days')
    )
  on conflict(notification_id,device_id) do nothing;

  get diagnostics v_backfilled=row_count;

  return jsonb_build_object(
    'ok',true,
    'code','PUSH_DEVICE_REGISTERED',
    'device_id',v_saved.id,
    'provider',v_saved.provider,
    'platform',v_saved.platform,
    'queued_notifications',v_backfilled
  );
end;
$function$;

-- Queue both supported providers. The registry remains inaccessible directly
-- to normal clients; only this trusted function reads delivery addresses.
create or replace function private.queue_push_for_notification()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
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
$function$;

-- Historical claim remains FCM-only. The ownership equality is defense in
-- depth against a device that has changed SchoolSafe account.
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
set search_path to ''
as $function$
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
    join public.push_subscriptions d
      on d.id=o.device_id
     and d.active
     and d.uid=o.recipient_user_id
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
  join public.push_subscriptions d
    on d.id=c.device_id
   and d.active
   and d.uid=c.recipient_user_id;
end;
$function$;

-- Web Push addresses are returned only to a service-role worker on the VPS.
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
set search_path to ''
as $function$
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
    join public.push_subscriptions d
      on d.id=o.device_id
     and d.active
     and d.uid=o.recipient_user_id
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
  join public.push_subscriptions d
    on d.id=c.device_id
   and d.active
   and d.uid=c.recipient_user_id;
end;
$function$;

revoke all on function public.claim_webpush_notification_batch(integer) from public,anon,authenticated;
grant execute on function public.claim_webpush_notification_batch(integer) to service_role;

-- Existing grants on get_safe_settings/register_push_device are preserved by
-- CREATE OR REPLACE. Direct-table deny policy remains unchanged.
-- disable_my_push_device(), get_my_push_device_status() and
-- complete_notification_push_delivery() remain unchanged and provider-neutral.

rollback;
