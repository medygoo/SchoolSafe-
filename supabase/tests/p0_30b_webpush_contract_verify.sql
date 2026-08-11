-- P0-30b Web Push — read-only verification after backend application.
-- Never print endpoint/auth/p256dh/VAPID values.

select
  to_regprocedure('public.get_safe_settings()') is not null as has_safe_settings_rpc,
  to_regprocedure('public.register_push_device(text,text,text,text,text,text)') is not null as has_shared_register_rpc,
  to_regprocedure('public.claim_notification_push_batch(integer)') is not null as has_fcm_claim_rpc,
  to_regprocedure('public.claim_webpush_notification_batch(integer)') is not null as has_webpush_claim_rpc,
  to_regprocedure('public.disable_my_push_device(text)') is not null as has_disable_rpc,
  to_regprocedure('public.get_my_push_device_status()') is not null as has_device_status_rpc,
  to_regprocedure('public.complete_notification_push_delivery(text,boolean,text,text,boolean)') is not null as has_complete_rpc;

select
  exists(
    select 1 from pg_policies
    where schemaname='public'
      and tablename='push_subscriptions'
      and policyname='push_subscriptions_no_direct_access'
      and qual='false'
      and with_check='false'
  ) as direct_device_access_denied;

select
  exists(
    select 1 from pg_indexes
    where schemaname='public'
      and tablename='push_subscriptions'
      and indexname='uq_push_subscriptions_webpush_endpoint'
  ) as webpush_endpoint_unique_index_present;

-- Contract-source checks only; no secret values are returned.
select
  position('vapid_public_key' in pg_get_functiondef('public.get_safe_settings()'::regprocedure)) > 0
    as safe_settings_exposes_public_vapid_key,
  position('webpush' in pg_get_functiondef('public.register_push_device(text,text,text,text,text,text)'::regprocedure)) > 0
    as shared_register_supports_webpush,
  position('DEVICE_OWNER_CHANGED' in pg_get_functiondef('public.register_push_device(text,text,text,text,text,text)'::regprocedure)) > 0
    as register_invalidates_pending_rows_on_owner_change;

select
  position('d.uid=o.recipient_user_id' in replace(pg_get_functiondef('public.claim_notification_push_batch(integer)'::regprocedure),' ','')) > 0
    as fcm_claim_checks_device_owner,
  position('d.uid=o.recipient_user_id' in replace(pg_get_functiondef('public.claim_webpush_notification_batch(integer)'::regprocedure),' ','')) > 0
    as webpush_claim_checks_device_owner;

select
  count(*) filter (where provider='webpush') as webpush_devices_total,
  count(*) filter (where provider='webpush' and active) as webpush_devices_active,
  count(*) filter (where provider='fcm') as fcm_devices_total,
  count(*) filter (where provider='fcm' and active) as fcm_devices_active
from public.push_subscriptions;

select
  count(*) filter (where provider='webpush' and status in ('queued','failed','sending')) as webpush_pending,
  count(*) filter (where provider='fcm' and status in ('queued','failed','sending')) as fcm_pending,
  count(*) filter (where status='sent') as sent_total,
  count(*) filter (where status='dead') as dead_total
from private.notification_push_outbox;

-- Public key PRESENCE only; never print the key.
select
  (vapid_public_key is not null and btrim(vapid_public_key)<>'') as vapid_public_key_present,
  coalesce(length(vapid_public_key),0) as vapid_public_key_length
from public.settings
order by id
limit 1;

-- A private VAPID key must not exist as a public settings column.
select not exists(
  select 1
  from information_schema.columns
  where table_schema='public'
    and table_name='settings'
    and column_name in ('vapid_private_key','webpush_private_key')
) as no_public_private_vapid_column;
