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
  if v_actor_id is null then v_actor_id:=coalesce(new.created_by_user_id,new."by"); end if;
  if v_actor_id is not null then
    select u.name,
      case u.role when 'direction_pedagogique' then 'direction2' when 'caisse' then 'direction3' else u.role end
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
