-- P0-30b — DRAFT ONLY
-- Expose app_instance_id only to the authenticated owner via the existing
-- status RPC so the frontend can distinguish this browser from another phone.
-- No endpoint/auth/p256dh/token value is returned.

begin;

create or replace function public.get_my_push_device_status()
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
declare
  v_uid text:=private.current_app_user_id();
  v_devices jsonb;
begin
  if v_uid is null then
    return jsonb_build_object('ok',false,'code','AUTH_REQUIRED');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'device_id',d.id,
    'provider',d.provider,
    'platform',d.platform,
    'app_instance_id',d.app_instance_id,
    'device_label',d.device_label,
    'active',d.active,
    'created_at',d.created_at,
    'last_seen_at',d.last_seen_at,
    'last_success_at',d.last_success_at,
    'disabled_at',d.disabled_at,
    'disabled_reason',d.disabled_reason
  ) order by d.last_seen_at desc),'[]'::jsonb)
  into v_devices
  from public.push_subscriptions d
  where d.uid=v_uid;

  return jsonb_build_object(
    'ok',true,
    'devices',v_devices,
    'active_count',(select count(*) from public.push_subscriptions where uid=v_uid and active)
  );
end;
$function$;

rollback;
