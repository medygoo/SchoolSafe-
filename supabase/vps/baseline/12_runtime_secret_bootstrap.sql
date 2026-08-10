-- SchoolSafe VPS baseline - 12 runtime secret bootstrap
-- IMPORTANT: this file contains NO secret value.
-- The QR signing key is generated cryptographically inside PostgreSQL on the VPS.

BEGIN;

INSERT INTO private.qr_keys(id,secret,created_at)
VALUES('student_daily_v1',extensions.gen_random_bytes(32),now())
ON CONFLICT (id) DO NOTHING;

-- Legacy settings.qr_secret and settings.msg_enc_key are intentionally left NULL.
-- No current SchoolSafe public/private function references those legacy fields.

COMMIT;
