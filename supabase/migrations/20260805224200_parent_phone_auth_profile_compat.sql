-- Conserver le contrat e-mail historique sous un nom interne, puis aiguiller
-- uniquement les Parents sans e-mail vers le nouveau contrat téléphone.
do $$
begin
  if to_regprocedure('public.save_school_user_profile_email(jsonb)') is null
     and to_regprocedure('public.save_school_user_profile(jsonb)') is not null then
    alter function public.save_school_user_profile(jsonb)
      rename to save_school_user_profile_email;
  end if;
end;
$$;

create or replace function public.save_school_user_profile(p_user jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  v_id text := btrim(coalesce(p_user->>'id', ''));
  v_requested_role text;
  v_existing public.users%rowtype;
  v_effective_email text;
  v_effective_phone text;
begin
  select * into v_existing from public.users where id = v_id;

  v_requested_role := case coalesce(nullif(btrim(p_user->>'role'), ''), v_existing.role, '')
    when 'direction_pedagogique' then 'direction2'
    when 'caisse' then 'direction3'
    when 'enseignant_maternelle' then 'enseignant'
    else coalesce(nullif(btrim(p_user->>'role'), ''), v_existing.role, '')
  end;

  v_effective_email := case
    when p_user ? 'email' then nullif(btrim(coalesce(p_user->>'email', '')), '')
    else v_existing.email
  end;
  v_effective_phone := case
    when p_user ? 'phone' then nullif(btrim(coalesce(p_user->>'phone', '')), '')
    else v_existing.phone
  end;

  if v_requested_role = 'parent'
     and v_effective_email is null
     and v_effective_phone is not null then
    return public.save_parent_phone_profile(p_user || jsonb_build_object('role', 'parent'));
  end if;

  return public.save_school_user_profile_email(p_user);
end;
$$;

revoke all on function public.save_school_user_profile_email(jsonb) from public, anon;
grant execute on function public.save_school_user_profile_email(jsonb) to authenticated;
revoke all on function public.save_school_user_profile(jsonb) from public, anon;
grant execute on function public.save_school_user_profile(jsonb) to authenticated;
