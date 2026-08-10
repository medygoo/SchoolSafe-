-- SchoolSafe VPS baseline - 03f notifications/exit helpers

BEGIN;

CREATE OR REPLACE FUNCTION private.disable_push_devices_for_inactive_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if old.status is distinct from new.status and new.status<>'active' then
    update public.push_subscriptions set active=false,disabled_at=now(),disabled_reason='ACCOUNT_'||upper(new.status),updated_at=now()
    where uid=new.id and active;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.protect_notification_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION private.stamp_notification_record()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  if v_actor_id is not null then
    select u.name,case u.role when 'direction_pedagogique' then 'direction2' when 'caisse' then 'direction3' else u.role end
      into v_actor_name,v_actor_role from public.users u where u.id=v_actor_id and u.status='active' limit 1;
    new.created_by_user_id:=v_actor_id;
    new.created_by_name:=v_actor_name;
    new.created_by_role:=v_actor_role;
    new."by":=v_actor_id;
  else
    v_actor_id:=coalesce(new.created_by_user_id,new."by");
    if v_actor_id is not null then
      select u.name,case u.role when 'direction_pedagogique' then 'direction2' when 'caisse' then 'direction3' else u.role end
        into v_actor_name,v_actor_role from public.users u where u.id=v_actor_id limit 1;
      new.created_by_user_id:=v_actor_id;
      new.created_by_name:=coalesce(nullif(new.created_by_name,''),v_actor_name);
      new.created_by_role:=coalesce(nullif(new.created_by_role,''),v_actor_role);
      new."by":=v_actor_id;
    end if;
  end if;
  if new.read then new.read_at:=coalesce(new.read_at,new.created_at); end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.queue_push_for_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION private.protect_student_exit_history()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op='DELETE' then
    raise exception 'L historique de sortie ne peut pas être supprimé.' using errcode='23514';
  end if;
  if old.status in ('confirmed','refused','cancelled','expired') then
    raise exception 'Un événement de sortie finalisé est immuable.' using errcode='23514';
  end if;
  new.updated_at:=now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.queue_student_exit_notification(p_exit_event_id text, p_notification_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$;

CREATE OR REPLACE FUNCTION private.expire_student_exit_events()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  r record;
  v_count integer:=0;
begin
  for r in
    select id from public.student_exit_events
    where status in ('prepared','gate_scanned') and expires_at<=now()
    for update skip locked
  loop
    update public.student_exit_events set status='expired',finalized_at=now(),decision_note='Expiration automatique'
    where id=r.id;
    perform private.queue_student_exit_notification(r.id,'exit_expired');
    v_count:=v_count+1;
  end loop;
  return v_count;
end;
$function$;

CREATE OR REPLACE FUNCTION private.notify_scan_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_parent text;
  v_message text;
  rec record;
begin
  if new.exit_event_id is not null then return new; end if;
  select pid into v_parent from public.students where id=new.sid;
  if new.type='entry' and new.status in ('ontime','late') then
    v_message:=new.name||' : entrée enregistrée à '||coalesce(new.time,'');
  elsif new.type='exit' and new.status='authorized' then
    v_message:=new.name||' : sortie autorisée à '||coalesce(new.time,'');
  else
    v_message:=new.name||' : contrôle de sécurité refusé. Contactez la Direction générale.';
  end if;
  if v_parent is not null then
    insert into public.notifs(id,uid,"from",msg,type,date,time,read,by)
    values('notif_'||replace(gen_random_uuid()::text,'-',''),v_parent,'SchoolSafe',v_message,
      case when new.status in ('ontime','late','authorized') then 'info' else 'warning' end,
      new.date,new.time,false,new.by_uid);
  end if;
  if new.status in ('refused_access','unauthorized') then
    for rec in select id from public.users where status='active'
      and role in ('direction','direction2','direction_pedagogique')
    loop
      insert into public.notifs(id,uid,"from",msg,type,date,time,read,by)
      values('notif_'||replace(gen_random_uuid()::text,'-',''),rec.id,'Contrôle d’accès',v_message,
        'warning',new.date,new.time,false,new.by_uid);
    end loop;
  end if;
  return new;
end;
$function$;

COMMIT;
