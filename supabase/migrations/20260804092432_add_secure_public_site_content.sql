-- Single-school public website content.
-- Anonymous users may read only this public row. Direction 1 publishes through a guarded RPC.

create table if not exists public.site_content (
  id text primary key default 'main' check (id='main'),
  school_name text not null default 'Complexe Scolaire Le Sage',
  school_name_en text not null default 'The Wise School International',
  tagline text,
  about_text text,
  mission text,
  founded_year text,
  address text,
  city text,
  phone text,
  whatsapp text,
  email text,
  programs jsonb not null default '[]'::jsonb check (jsonb_typeof(programs)='array'),
  pillars jsonb not null default '[]'::jsonb check (jsonb_typeof(pillars)='array'),
  stats jsonb not null default '{}'::jsonb check (jsonb_typeof(stats)='object'),
  staff jsonb not null default '[]'::jsonb check (jsonb_typeof(staff)='array'),
  gallery jsonb not null default '[]'::jsonb check (jsonb_typeof(gallery)='array'),
  hero_photos jsonb not null default '[]'::jsonb check (jsonb_typeof(hero_photos)='array'),
  hero_url text,
  logo_url text,
  theme text not null default 'dark' check (theme in ('dark','light','custom')),
  primary_color text not null default '#c0962e' check (primary_color ~ '^#[0-9A-Fa-f]{6}$'),
  published_at timestamptz,
  updated_at timestamptz not null default now()
);

insert into public.site_content(id,school_name,school_name_en)
values('main','Complexe Scolaire Le Sage','The Wise School International')
on conflict(id) do nothing;

alter table public.site_content enable row level security;

drop policy if exists site_content_public_read on public.site_content;
create policy site_content_public_read
on public.site_content
for select
to anon,authenticated
using (id='main');

revoke all on table public.site_content from public;
revoke all on table public.site_content from anon;
revoke all on table public.site_content from authenticated;
grant select on table public.site_content to anon;
grant select on table public.site_content to authenticated;
grant all on table public.site_content to service_role;

create or replace function public.save_site_content(p_content jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_id text := private.current_app_user_id();
  v_actor_name text;
  v_saved public.site_content%rowtype;
  v_programs jsonb;
  v_pillars jsonb;
  v_stats jsonb;
  v_staff jsonb;
  v_gallery jsonb;
  v_hero_photos jsonb;
  v_theme text;
  v_color text;
begin
  if private.current_app_role()<>'direction' then
    raise exception 'Accès refusé' using errcode='42501';
  end if;
  if p_content is null or jsonb_typeof(p_content)<>'object' then
    raise exception 'Contenu invalide' using errcode='22023';
  end if;

  select name into v_actor_name
  from public.users
  where id=v_actor_id and status='active';
  if not found then raise exception 'Profil Direction introuvable' using errcode='42501'; end if;

  select
    case when p_content ? 'programs' then p_content->'programs' else programs end,
    case when p_content ? 'pillars' then p_content->'pillars' else pillars end,
    case when p_content ? 'stats' then p_content->'stats' else stats end,
    case when p_content ? 'staff' then p_content->'staff' else staff end,
    case when p_content ? 'gallery' then p_content->'gallery' else gallery end,
    case when p_content ? 'hero_photos' then p_content->'hero_photos' else hero_photos end,
    case when p_content ? 'theme' then lower(btrim(coalesce(p_content->>'theme',''))) else theme end,
    case when p_content ? 'primary_color' then btrim(coalesce(p_content->>'primary_color','')) else primary_color end
  into v_programs,v_pillars,v_stats,v_staff,v_gallery,v_hero_photos,v_theme,v_color
  from public.site_content where id='main';

  if jsonb_typeof(v_programs)<>'array' or jsonb_typeof(v_pillars)<>'array'
     or jsonb_typeof(v_staff)<>'array' or jsonb_typeof(v_gallery)<>'array'
     or jsonb_typeof(v_hero_photos)<>'array' or jsonb_typeof(v_stats)<>'object' then
    raise exception 'Structure JSON du site invalide' using errcode='22023';
  end if;
  if v_theme not in ('dark','light','custom') then
    raise exception 'Thème invalide' using errcode='22023';
  end if;
  if v_color !~ '^#[0-9A-Fa-f]{6}$' then
    raise exception 'Couleur invalide' using errcode='22023';
  end if;

  if exists(
    select 1
    from jsonb_array_elements_text(v_hero_photos) x(url)
    where url !~ '^https://'
  ) then
    raise exception 'Les images principales doivent utiliser HTTPS' using errcode='22023';
  end if;

  update public.site_content
  set school_name=case when p_content ? 'school_name' then nullif(btrim(p_content->>'school_name'),'') else school_name end,
      school_name_en=case when p_content ? 'school_name_en' then nullif(btrim(p_content->>'school_name_en'),'') else school_name_en end,
      tagline=case when p_content ? 'tagline' then nullif(btrim(p_content->>'tagline'),'') else tagline end,
      about_text=case when p_content ? 'about_text' then nullif(btrim(p_content->>'about_text'),'') else about_text end,
      mission=case when p_content ? 'mission' then nullif(btrim(p_content->>'mission'),'') else mission end,
      founded_year=case when p_content ? 'founded_year' then nullif(btrim(p_content->>'founded_year'),'') else founded_year end,
      address=case when p_content ? 'address' then nullif(btrim(p_content->>'address'),'') else address end,
      city=case when p_content ? 'city' then nullif(btrim(p_content->>'city'),'') else city end,
      phone=case when p_content ? 'phone' then nullif(btrim(p_content->>'phone'),'') else phone end,
      whatsapp=case when p_content ? 'whatsapp' then nullif(btrim(p_content->>'whatsapp'),'') else whatsapp end,
      email=case when p_content ? 'email' then nullif(lower(btrim(p_content->>'email')),'') else email end,
      programs=v_programs,
      pillars=v_pillars,
      stats=v_stats,
      staff=v_staff,
      gallery=v_gallery,
      hero_photos=v_hero_photos,
      hero_url=case when p_content ? 'hero_url' then nullif(btrim(p_content->>'hero_url'),'') else hero_url end,
      logo_url=case when p_content ? 'logo_url' then nullif(btrim(p_content->>'logo_url'),'') else logo_url end,
      theme=v_theme,
      primary_color=lower(v_color),
      published_at=now(),
      updated_at=now()
  where id='main'
  returning * into v_saved;

  if v_saved.school_name is null or v_saved.school_name_en is null then
    raise exception 'Le nom de l’école est obligatoire' using errcode='22023';
  end if;

  perform private.write_audit_event(
    v_actor_id,v_actor_name,'site_content_updated',
    jsonb_build_object('published_at',v_saved.published_at),
    'main'
  );

  return jsonb_build_object('ok',true,'code','SITE_CONTENT_SAVED','content',to_jsonb(v_saved));
end;
$$;

revoke all on function public.save_site_content(jsonb) from public;
revoke all on function public.save_site_content(jsonb) from anon;
grant execute on function public.save_site_content(jsonb) to authenticated;
grant execute on function public.save_site_content(jsonb) to service_role;

comment on table public.site_content is
  'Single-school public website content. Anonymous users can read the main row; only Direction 1 can write through save_site_content.';
comment on function public.save_site_content(jsonb) is
  'Direction 1-only website publishing contract. Media fields contain HTTPS URLs, normally Cloudflare R2 public delivery URLs.';
