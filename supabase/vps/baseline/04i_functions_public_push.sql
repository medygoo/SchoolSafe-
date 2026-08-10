-- SchoolSafe VPS baseline - 04i push device/outbox RPCs

BEGIN;

CREATE OR REPLACE FUNCTION public.register_push_device(p_provider text, p_token text, p_platform text DEFAULT 'web'::text, p_app_instance_id text DEFAULT NULL::text, p_device_label text DEFAULT NULL::text, p_user_agent text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid text:=private.current_app_user_id();
  v_provider text:=lower(btrim(coalesce(p_provider,'fcm')));
  v_token text:=nullif(btrim(coalesce(p_token,'')),'');
  v_platform text:=lower(btrim(coalesce(p_platform,'unknown')));
  v_instance text:=nullif(btrim(coalesce(p_app_instance_id,'')),'');
  v_saved public.push_subscriptions%rowtype;
  v_backfilled integer:=0;
begin
  if v_uid is null then return jsonb_build_object('ok',false,'code','AUTH_REQUIRED'); end if;
  if v_provider<>'fcm' then return jsonb_build_object('ok',false,'code','UNSUPPORTED_PROVIDER'); end if;
  if v_token is null or length(v_token) not between 20 and 4096 then return jsonb_build_object('ok',false,'code','INVALID_PUSH_TOKEN'); end if;
  if v_platform not in ('web','android','ios','unknown') then return jsonb_build_object('ok',false,'code','INVALID_PLATFORM'); end if;
  if length(coalesce(v_instance,''))>200 or length(coalesce(p_device_label,''))>200 or length(coalesce(p_user_agent,''))>1000 then return jsonb_build_object('ok',false,'code','VALIDATION_ERROR'); end if;

  update public.push_subscriptions set active=false,disabled_at=now(),disabled_reason='TOKEN_REPLACED',updated_at=now()
   where uid=v_uid and provider=v_provider and v_instance is not null and app_instance_id=v_instance and token is distinct from v_token and active;

  insert into public.push_subscriptions(id,uid,provider,token,platform,app_instance_id,device_label,ua,active,created_at,last_seen_at,updated_at,failure_count)
  values('push_'||replace(gen_random_uuid()::text,'-',''),v_uid,v_provider,v_token,v_platform,v_instance,
    nullif(left(btrim(coalesce(p_device_label,'')),200),''),nullif(left(btrim(coalesce(p_user_agent,'')),1000),''),true,now(),now(),now(),0)
  on conflict(provider,token) where token is not null do update set
    uid=excluded.uid,platform=excluded.platform,app_instance_id=excluded.app_instance_id,device_label=excluded.device_label,
    ua=excluded.ua,active=true,last_seen_at=now(),updated_at=now(),disabled_at=null,disabled_reason=null,failure_count=0
  returning * into v_saved;

  insert into private.notification_push_outbox(notification_id,recipient_user_id,device_id,provider,payload)
  select n.id,n.uid,v_saved.id,v_saved.provider,jsonb_build_object(
    'title',case when n.privacy_level='sensitive' then
      case n.category when 'emergency' then 'SchoolSafe — Urgence' when 'security' then 'SchoolSafe — Sécurité'
        when 'convocation' then 'SchoolSafe — Convocation' when 'exit_prepared' then 'SchoolSafe — Sortie'
        when 'exit_confirmed' then 'SchoolSafe — Sortie confirmée' else 'SchoolSafe — Information importante' end
      else n.title end,
    'body',case when n.privacy_level='sensitive' then 'Une information concernant votre enfant est disponible. Ouvrez SchoolSafe.' else left(coalesce(n.msg,''),240) end,
    'action_url',coalesce(nullif(n.action_url,''),'/?page=notifications&notification='||n.id),
    'data',jsonb_build_object('notification_id',n.id,'category',n.category,'student_id',coalesce(n.student_id,''),'action_url',coalesce(nullif(n.action_url,''),'/?page=notifications&notification='||n.id))
  ) from public.notifs n where n.uid=v_uid and n.archived_at is null and not n.read and n.push_requested
    and (n.created_at>=now()-interval '24 hours' or (n.requires_ack and n.acknowledged_at is null and n.created_at>=now()-interval '30 days'))
  on conflict(notification_id,device_id) do nothing;
  get diagnostics v_backfilled=row_count;
  return jsonb_build_object('ok',true,'code','PUSH_DEVICE_REGISTERED','device_id',v_saved.id,'provider',v_saved.provider,'platform',v_saved.platform,'queued_notifications',v_backfilled);
end;
$function$;

CREATE OR REPLACE FUNCTION public.disable_my_push_device(p_device_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid text:=private.current_app_user_id(); v_count integer;
begin
  if v_uid is null then return jsonb_build_object('ok',false,'code','AUTH_REQUIRED'); end if;
  update public.push_subscriptions set active=false,disabled_at=now(),disabled_reason='USER_DISABLED',updated_at=now()
  where id=p_device_id and uid=v_uid and active;
  get diagnostics v_count=row_count;
  return jsonb_build_object('ok',v_count=1,'code',case when v_count=1 then 'PUSH_DEVICE_DISABLED' else 'DEVICE_NOT_FOUND' end);
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_my_push_device_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid text:=private.current_app_user_id(); v_devices jsonb;
begin
  if v_uid is null then return jsonb_build_object('ok',false,'code','AUTH_REQUIRED'); end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'device_id',d.id,'provider',d.provider,'platform',d.platform,'device_label',d.device_label,
    'active',d.active,'created_at',d.created_at,'last_seen_at',d.last_seen_at,
    'last_success_at',d.last_success_at,'disabled_at',d.disabled_at,'disabled_reason',d.disabled_reason
  ) order by d.last_seen_at desc),'[]'::jsonb) into v_devices
  from public.push_subscriptions d where d.uid=v_uid;
  return jsonb_build_object('ok',true,'devices',v_devices,'active_count',
    (select count(*) from public.push_subscriptions where uid=v_uid and active));
end;
$function$;

CREATE OR REPLACE FUNCTION public.claim_notification_push_batch(p_limit integer DEFAULT 100)
 RETURNS TABLE(outbox_id text, notification_id text, device_id text, provider text, token text, payload jsonb, attempt_no integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_limit integer:=greatest(1,least(coalesce(p_limit,100),500));
begin
  if auth.role()<>'service_role' and current_user<>'postgres' then raise exception 'Accès refusé' using errcode='42501'; end if;
  update private.notification_push_outbox set status='queued',lease_until=null,next_attempt_at=now(),updated_at=now(),last_error=coalesce(last_error,'LEASE_EXPIRED')
   where status='sending' and lease_until<now();
  return query
  with picked as (
    select o.id from private.notification_push_outbox o
    join public.push_subscriptions d on d.id=o.device_id and d.active
    where o.status in ('queued','failed') and o.next_attempt_at<=now()
    order by case when (select n.priority from public.notifs n where n.id=o.notification_id)='urgent' then 0 else 1 end,o.created_at
    for update of o skip locked limit v_limit
  ), claimed as (
    update private.notification_push_outbox o set status='sending',attempts=o.attempts+1,lease_until=now()+interval '2 minutes',updated_at=now()
    from picked p where o.id=p.id returning o.*
  )
  select c.id,c.notification_id,c.device_id,c.provider,d.token,c.payload,c.attempts
  from claimed c join public.push_subscriptions d on d.id=c.device_id and d.active;
end;
$function$;

CREATE OR REPLACE FUNCTION public.complete_notification_push_delivery(p_outbox_id text, p_success boolean, p_provider_message_id text DEFAULT NULL::text, p_error text DEFAULT NULL::text, p_disable_device boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o private.notification_push_outbox%rowtype; v_status text;
begin
  if auth.role()<>'service_role' and current_user<>'postgres' then raise exception 'Accès refusé' using errcode='42501'; end if;
  select * into o from private.notification_push_outbox where id=p_outbox_id for update;
  if not found then return jsonb_build_object('ok',false,'code','OUTBOX_NOT_FOUND'); end if;
  if p_success then
    update private.notification_push_outbox set status='sent',sent_at=now(),provider_message_id=nullif(p_provider_message_id,''),last_error=null,lease_until=null,updated_at=now()
    where id=o.id;
    update public.push_subscriptions set last_success_at=now(),failure_count=0,last_seen_at=now(),updated_at=now() where id=o.device_id;
    v_status:='sent';
  else
    if p_disable_device or o.attempts>=5 then v_status:='dead'; else v_status:='failed'; end if;
    update private.notification_push_outbox set status=v_status,last_error=left(coalesce(p_error,'PUSH_FAILED'),1000),lease_until=null,
      next_attempt_at=case when v_status='failed' then now()+make_interval(mins=>least(60,greatest(1,o.attempts*o.attempts))) else next_attempt_at end,updated_at=now()
    where id=o.id;
    update public.push_subscriptions set failure_count=failure_count+1,updated_at=now(),
      active=case when p_disable_device then false else active end,
      disabled_at=case when p_disable_device then now() else disabled_at end,
      disabled_reason=case when p_disable_device then 'PROVIDER_TOKEN_INVALID' else disabled_reason end
    where id=o.device_id;
  end if;
  return jsonb_build_object('ok',true,'code','PUSH_DELIVERY_UPDATED','status',v_status,'attempts',o.attempts);
end;
$function$;

COMMIT;
