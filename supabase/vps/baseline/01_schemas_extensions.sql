-- SchoolSafe VPS baseline - 01 schemas/extensions
-- A executer uniquement APRES 00_PRECHECK_READONLY.sql et sauvegarde VPS validee.
-- Ce fichier ne touche pas aux schemas internes auth/storage/realtime.

BEGIN;

CREATE SCHEMA IF NOT EXISTS private;
CREATE SCHEMA IF NOT EXISTS extensions;

-- Dependances SchoolSafe reellement utilisees :
--   extensions.digest(...) pour l'authentification telephone / fingerprints
--   extensions.hmac(...)   pour les QR SchoolSafe
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- Les extensions suivantes existent dans l'ancien Cloud mais ne sont pas
-- actuellement requises directement par les fonctions applicatives SchoolSafe :
-- pg_net, supabase_vault, uuid-ossp, pg_stat_statements.
-- Elles ne sont donc PAS forcees ici. Le precheck les inventorie seulement.

COMMIT;
