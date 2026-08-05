revoke all on function public.get_archive_summary() from public;
grant execute on function public.get_archive_summary() to authenticated;

revoke all on function public.archive_administrative_document(text) from public;
revoke all on function public.restore_administrative_document(text) from public;
grant execute on function public.archive_administrative_document(text) to authenticated;
grant execute on function public.restore_administrative_document(text) to authenticated;
