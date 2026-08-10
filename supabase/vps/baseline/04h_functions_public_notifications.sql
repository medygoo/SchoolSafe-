-- SchoolSafe VPS baseline - 04h notification center RPCs

BEGIN;

CREATE OR REPLACE FUNCTION public.get_my_notification_center(p_limit integer DEFAULT 50, p_before timestamp with time zone DEFAULT NULL::timestamp with time zone, p_category text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
end;
$function$;

CREATE OR REPLACE FUNCTION public.mark_my_notification_opened(p_notification_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid text:=private.current_app_user_id(); v_count integer;
begin
  update public.notifs set opened_at=coalesce(opened_at,now()) where id=p_notification_id and uid=v_uid and archived_at is null;
  get diagnostics v_count=row_count;
  return jsonb_build_object('ok',v_count=1,'code',case when v_count=1 then 'NOTIFICATION_OPENED' else 'NOTIFICATION_NOT_FOUND' end);
end;
$function$;

CREATE OR REPLACE FUNCTION public.mark_my_notification_read(p_notification_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid text:=private.current_app_user_id(); v_count integer;
begin
  update public.notifs set read=true,opened_at=coalesce(opened_at,now()),read_at=coalesce(read_at,now()) where id=p_notification_id and uid=v_uid and archived_at is null;
  get diagnostics v_count=row_count;
  return jsonb_build_object('ok',v_count=1,'code',case when v_count=1 then 'NOTIFICATION_READ' else 'NOTIFICATION_NOT_FOUND' end);
end;
$function$;

CREATE OR REPLACE FUNCTION public.acknowledge_my_notification(p_notification_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid text:=private.current_app_user_id(); v_count integer;
begin
  update public.notifs set acknowledged_at=coalesce(acknowledged_at,now()),read=true,opened_at=coalesce(opened_at,now()),read_at=coalesce(read_at,now())
  where id=p_notification_id and uid=v_uid and archived_at is null and requires_ack;
  get diagnostics v_count=row_count;
  return jsonb_build_object('ok',v_count=1,'code',case when v_count=1 then 'NOTIFICATION_ACKNOWLEDGED' else 'ACK_NOT_AVAILABLE' end);
end;
$function$;

CREATE OR REPLACE FUNCTION public.archive_my_notification(p_notification_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_uid text:=private.current_app_user_id(); v_count integer;
begin
  update public.notifs set archived_at=coalesce(archived_at,now()) where id=p_notification_id and uid=v_uid;
  get diagnostics v_count=row_count;
  return jsonb_build_object('ok',v_count=1,'code',case when v_count=1 then 'NOTIFICATION_ARCHIVED' else 'NOTIFICATION_NOT_FOUND' end);
end;
$function$;

CREATE OR REPLACE FUNCTION public.send_school_notification(p_notification jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
    if v_actor_role='gardien' and (v_student_id is null or v_student.pid is distinct from v_target.id) then return jsonb_build_object('ok',false,'code','STUDENT_PARENT_REQUIRED'); end if;
    if v_actor_role='direction3' and (case v_target.role when 'parent' then 'parent' else v_target.role end)<>'parent' then return jsonb_build_object('ok',false,'code','PARENT_RECIPIENT_REQUIRED'); end if;
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
$function$;

COMMIT;
