revoke all on function public.submit_preinscription_email(jsonb) from public, anon, authenticated;
grant execute on function public.submit_preinscription_email(jsonb) to service_role;
revoke all on function public.validate_preinscription_email(text) from public, anon, authenticated;
grant execute on function public.validate_preinscription_email(text) to service_role;
