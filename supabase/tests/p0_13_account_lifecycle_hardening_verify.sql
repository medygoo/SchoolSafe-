-- P0-13 account lifecycle hardening — read-only verification.

select
  to_regprocedure('public.suspend_school_account(text,text)') is not null as has_suspend_rpc,
  to_regprocedure('public.reactivate_school_account(text)') is not null as has_reactivate_rpc,
  to_regprocedure('public.prepare_school_account_removal(uuid,text,text)') is not null as has_prepare_rpc,
  to_regprocedure('public.confirm_school_account_removal(uuid,text,uuid)') is not null as has_confirm_rpc;

select
  has_function_privilege('authenticated','public.suspend_school_account(text,text)','EXECUTE') as authenticated_can_suspend,
  has_function_privilege('authenticated','public.reactivate_school_account(text)','EXECUTE') as authenticated_can_reactivate,
  not has_function_privilege('authenticated','public.prepare_school_account_removal(uuid,text,text)','EXECUTE') as prepare_stays_service_only,
  not has_function_privilege('authenticated','public.confirm_school_account_removal(uuid,text,uuid)','EXECUTE') as confirm_stays_service_only;

select
  position('ACCOUNT_ACCESS_REMOVED' in pg_get_functiondef('public.suspend_school_account(text,text)'::regprocedure)) > 0
    as suspend_rejects_permanent_removal,
  position('ACCOUNT_ACCESS_REMOVED' in pg_get_functiondef('public.reactivate_school_account(text)'::regprocedure)) > 0
    as reactivate_rejects_permanent_removal;

-- State inventory only; no personal values returned.
select
  count(*) filter (where status='suspended') as suspended_accounts,
  count(*) filter (where access_removed_at is not null or removed_auth_user_id is not null) as permanently_removed_accounts,
  count(*) filter (
    where (access_removed_at is not null or removed_auth_user_id is not null)
      and status='active'
  ) as invalid_reactivated_removed_accounts
from public.users;
