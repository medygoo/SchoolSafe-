-- P0-8 — vérification structurelle après application de la migration.
-- Lecture seule. Ne retourne aucune valeur de secret.

-- 1. Table + RLS
select
  c.relname as table_name,
  c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relname='student_cards';

-- 2. Colonnes attendues
select column_name,data_type,is_nullable
from information_schema.columns
where table_schema='public' and table_name='student_cards'
order by ordinal_position;

-- 3. Une seule carte active / élève / année
select indexname,indexdef
from pg_indexes
where schemaname='public'
  and tablename='student_cards'
  and indexname='student_cards_one_active_per_student_year_idx';

-- 4. RLS lecture par rôle applicatif
select policyname,cmd,roles,qual,with_check
from pg_policies
where schemaname='public' and tablename='student_cards'
order by policyname;

-- 5. Aucun droit direct d'écriture pour authenticated/anon
select grantee,privilege_type
from information_schema.role_table_grants
where table_schema='public'
  and table_name='student_cards'
  and grantee in ('anon','authenticated')
order by grantee,privilege_type;

-- Résultat attendu : authenticated = SELECT uniquement ; anon = aucune ligne.

-- 6. RPC P0-8 présentes
select n.nspname as schema_name,p.proname,pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in (
    'issue_student_card',
    'declare_student_card_lost',
    'revoke_student_card',
    'count_student_card_print',
    'verify_student_card_qr'
  )
order by p.proname;

-- 7. Clé carte présente — longueur seulement, JAMAIS la valeur.
select id,octet_length(secret) as secret_bytes,created_at
from private.qr_keys
where id='student_card_v1';

-- Résultat attendu : 1 ligne, secret_bytes = 32.

-- 8. Le secret historique settings.qr_secret n'est pas une dépendance du contrat public.
select position('qr_secret' in pg_get_functiondef(p.oid))>0 as mentions_settings_qr_secret,
       p.proname
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in ('issue_student_card','verify_student_card_qr')
order by p.proname;

-- Résultat attendu : false pour les deux fonctions.

-- 9. Durcissements Sortie : politique enseignant limitée aux classes.
select policyname,qual
from pg_policies
where schemaname='public'
  and tablename='student_exit_events'
  and policyname='student_exit_events_read';

-- 10. Le contexte pickup n'utilise plus private.can_scan() (qui inclut la Caisse).
select p.proname,
       position('can_read_student_pickup_context' in pg_get_functiondef(p.oid))>0 as uses_dedicated_guard,
       position('can_scan()' in pg_get_functiondef(p.oid))>0 as still_uses_can_scan
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname='get_student_pickup_context';

-- Résultat attendu : uses_dedicated_guard=true, still_uses_can_scan=false.

-- 11. L'état de sortie ne sérialise plus la ligne complète.
select p.proname,
       position('to_jsonb(e)' in pg_get_functiondef(p.oid))>0 as leaks_full_event_row
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname='get_student_exit_status';

-- Résultat attendu : false.

-- 12. Aucun secret brut dans les vues/fonctions publiques P0-8.
select count(*) as suspicious_public_secret_references
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and p.proname in ('issue_student_card','verify_student_card_qr')
  and pg_get_functiondef(p.oid) ilike '%select secret%from public.settings%';

-- Résultat attendu : 0.
