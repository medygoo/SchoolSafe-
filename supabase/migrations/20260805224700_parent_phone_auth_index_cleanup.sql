drop index if exists public.users_access_channel_idx;
drop index if exists public.users_parent_phone_access_idx;
create index if not exists parent_phone_access_requested_by_idx
on private.parent_phone_access_requests(requested_by);
