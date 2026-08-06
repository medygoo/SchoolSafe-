drop policy if exists push_subscriptions_no_direct_access on public.push_subscriptions;
create policy push_subscriptions_no_direct_access on public.push_subscriptions
for all to authenticated using (false) with check (false);

comment on policy push_subscriptions_no_direct_access on public.push_subscriptions is
  'Explicit deny-all policy. Device registration and status use SECURITY DEFINER RPCs; tokens are never exposed directly.';
