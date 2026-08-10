-- SchoolSafe VPS baseline - 04j administrative/settings/site RPCs

BEGIN;

CREATE OR REPLACE FUNCTION public.create_administrative_document(p_document_type_id text, p_title text, p_document_number text DEFAULT NULL::text, p_document_date date DEFAULT NULL::date, p_period_start date DEFAULT NULL::date, p_period_end date DEFAULT NULL::date, p_provider text DEFAULT NULL::text, p_amount numeric DEFAULT NULL::numeric, p_currency text DEFAULT 'USD'::text, p_notes text DEFAULT NULL::text, p_school_year text DEFAULT NULL::text, p_confidentiality text DEFAULT 'administrative'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_doc public.administrative_documents;
  v_year text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  v_year := coalesce(nullif(btrim(p_school_year),''), private.current_school_year());
  if v_year !~ '^\d{4}-\d{4}$' then raise exception 'Invalid school year'; end if;
  insert into public.administrative_documents(document_type_id,title,document_number,document_date,period_start,period_end,provider,amount,currency,notes,school_year,confidentiality,created_by)
  values(p_document_type_id,btrim(p_title),nullif(btrim(p_document_number),''),p_document_date,p_period_start,p_period_end,nullif(btrim(p_provider),''),p_amount,upper(coalesce(nullif(btrim(p_currency),''),'USD')),nullif(btrim(p_notes),''),v_year,p_confidentiality,private.current_app_user_id())
  returning * into v_doc;
  return to_jsonb(v_doc);
end;
$function$;

CREATE OR REPLACE FUNCTION public.archive_administrative_document(p_document_id text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.set_administrative_document_archive_state(p_document_id,true) $function$;

CREATE OR REPLACE FUNCTION public.restore_administrative_document(p_document_id text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.set_administrative_document_archive_state(p_document_id,false) $function$;

CREATE OR REPLACE FUNCTION public.get_archive_summary()
 RETURNS TABLE(academic_year text, file_count bigint, total_bytes bigint, archived_count bigint, active_count bigint)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
begin
  if private.current_app_role() <> 'direction' then raise exception 'Accès refusé' using errcode = '42501'; end if;
  return query
  select sf.academic_year,count(*)::bigint,coalesce(sum(sf.size_bytes), 0)::bigint,
    count(*) filter (where sf.archived_at is not null)::bigint,
    count(*) filter (where sf.archived_at is null)::bigint
  from public.school_files sf
  where sf.deleted_at is null
  group by sf.academic_year
  order by sf.academic_year desc;
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_safe_settings()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  s public.settings%rowtype;
  r text := private.current_app_role();
begin
  if r is null then raise exception 'Session inactive' using errcode = '42501'; end if;
  select * into s from public.settings order by id limit 1;
  if not found then return '{}'::jsonb; end if;
  return jsonb_strip_nulls(jsonb_build_object(
    'id', s.id,'year', s.year,'school', s.school,'toggles', s.toggles,'horaires', s.horaires,
    'lockdown', s.lockdown,'retention', s.retention,'trimlocks', s.trimlocks,
    'currenttrimestre', s.currenttrimestre,'school_type', s.school_type,
    'session_timeout_min', s.session_timeout_min,'rattrapage_rate', s.rattrapage_rate,
    'rattrapage_threshold', s.rattrapage_threshold,
    'fees', case when r in ('direction', 'direction3', 'parent') then s.fees else null end,
    'feescontrol', case when r in ('direction', 'direction3', 'parent') then s.feescontrol else null end
  ));
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_site_content(p_content jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  if private.current_app_role()<>'direction' then raise exception 'Accès refusé' using errcode='42501'; end if;
  if p_content is null or jsonb_typeof(p_content)<>'object' then raise exception 'Contenu invalide' using errcode='22023'; end if;
  select name into v_actor_name from public.users where id=v_actor_id and status='active';
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
  if v_theme not in ('dark','light','custom') then raise exception 'Thème invalide' using errcode='22023'; end if;
  if v_color !~ '^#[0-9A-Fa-f]{6}$' then raise exception 'Couleur invalide' using errcode='22023'; end if;
  if exists(select 1 from jsonb_array_elements_text(v_hero_photos) x(url) where url !~ '^https://') then
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
      programs=v_programs,pillars=v_pillars,stats=v_stats,staff=v_staff,gallery=v_gallery,hero_photos=v_hero_photos,
      hero_url=case when p_content ? 'hero_url' then nullif(btrim(p_content->>'hero_url'),'') else hero_url end,
      logo_url=case when p_content ? 'logo_url' then nullif(btrim(p_content->>'logo_url'),'') else logo_url end,
      theme=v_theme,primary_color=lower(v_color),published_at=now(),updated_at=now()
  where id='main' returning * into v_saved;

  if v_saved.school_name is null or v_saved.school_name_en is null then raise exception 'Le nom de l’école est obligatoire' using errcode='22023'; end if;
  perform private.write_audit_event(v_actor_id,v_actor_name,'site_content_updated',jsonb_build_object('published_at',v_saved.published_at),'main');
  return jsonb_build_object('ok',true,'code','SITE_CONTENT_SAVED','content',to_jsonb(v_saved));
end;
$function$;

CREATE OR REPLACE FUNCTION public.schoolsafe_health_check()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select jsonb_build_object('ok', true,'service', 'schoolsafe-supabase','checked_at', timezone('Africa/Kinshasa', now()));
$function$;

COMMIT;
