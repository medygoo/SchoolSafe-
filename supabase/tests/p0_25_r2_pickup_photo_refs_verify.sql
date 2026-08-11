-- P0-25 — vérification LECTURE SEULE après application sur une base jetable.
-- Ne crée ni utilisateur, ni personne autorisée, ni fichier.

-- 1. Colonnes R2 permanentes.
select
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='aps' and column_name='photo_file_id' and udt_name='uuid') as aps_portrait_file_id,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='aps' and column_name='photo_full_body_file_id' and udt_name='uuid') as aps_full_body_file_id,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='users' and column_name='photo_file_id' and udt_name='uuid') as parent_portrait_file_id,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='users' and column_name='identity_full_body_photo_file_id' and udt_name='uuid') as parent_full_body_file_id,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='student_exit_events' and column_name='escort_photo_portrait_file_id_snapshot' and udt_name='uuid') as exit_portrait_snapshot,
  exists(select 1 from information_schema.columns where table_schema='public' and table_name='scan_log' and column_name='escort_photo_portrait_file_id' and udt_name='uuid') as scan_portrait_snapshot;

-- 2. Les FKs empêchent de pointer vers un fichier inexistant.
select conrelid::regclass::text as table_name,conname,pg_get_constraintdef(oid) as definition
from pg_constraint
where conname in (
  'aps_photo_file_id_fkey',
  'aps_photo_full_body_file_id_fkey',
  'users_photo_file_id_fkey',
  'users_identity_full_body_photo_file_id_fkey',
  'student_exit_events_escort_portrait_file_fkey',
  'student_exit_events_escort_full_body_file_fkey',
  'scan_log_escort_portrait_file_fkey',
  'scan_log_escort_full_body_file_fkey'
)
order by table_name,conname;

-- 3. Une personne active accepte désormais URL historique OU file_id.
select
  position('photo_file_id' in pg_get_constraintdef(oid))>0 as active_check_has_portrait_file_id,
  position('photo_full_body_file_id' in pg_get_constraintdef(oid))>0 as active_check_has_full_body_file_id
from pg_constraint
where conrelid='public.aps'::regclass
  and conname='aps_active_requires_approval_check';

-- 4. RPCs et helper.
select
  to_regprocedure('public.reserve_authorized_pickup_person(jsonb)') is not null as has_reservation_rpc,
  to_regprocedure('public.save_authorized_pickup_person(jsonb)') is not null as has_save_rpc,
  to_regprocedure('public.save_primary_parent_pickup_identity(text,text,text,text,text)') is not null as has_parent_identity_rpc,
  to_regprocedure('public.get_student_pickup_context(text)') is not null as has_pickup_context,
  to_regprocedure('private.pickup_photo_file_status(uuid,text,text)') is not null as has_file_validator;

-- 5. Permissions : la réservation est authentifiée mais jamais anonyme.
select
  has_function_privilege('anon','public.reserve_authorized_pickup_person(jsonb)','EXECUTE') as anon_can_reserve,
  has_function_privilege('authenticated','public.reserve_authorized_pickup_person(jsonb)','EXECUTE') as authenticated_can_call_guarded_reservation;
-- Attendu : false / true. Le rôle est encore contrôlé dans la fonction.

-- 6. Contrôle de portée : la Caisse ne doit plus entrer par can_scan().
select
  position('can_confirm_student_exit' in pg_get_functiondef('public.get_student_pickup_context(text)'::regprocedure))>0 as pickup_context_uses_exit_role_gate,
  position('can_scan()' in pg_get_functiondef('public.get_student_pickup_context(text)'::regprocedure))=0 as pickup_context_does_not_use_generic_scan_gate,
  position('can_confirm_student_exit' in pg_get_functiondef('public.get_scanner_aps()'::regprocedure))>0 as scanner_aps_uses_exit_role_gate;

-- 7. Le contexte expose des file_id mais ne génère aucune URL signée.
select
  position('photo_portrait_file_id' in pg_get_functiondef('public.get_student_pickup_context(text)'::regprocedure))>0 as context_has_portrait_file_id,
  position('photo_full_body_file_id' in pg_get_functiondef('public.get_student_pickup_context(text)'::regprocedure))>0 as context_has_full_body_file_id,
  position('http' in lower(pg_get_functiondef('public.get_student_pickup_context(text)'::regprocedure)))=0 as context_does_not_build_urls;

-- 8. Snapshots permanents.
select
  exists(select 1 from pg_trigger where tgrelid='public.student_exit_events'::regclass and tgname='trg_snapshot_exit_pickup_photo_file_ids' and not tgisinternal) as exit_snapshot_trigger,
  exists(select 1 from pg_trigger where tgrelid='public.scan_log'::regclass and tgname='trg_snapshot_scan_log_pickup_photo_file_ids' and not tgisinternal) as scan_snapshot_trigger;

-- 9. Aucun résumé sensible : seulement des compteurs de références R2.
select
  count(*) filter(where photo_file_id is not null) as authorized_people_with_r2_portrait,
  count(*) filter(where photo_full_body_file_id is not null) as authorized_people_with_r2_full_body
from public.aps;

select
  count(*) filter(where photo_file_id is not null) as users_with_r2_portrait,
  count(*) filter(where identity_full_body_photo_file_id is not null) as users_with_r2_full_body
from public.users;
