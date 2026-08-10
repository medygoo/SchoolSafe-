-- SchoolSafe VPS Supabase - PRECHECK LECTURE SEULE
-- Aucune modification de donnees ou de configuration.
-- Objectif : confirmer que le Supabase auto-heberge peut recevoir le baseline SchoolSafe.

select now() as checked_at;
select version() as postgres_version;
select current_database() as database_name, current_user as database_user;
select pg_size_pretty(pg_database_size(current_database())) as database_size;

-- Schemas indispensables Supabase + SchoolSafe
select nspname as schema_name
from pg_namespace
where nspname in ('public','private','auth','storage','realtime','extensions')
order by nspname;

-- Roles attendus par les policies / RPC SchoolSafe
select rolname, rolcanlogin, rolsuper
from pg_roles
where rolname in ('anon','authenticated','service_role','authenticator','supabase_admin')
order by rolname;

-- Extensions : presence installee et disponibilite serveur
with wanted(name) as (
  values ('pgcrypto'), ('uuid-ossp'), ('pg_stat_statements'), ('pg_net'), ('supabase_vault')
)
select
  w.name,
  e.extversion as installed_version,
  a.default_version as available_default_version,
  case when e.extname is not null then 'installed'
       when a.name is not null then 'available'
       else 'missing' end as state
from wanted w
left join pg_extension e on e.extname = w.name
left join pg_available_extensions a on a.name = w.name
order by w.name;

-- Etat actuel des objets applicatifs sur le VPS avant import
select n.nspname as schema_name,
       count(*) filter (where c.relkind in ('r','p')) as tables,
       count(*) filter (where c.relkind='v') as views,
       count(*) filter (where c.relkind='m') as materialized_views
from pg_class c
join pg_namespace n on n.oid=c.relnamespace
where n.nspname in ('public','private')
group by n.nspname
order by n.nspname;

select n.nspname as schema_name, count(*) as functions
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname in ('public','private') and p.prokind='f'
group by n.nspname
order by n.nspname;

-- RLS : aucune ecriture, juste inventaire
select n.nspname as schema_name, c.relname as table_name, c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid=c.relnamespace
where n.nspname in ('public','private') and c.relkind in ('r','p')
order by n.nspname,c.relname;

-- Valeur de configuration PostgREST si exposee dans PostgreSQL.
-- NULL est acceptable selon le mode de deploiement.
select current_setting('pgrst.db_schemas', true) as postgrest_exposed_schemas;

-- Migrations internes Auth/Storage : compter uniquement, ne jamais les remplacer par celles du Cloud.
select 'auth.schema_migrations' as source, count(*) as migration_rows
from auth.schema_migrations
union all
select 'storage.migrations', count(*)
from storage.migrations;

-- Verification de sante minimale des schemas internes
select to_regclass('auth.users') is not null as auth_users_present,
       to_regclass('storage.objects') is not null as storage_objects_present;

-- Resultat attendu avant import SchoolSafe :
-- 1) auth/storage presentes ;
-- 2) roles anon/authenticated/service_role presents ;
-- 3) pgcrypto disponible (obligatoire pour gen_random_uuid) ;
-- 4) public/private ne doivent pas deja contenir une ancienne installation SchoolSafe non identifiee ;
-- 5) aucune ligne de ce fichier ne doit modifier le VPS.
