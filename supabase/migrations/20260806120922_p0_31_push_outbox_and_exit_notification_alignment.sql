-- P0-31: provider-neutral push outbox and app+push exit notifications.

create table if not exists private.notification_push_outbox(
  id text primary key default ('pout_'||replace(gen_random_uuid()::text,'-','')),
  notification_id text not null references public.notifs(id) on delete cascade,
  recipient_user_id text not null references public.users(id) on delete restrict,
  device_id text not null references public.push_subscriptions(id) on delete restrict,
  provider text not null default 'fcm' check(provider in ('fcm','webpush')),
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'queued' check(status in ('queued','sending','sent','failed','dead')),
  attempts integer not null default 0 check(attempts between 0 and 100),
  next_attempt_at timestamptz not null default now(),
  lease_until timestamptz,
  last_error text,
  provider_message_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  sent_at timestamptz,
  unique(notification_id,device_id)
);
create index if not exists idx_notification_push_outbox_claim on private.notification_push_outbox(status,next_attempt_at,created_at)
  where status in ('queued','failed','sending');
create index if not exists idx_notification_push_outbox_notification on private.notification_push_outbox(notification_id,status);

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
  new.priority:=coalesce(nullif(lower(btrim(coalesce(new.priority,''))),''),'normal');
  if new.category in ('emergency','security') then new.priority:='urgent';
  elsif new.category in ('convocation','exit_refused','exit_expired') and new.priority in ('low','normal') then new.priority:='high'; end if;
  new.privacy_level:=coalesce(nullif(lower(btrim(coalesce(new.privacy_level,''))),''),'normal');
  if new.category in ('emergency','security','convocation','payment','receipt_available','result_available','exit_prepared','exit_confirmed','exit_refused','exit_expired') then
    new.privacy_level:='sensitive';
  end if;
  if new.category in ('emergency','convocation','security') then new.requires_ack:=true;
  else new.requires_ack:=coalesce(new.requires_ack,false); end if;
  new.data:=coalesce(new.data,'{}'::jsonb);
  new.push_requested:=coalesce(new.push_requested,true);
  new.read:=coalesce(new.read,false);
  v_actor_id:=private.current_app_user_id();
  if v_actor_id is null then v_actor_id:=coalesce(new.created_by_user_id,new."by"); end if;
  if v_actor_id is not null then
    select u.name,case u.role when 'direction_pedagogique' then 'direction2' when 'caisse' then 'direction3' else u.role end
      into v_actor_name,v_actor_role from public.users u where u.id=v_actor_id limit 1;
  end if;
  new.created_by_user_id:=coalesce(new.created_by_user_id,v_actor_id);
  new.created_by_name:=coalesce(nullif(new.created_by_name,''),v_actor_name);
  new.created_by_role:=coalesce(nullif(new.created_by_role,''),v_actor_role);
  new."by":=coalesce(new."by",new.created_by_user_id);
  if new.read then new.read_at:=coalesce(new.read_at,new.created_at); end if;
  return new;
end;
$$;

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
      else 'SchoolSafe — Information importante' end;
    v_body:='Une information concernant votre enfant est disponible. Ouvrez SchoolSafe.';
  else
    v_title:=coalesce(new.title,'SchoolSafe');
    v_body:=left(coalesce(new.msg,''),240);
  end if;
  v_link:=coalesce(nullif(new.action_url,''),'/?page=notifications&notification='||new.id);
  for d in select * from public.push_subscriptions where uid=new.uid and active and provider='fcm' and token is not null loop
    insert into private.notification_push_outbox(notification_id,recipient_user_id,device_id,provider,payload)
    values(new.id,new.uid,d.id,d.provider,jsonb_build_object(
      'title',v_title,'body',v_body,'action_url',v_link,
      'data',jsonb_build_object('notification_id',new.id,'category',new.category,'student_id',coalesce(new.student_id,''),'action_url',v_link)
    )) on conflict(notification_id,device_id) do nothing;
  end loop;
  return new;
end;
$$;
drop trigger if exists notifs_queue_push on public.notifs;
create trigger notifs_queue_push after insert on public.notifs
for each row execute function private.queue_push_for_notification();

-- Registering a new phone also queues recent unread/mandatory notifications.
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
$$;

create or replace function public.claim_notification_push_batch(p_limit integer default 100)
returns table(outbox_id text,notification_id text,device_id text,provider text,token text,payload jsonb,attempt_no integer)
language plpgsql
security definer
set search_path=''
as $$
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
$$;

create or replace function public.complete_notification_push_delivery(
  p_outbox_id text,p_success boolean,p_provider_message_id text default null,p_error text default null,p_disable_device boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
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
$$;

create or replace function public.get_my_notification_center(p_limit integer default 50,p_before timestamptz default null,p_category text default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_uid text:=private.current_app_user_id(); v_items jsonb; v_limit integer:=greatest(1,least(coalesce(p_limit,50),100));
begin
  if v_uid is null then return jsonb_build_object('ok',false,'code','AUTH_REQUIRED'); end if;
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_items from (
    select n.id,n.category,n.title,n.msg as message,n.type,n.student_id,n.action_url,n.priority,n.privacy_level,n.requires_ack,
      n.created_at,n.opened_at,n.read,n.read_at,n.acknowledged_at,n.created_by_name,n.created_by_role,n.source_type,n.source_id,n.data,
      case
        when not n.push_requested then 'not_requested'
        when exists(select 1 from private.notification_push_outbox o where o.notification_id=n.id and o.status='sent') then 'sent'
        when exists(select 1 from private.notification_push_outbox o where o.notification_id=n.id and o.status in ('queued','sending','failed')) then 'queued'
        when exists(select 1 from private.notification_push_outbox o where o.notification_id=n.id and o.status='dead') then 'failed'
        when not exists(select 1 from public.push_subscriptions d where d.uid=n.uid and d.active) then 'no_device'
        else 'not_queued' end as push_status
    from public.notifs n where n.uid=v_uid and n.archived_at is null
      and (p_before is null or n.created_at<p_before)
      and (nullif(btrim(coalesce(p_category,'')),'') is null or n.category=lower(btrim(p_category)))
    order by n.created_at desc limit v_limit
  ) x;
  return jsonb_build_object('ok',true,'items',v_items,
    'unread_count',(select count(*) from public.notifs where uid=v_uid and archived_at is null and not read),
    'ack_required_count',(select count(*) from public.notifs where uid=v_uid and archived_at is null and requires_ack and acknowledged_at is null),
    'active_device_count',(select count(*) from public.push_subscriptions where uid=v_uid and active));
end; $$;

create or replace function private.queue_student_exit_notification(p_exit_event_id text,p_notification_type text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  e public.student_exit_events%rowtype;
  p public.users%rowtype;
  v_message text;
  v_type text:=lower(btrim(coalesce(p_notification_type,'')));
  v_notification_id text;
  v_dedupe text;
  v_push_count integer:=0;
  v_channels jsonb:='["app"]'::jsonb;
begin
  select * into e from public.student_exit_events where id=p_exit_event_id;
  if not found then return jsonb_build_object('ok',false,'code','EXIT_EVENT_NOT_FOUND'); end if;
  select * into p from public.users where id=e.parent_id_snapshot and status='active';
  if not found then return jsonb_build_object('ok',false,'code','PARENT_NOT_FOUND'); end if;
  v_message:=case v_type
    when 'exit_prepared' then e.student_name_snapshot||' est prêt(e) pour la sortie. Vous pouvez venir le/la récupérer au portail.'
    when 'exit_confirmed' then 'La sortie de '||e.student_name_snapshot||' a été confirmée à '||coalesce(to_char(timezone('Africa/Kinshasa',e.validated_at),'HH24:MI'),to_char(timezone('Africa/Kinshasa',now()),'HH24:MI'))||'. Récupéré(e) par '||coalesce(e.escort_name_snapshot,'la personne autorisée')||'.'
    when 'exit_refused' then 'La sortie de '||e.student_name_snapshot||' a été refusée. Contactez la Direction.'
    when 'exit_cancelled' then 'La préparation de sortie de '||e.student_name_snapshot||' a été annulée.'
    when 'exit_expired' then 'La préparation de sortie de '||e.student_name_snapshot||' a expiré. L enfant reste sous la responsabilité de l école.'
    else null end;
  if v_message is null then return jsonb_build_object('ok',false,'code','UNSUPPORTED_NOTIFICATION'); end if;
  v_dedupe:='exit:'||e.id||':'||v_type;
  v_notification_id:='notif_'||replace(gen_random_uuid()::text,'-','');
  insert into public.notifs(id,uid,"from",msg,type,status,category,title,student_id,action_url,priority,privacy_level,requires_ack,
    created_by_user_id,created_by_name,created_by_role,source_type,source_id,dedupe_key,data,push_requested)
  values(v_notification_id,p.id,'SchoolSafe — Sortie',v_message,
    case when v_type in ('exit_refused','exit_expired') then 'warning' else 'info' end,v_type,v_type,'SchoolSafe — Sortie',e.sid,
    '/?page=notifications&notification='||v_notification_id,
    case when v_type in ('exit_refused','exit_expired') then 'high' else 'normal' end,'sensitive',false,
    coalesce(e.validated_by_user_id,e.gate_scanned_by_user_id,e.prepared_by_user_id),
    coalesce(e.validated_by_name,e.gate_scanned_by_name,e.prepared_by_name),
    coalesce(e.validated_by_role,e.gate_scanned_by_role,e.prepared_by_role),
    'student_exit_event',e.id,v_dedupe,jsonb_build_object('exit_event_id',e.id,'student_id',e.sid,'status',v_type),true)
  on conflict(uid,dedupe_key) where dedupe_key is not null do nothing returning id into v_notification_id;
  if v_notification_id is null then select id into v_notification_id from public.notifs where uid=p.id and dedupe_key=v_dedupe; end if;
  select count(*) into v_push_count from private.notification_push_outbox where notification_id=v_notification_id;
  if v_push_count>0 then v_channels:=v_channels||'"push"'::jsonb; end if;
  delete from private.student_exit_notification_outbox where exit_event_id=e.id and channel in ('email','whatsapp') and status='queued';
  return jsonb_build_object('ok',true,'channels',v_channels,'message',v_message,'notification_id',v_notification_id,
    'push_status',case when v_push_count>0 then 'queued' else 'no_device' end,'push_device_count',v_push_count);
end;
$$;

revoke all on function public.claim_notification_push_batch(integer) from public,anon,authenticated;
grant execute on function public.claim_notification_push_batch(integer) to service_role;
revoke all on function public.complete_notification_push_delivery(text,boolean,text,text,boolean) from public,anon,authenticated;
grant execute on function public.complete_notification_push_delivery(text,boolean,text,text,boolean) to service_role;

comment on table private.notification_push_outbox is 'Private provider delivery queue. Tokens remain in push_subscriptions and are exposed only to the service-role claim RPC.';
comment on function public.claim_notification_push_batch(integer) is 'Service-role only: leases queued push deliveries for an FCM dispatcher.';
comment on function private.queue_student_exit_notification(text,text) is 'Exit notifications use the in-app center plus free push; automatic WhatsApp/email dispatch is intentionally disabled.';
