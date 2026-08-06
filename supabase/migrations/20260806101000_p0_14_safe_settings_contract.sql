-- P0-14: stable, least-privilege settings payload for all authenticated roles.

create or replace function public.get_safe_settings()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  s public.settings%rowtype;
  r text := private.current_app_role();
begin
  if r is null then
    raise exception 'Session inactive' using errcode = '42501';
  end if;

  select * into s from public.settings order by id limit 1;
  if not found then
    return '{}'::jsonb;
  end if;

  return jsonb_strip_nulls(jsonb_build_object(
    'id', s.id,
    'year', s.year,
    'school', s.school,
    'toggles', s.toggles,
    'horaires', s.horaires,
    'lockdown', s.lockdown,
    'retention', s.retention,
    'trimlocks', s.trimlocks,
    'currenttrimestre', s.currenttrimestre,
    'school_type', s.school_type,
    'session_timeout_min', s.session_timeout_min,
    'rattrapage_rate', s.rattrapage_rate,
    'rattrapage_threshold', s.rattrapage_threshold,
    'fees', case when r in ('direction', 'direction3', 'parent') then s.fees else null end,
    'feescontrol', case when r in ('direction', 'direction3', 'parent') then s.feescontrol else null end
  ));
end;
$$;

revoke all on function public.get_safe_settings() from public, anon;
grant execute on function public.get_safe_settings() to authenticated, service_role;

comment on function public.get_safe_settings() is
  'Retourne uniquement les paramètres nécessaires à l interface selon le rôle. N expose jamais qr_secret, msg_enc_key, soldes d ouverture, budget, compteur de reçus, clé VAPID ou numéro opérateur.';
