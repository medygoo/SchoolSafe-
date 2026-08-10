-- SchoolSafe VPS baseline - 02a private tables
-- Structures uniquement : defaults, contraintes, RLS et grants arrivent plus tard.

BEGIN;

CREATE TABLE private.account_invitations (
  email text NOT NULL,
  full_name text NOT NULL,
  role text NOT NULL,
  invited_at timestamp with time zone NOT NULL,
  expires_at timestamp with time zone NOT NULL,
  accepted_at timestamp with time zone,
  auth_user_id uuid,
  id uuid NOT NULL,
  app_user_id text,
  invited_by text
);

CREATE TABLE private.notification_push_outbox (
  id text NOT NULL,
  notification_id text NOT NULL,
  recipient_user_id text NOT NULL,
  device_id text NOT NULL,
  provider text NOT NULL,
  payload jsonb NOT NULL,
  status text NOT NULL,
  attempts integer NOT NULL,
  next_attempt_at timestamp with time zone NOT NULL,
  lease_until timestamp with time zone,
  last_error text,
  provider_message_id text,
  created_at timestamp with time zone NOT NULL,
  updated_at timestamp with time zone NOT NULL,
  sent_at timestamp with time zone
);

CREATE TABLE private.parent_phone_access_requests (
  id uuid NOT NULL,
  secret uuid NOT NULL,
  app_user_id text NOT NULL,
  phone text NOT NULL,
  action text NOT NULL,
  requested_by text NOT NULL,
  status text NOT NULL,
  auth_user_id uuid,
  password_fingerprint text,
  created_at timestamp with time zone NOT NULL,
  expires_at timestamp with time zone NOT NULL,
  ready_at timestamp with time zone,
  completed_at timestamp with time zone,
  failed_at timestamp with time zone,
  failure_code text
);

CREATE TABLE private.qr_keys (
  id text NOT NULL,
  secret bytea NOT NULL,
  created_at timestamp with time zone NOT NULL
);

CREATE TABLE private.role_test_runs (
  id uuid NOT NULL,
  test_name text NOT NULL,
  started_at timestamp with time zone NOT NULL,
  finished_at timestamp with time zone,
  passed boolean,
  summary jsonb NOT NULL
);

CREATE TABLE private.school_counters (
  counter_key text NOT NULL,
  counter_value bigint NOT NULL,
  updated_at timestamp with time zone NOT NULL
);

CREATE TABLE private.school_login_rate_limits (
  key_hash text NOT NULL,
  window_started_at timestamp with time zone NOT NULL,
  attempts integer NOT NULL,
  blocked_until timestamp with time zone,
  updated_at timestamp with time zone NOT NULL
);

CREATE TABLE private.student_exit_notification_outbox (
  id text NOT NULL,
  exit_event_id text NOT NULL,
  recipient_user_id text NOT NULL,
  notification_type text NOT NULL,
  channel text NOT NULL,
  recipient_address_snapshot text,
  payload jsonb NOT NULL,
  status text NOT NULL,
  attempts integer NOT NULL,
  last_error text,
  created_at timestamp with time zone NOT NULL,
  sent_at timestamp with time zone
);

COMMIT;
