-- P0-30b Web Push — read-only verification after backend application.
-- This file must never print endpoint/auth/p256dh/VAPID values.

select
  to_regprocedure('public.get_webpush_public_config()') is not null as has_public_config_rpc,
  to_regprocedure('public.register_webpush_device(text,text,text,text,text,text,text)') is not null as has_register_webpush_rpc,
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

-- Public key presence only; never print the key.
select
  (vapid_public_key is not null and btrim(vapid_public_key)<>'') as vapid_public_key_present,
  coalesce(length(vapid_public_key),0) as vapid_public_key_length
from public.settings
order by id
limit 1;

-- Confirm the private VAPID key is NOT represented as a public settings column.
select not exists(
  select 1
  from information_schema.columns
  where table_schema='public'
    and table_name='settings'
    and column_name in ('vapid_private_key','webpush_private_key')
) as no_public_private_vapid_column;
