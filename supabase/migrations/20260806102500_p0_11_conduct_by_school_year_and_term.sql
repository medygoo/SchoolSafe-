-- P0-11: every conduct record belongs to one school year and one trimester.

create or replace function private.stamp_conduct_period()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_year text;
  v_term text;
  v_settings_year text;
  v_settings_term text;
begin
  select nullif(btrim(s.year), ''), upper(nullif(btrim(s.currenttrimestre), ''))
    into v_settings_year, v_settings_term
  from public.settings s
  order by s.id
  limit 1;

  v_year := coalesce(nullif(btrim(new.year), ''), v_settings_year, private.current_school_year());
  v_term := upper(coalesce(nullif(btrim(new.trimestre), ''), v_settings_term));

  if v_year is null or v_year !~ '^\d{4}-\d{4}$' then
    raise exception 'Année scolaire invalide pour la conduite.' using errcode = '22023';
  end if;

  if v_term not in ('T1', 'T2', 'T3') then
    raise exception 'Trimestre invalide pour la conduite.' using errcode = '22023';
  end if;

  if tg_op = 'UPDATE' and (
    old.year is distinct from v_year or old.trimestre is distinct from v_term
  ) then
    raise exception 'La période d une conduite enregistrée est immuable.' using errcode = '23514';
  end if;

  new.year := v_year;
  new.trimestre := v_term;
  return new;
end;
$$;

revoke all on function private.stamp_conduct_period() from public, anon, authenticated;
grant execute on function private.stamp_conduct_period() to service_role;

drop trigger if exists trg_conduct_period on public.conduct;
create trigger trg_conduct_period
before insert or update on public.conduct
for each row execute function private.stamp_conduct_period();

alter table public.conduct
  alter column year set not null,
  alter column trimestre set not null;

alter table public.conduct drop constraint if exists conduct_year_format_check;
alter table public.conduct
  add constraint conduct_year_format_check
  check (year ~ '^\d{4}-\d{4}$');

alter table public.conduct drop constraint if exists conduct_trimestre_check;
alter table public.conduct
  add constraint conduct_trimestre_check
  check (trimestre in ('T1', 'T2', 'T3'));

create index if not exists idx_conduct_sid_year_trimestre_date
  on public.conduct(sid, year, trimestre, date);

comment on column public.conduct.year is
  'Année scolaire obligatoire de la conduite, par exemple 2026-2027.';
comment on column public.conduct.trimestre is
  'Trimestre obligatoire T1, T2 ou T3. La valeur est fixée à la création.';
comment on function private.stamp_conduct_period() is
  'Complète et valide côté serveur l année scolaire et le trimestre de chaque conduite.';
