-- SchoolSafe — contrôle de santé externe minimal
--
-- Cette RPC sert à vérifier que PostgREST et PostgreSQL répondent. Elle ne lit
-- aucune table et ne renvoie aucune donnée d'élève, parent, paiement, compte ou
-- configuration. Elle fonctionne en SECURITY INVOKER et n'a aucun privilège
-- supplémentaire.

create or replace function public.schoolsafe_health_check()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'ok', true,
    'service', 'schoolsafe-supabase',
    'checked_at', timezone('Africa/Kinshasa', now())
  );
$$;

revoke all on function public.schoolsafe_health_check() from public;
grant execute on function public.schoolsafe_health_check() to anon, authenticated;

comment on function public.schoolsafe_health_check() is
'Lightweight external health check for SchoolSafe. Returns no school, student, parent, payment, or authentication data.';
