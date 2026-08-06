-- P0-32: server-owned sender provenance and hidden device tokens.

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
$$;

drop policy if exists push_subscriptions_read on public.push_subscriptions;
revoke select on public.push_subscriptions from authenticated;

create or replace function public.get_my_push_device_status()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
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
$$;
revoke all on function public.get_my_push_device_status() from public,anon;
grant execute on function public.get_my_push_device_status() to authenticated,service_role;

comment on function public.get_my_push_device_status() is 'Returns device status without exposing FCM or Web Push tokens.';
