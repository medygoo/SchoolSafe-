-- SchoolSafe VPS baseline - 02d public tables N-R
-- Structures uniquement : defaults, contraintes, index, triggers et RLS arrivent plus tard.

BEGIN;

CREATE TABLE public.notifs (
  id text NOT NULL,
  uid text,
  "from" text,
  msg text,
  type text,
  date text,
  "time" text,
  read boolean NOT NULL,
  devoir_id text,
  status text,
  to_role text,
  by text,
  wa_links jsonb,
  receipt jsonb,
  category text NOT NULL,
  title text,
  student_id text,
  action_url text,
  priority text NOT NULL,
  privacy_level text NOT NULL,
  requires_ack boolean NOT NULL,
  created_at timestamp with time zone NOT NULL,
  created_by_user_id text,
  created_by_name text,
  created_by_role text,
  opened_at timestamp with time zone,
  read_at timestamp with time zone,
  acknowledged_at timestamp with time zone,
  archived_at timestamp with time zone,
  source_type text,
  source_id text,
  dedupe_key text,
  data jsonb NOT NULL,
  push_requested boolean NOT NULL
);

CREATE TABLE public.palmares_publication_history (
  id uuid NOT NULL,
  publication_id text NOT NULL,
  cid text NOT NULL,
  year text NOT NULL,
  trimestre text NOT NULL,
  version integer NOT NULL,
  snapshot jsonb NOT NULL,
  status text NOT NULL,
  changed_by text,
  change_reason text,
  archived_at timestamp with time zone NOT NULL
);

CREATE TABLE public.palmares_publications (
  id text NOT NULL,
  cid text NOT NULL,
  year text NOT NULL,
  trimestre text NOT NULL,
  status text NOT NULL,
  formula_version text NOT NULL,
  snapshot jsonb NOT NULL,
  version integer NOT NULL,
  published_by text,
  published_by_name text,
  published_by_role text,
  published_at timestamp with time zone,
  correction_reason text,
  updated_at timestamp with time zone NOT NULL
);

CREATE TABLE public.payment_access_exceptions (
  id text NOT NULL,
  sid text NOT NULL,
  starts_at timestamp with time zone NOT NULL,
  ends_at timestamp with time zone NOT NULL,
  reason text NOT NULL,
  granted_by text NOT NULL,
  revoked_at timestamp with time zone,
  revoked_by text,
  revoke_reason text,
  created_at timestamp with time zone NOT NULL
);

CREATE TABLE public.payment_allocations (
  id text NOT NULL,
  transaction_id text NOT NULL,
  obligation_id text NOT NULL,
  amount numeric(14,2) NOT NULL,
  created_at timestamp with time zone NOT NULL
);

CREATE TABLE public.payment_receipt_counters (
  school_year text NOT NULL,
  last_no bigint NOT NULL,
  updated_at timestamp with time zone NOT NULL
);

CREATE TABLE public.payment_scan_log (
  id text NOT NULL,
  sid text NOT NULL,
  checked_by text,
  checked_role text NOT NULL,
  source text NOT NULL,
  result_code text NOT NULL,
  details jsonb NOT NULL,
  created_at timestamp with time zone NOT NULL
);

CREATE TABLE public.payment_transactions (
  id text NOT NULL,
  sid text NOT NULL,
  school_year text NOT NULL,
  amount numeric(14,2) NOT NULL,
  currency text NOT NULL,
  payment_date date NOT NULL,
  payment_method text NOT NULL,
  external_reference text,
  receipt_no text NOT NULL,
  status text NOT NULL,
  recorded_by text NOT NULL,
  note text,
  created_at timestamp with time zone NOT NULL,
  updated_at timestamp with time zone NOT NULL,
  reversed_at timestamp with time zone,
  reversed_by text,
  reversal_reason text,
  recorded_by_name text NOT NULL,
  recorded_by_role text NOT NULL,
  reversed_by_name text,
  reversed_by_role text
);

CREATE TABLE public.payments (
  id text NOT NULL,
  sid text,
  t text,
  paid boolean,
  date text,
  by text,
  note text,
  recorded_by text,
  recorded_by_name text,
  recorded_by_role text,
  recorded_at timestamp with time zone
);

CREATE TABLE public.preinscriptions (
  id text NOT NULL,
  statut text NOT NULL,
  created_at timestamp with time zone NOT NULL,
  expire_le date NOT NULL,
  nom text NOT NULL,
  sexe text NOT NULL,
  dob date NOT NULL,
  lieu_naissance text,
  classe text NOT NULL,
  ecole_provenance text,
  nom_papa text,
  nom_maman text,
  telephone text NOT NULL,
  telephone2 text,
  adresse text,
  email text,
  blood_group text,
  urgence text,
  medical_notes text,
  tutelle text NOT NULL,
  autorisees jsonb NOT NULL,
  motif_refus text,
  traite_par text,
  traite_par_nom text,
  traite_le timestamp with time zone,
  student_id text,
  parent_id text
);

CREATE TABLE public.prevision_matiere (
  id text NOT NULL,
  cid text,
  matiere text,
  lang text,
  trimestre text,
  programme text,
  pourcentage numeric,
  validated boolean,
  by text
);

CREATE TABLE public.profiles (
  id uuid NOT NULL,
  email text,
  full_name text NOT NULL,
  role text NOT NULL,
  status text NOT NULL,
  phone text,
  avatar_path text,
  created_at timestamp with time zone NOT NULL,
  updated_at timestamp with time zone NOT NULL
);

CREATE TABLE public.push_subscriptions (
  id text NOT NULL,
  uid text NOT NULL,
  endpoint text,
  auth text,
  p256dh text,
  ua text,
  updated_at timestamp with time zone NOT NULL,
  provider text NOT NULL,
  token text,
  platform text NOT NULL,
  app_instance_id text,
  device_label text,
  active boolean NOT NULL,
  created_at timestamp with time zone NOT NULL,
  last_seen_at timestamp with time zone NOT NULL,
  last_success_at timestamp with time zone,
  disabled_at timestamp with time zone,
  disabled_reason text,
  failure_count integer NOT NULL
);

CREATE TABLE public.rattrapages (
  id text NOT NULL,
  sid text,
  teacher_id text,
  matiere text,
  motif text,
  date text,
  "time" text,
  status text,
  amount numeric,
  paid boolean,
  score numeric,
  auto_triggered boolean,
  trimestre text,
  validated_by text,
  validated_date text,
  d2_validated boolean,
  note text,
  session_date text,
  session_time text,
  session_place text,
  done boolean,
  done_date text,
  done_note text,
  archived boolean,
  payment_signaled boolean,
  reminder_sent boolean,
  validated_by_d2 text,
  validated_by_d2_name text,
  paid_date text
);

COMMIT;
