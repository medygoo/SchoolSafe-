-- SchoolSafe VPS baseline - 02e public tables S-Z
-- Structures uniquement : defaults, contraintes, index, triggers et RLS arrivent plus tard.

BEGIN;

CREATE TABLE public.salaries (
  id text NOT NULL,
  teacher_id text,
  month text,
  amount numeric,
  bonus numeric,
  rat_prime numeric,
  deductions numeric,
  adv_total numeric,
  net numeric,
  paid boolean,
  paid_date text,
  notes text,
  by text,
  updated text,
  direct_primes_total numeric,
  person_name text,
  person_role text,
  payment_method text,
  user_id text
);

CREATE TABLE public.sanctions (
  id text NOT NULL,
  sid text,
  type text,
  description text,
  date text,
  by text,
  duration_days numeric,
  return_date text,
  lifted boolean,
  parent_notified boolean,
  reason text
);

CREATE TABLE public.scan_log (
  id text NOT NULL,
  sid text,
  type text,
  status text,
  date text,
  "time" text,
  name text,
  label text,
  by_uid text,
  by_name text,
  description text,
  photo_thumb text,
  note text,
  by_role text,
  manual boolean,
  escort_kind text,
  escort_id text,
  escort_name text,
  created_at timestamp with time zone NOT NULL,
  exit_event_id text,
  prepared_by_uid text,
  prepared_by_name text,
  prepared_by_role text,
  validated_by_uid text,
  validated_by_name text,
  validated_by_role text,
  gate_label text,
  preparation_time timestamp with time zone,
  gate_scan_time timestamp with time zone,
  validation_time timestamp with time zone,
  escort_relation text,
  escort_photo_portrait text,
  escort_photo_full_body text,
  escort_id_doc_type text,
  escort_id_doc_last4 text
);

CREATE TABLE public.school_files (
  id uuid NOT NULL,
  owner_type text NOT NULL,
  owner_id text NOT NULL,
  category text NOT NULL,
  storage_path text NOT NULL,
  original_name text NOT NULL,
  mime_type text NOT NULL,
  size_bytes bigint NOT NULL,
  academic_year text NOT NULL,
  uploaded_by uuid,
  checksum_sha256 text,
  metadata jsonb NOT NULL,
  created_at timestamp with time zone NOT NULL,
  archived_at timestamp with time zone,
  idempotency_key text,
  payment_transaction_id text,
  deleted_at timestamp with time zone,
  deleted_by uuid,
  display_name text,
  cahier_prep_id text,
  administrative_document_id text,
  archived_by uuid,
  restored_at timestamp with time zone,
  restored_by uuid,
  source_original_name text,
  source_mime_type text,
  source_size_bytes bigint,
  source_width integer,
  source_height integer,
  processed_width integer,
  processed_height integer,
  compression_quality smallint,
  compression_profile text,
  optimized boolean NOT NULL,
  optimization_version smallint,
  compression_saved_bytes bigint GENERATED ALWAYS AS (
    CASE WHEN source_size_bytes IS NULL THEN 0::bigint
         ELSE GREATEST(source_size_bytes - size_bytes, 0::bigint)
    END
  ) STORED,
  compression_ratio_pct numeric(6,2) GENERATED ALWAYS AS (
    CASE WHEN source_size_bytes IS NULL OR source_size_bytes <= 0 THEN 0::numeric
         ELSE round((GREATEST(source_size_bytes - size_bytes, 0::bigint)::numeric / source_size_bytes::numeric) * 100::numeric, 2)
    END
  ) STORED,
  uploaded_by_app_user_id text NOT NULL,
  uploaded_by_name text NOT NULL,
  uploaded_by_role text NOT NULL
);

CREATE TABLE public.school_profile (
  id smallint NOT NULL,
  legal_name text NOT NULL,
  display_name text NOT NULL,
  slogan text,
  locale text NOT NULL,
  timezone text NOT NULL,
  updated_at timestamp with time zone NOT NULL
);

CREATE TABLE public.settings (
  id text NOT NULL,
  currenttrimestre text,
  feescontrol jsonb,
  fees jsonb,
  retention jsonb,
  toggles jsonb,
  trimlocks jsonb,
  school jsonb,
  year text,
  horaires jsonb,
  session_timeout_min numeric,
  _lastcleanup text,
  lockdown boolean,
  budget_depenses numeric,
  school_type text,
  rattrapage_threshold numeric,
  rattrapage_rate numeric,
  opening_cash numeric,
  opening_bank numeric,
  staff_postes jsonb,
  archived_years jsonb,
  year_locked text,
  year_locked_by text,
  year_locked_date text,
  qr_secret text,
  qr_secret_date text,
  msg_enc_key text,
  _last_recu_no numeric,
  vapid_public_key text,
  operator_wa text
);

CREATE TABLE public.site_content (
  id text NOT NULL,
  school_name text NOT NULL,
  school_name_en text NOT NULL,
  tagline text,
  about_text text,
  mission text,
  founded_year text,
  address text,
  city text,
  phone text,
  whatsapp text,
  email text,
  programs jsonb NOT NULL,
  pillars jsonb NOT NULL,
  stats jsonb NOT NULL,
  staff jsonb NOT NULL,
  gallery jsonb NOT NULL,
  hero_photos jsonb NOT NULL,
  hero_url text,
  logo_url text,
  theme text NOT NULL,
  primary_color text NOT NULL,
  published_at timestamp with time zone,
  updated_at timestamp with time zone NOT NULL
);

CREATE TABLE public.student_exit_events (
  id text NOT NULL,
  sid text NOT NULL,
  student_name_snapshot text NOT NULL,
  student_class_id_snapshot text,
  school_date date NOT NULL,
  status text NOT NULL,
  quick_flow boolean NOT NULL,
  prepared_at timestamp with time zone NOT NULL,
  expires_at timestamp with time zone NOT NULL,
  prepared_by_user_id text NOT NULL,
  prepared_by_name text NOT NULL,
  prepared_by_role text NOT NULL,
  preparation_gate text,
  parent_id_snapshot text NOT NULL,
  parent_name_snapshot text NOT NULL,
  parent_phone_snapshot text,
  parent_email_snapshot text,
  gate_scanned_at timestamp with time zone,
  gate_scanned_by_user_id text,
  gate_scanned_by_name text,
  gate_scanned_by_role text,
  gate_label text,
  teacher_gate_reason text,
  manual boolean NOT NULL,
  escort_kind text,
  escort_id_snapshot text,
  escort_name_snapshot text,
  escort_relation_snapshot text,
  escort_phone_snapshot text,
  escort_photo_portrait_snapshot text,
  escort_photo_full_body_snapshot text,
  escort_id_doc_type_snapshot text,
  escort_id_doc_last4_snapshot text,
  validated_at timestamp with time zone,
  validated_by_user_id text,
  validated_by_name text,
  validated_by_role text,
  decision_note text,
  finalized_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL,
  updated_at timestamp with time zone NOT NULL
);

CREATE TABLE public.student_fee_obligations (
  id text NOT NULL,
  sid text NOT NULL,
  fee_type_id text NOT NULL,
  school_year text NOT NULL,
  label text NOT NULL,
  installment_no integer NOT NULL,
  amount_due numeric(14,2) NOT NULL,
  currency text NOT NULL,
  due_date date,
  active boolean NOT NULL,
  created_by text,
  created_at timestamp with time zone NOT NULL,
  updated_at timestamp with time zone NOT NULL
);

CREATE TABLE public.student_primary_parent_history (
  id text NOT NULL,
  sid text NOT NULL,
  student_name_snapshot text NOT NULL,
  old_parent_id text,
  old_parent_name_snapshot text,
  new_parent_id text,
  new_parent_name_snapshot text,
  changed_by_user_id text,
  changed_by_name text NOT NULL,
  changed_by_role text NOT NULL,
  changed_at timestamp with time zone NOT NULL
);

CREATE TABLE public.students (
  id text NOT NULL,
  name text,
  mat text,
  cid text,
  pid text,
  dob text,
  photo text,
  adresse text,
  nom_papa text,
  nom_maman text,
  access_blocked boolean,
  blocked boolean,
  created_by text,
  created_by_name text,
  access_parent boolean NOT NULL,
  archived boolean NOT NULL,
  archived_at text,
  card_printed boolean,
  card_print_date text,
  card_print_count numeric,
  diplome boolean,
  created_at text,
  lieu_naissance text,
  num_inscription text,
  may_leave_alone boolean NOT NULL,
  leave_alone_until date,
  leave_alone_authorized_by text,
  leave_alone_authorized_at timestamp with time zone,
  sexe text,
  ecole_provenance text,
  tutelle_principale text
);

CREATE TABLE public.teacher_absences (
  id text NOT NULL,
  uid text,
  date text,
  reason text,
  status text,
  approved_by text,
  cid text,
  name text,
  "time" text,
  motif text,
  duree text
);

CREATE TABLE public.teacher_notes (
  id text NOT NULL,
  content text,
  date text,
  "time" text,
  sid text,
  expires_at text,
  by text,
  cid text
);

CREATE TABLE public.tenafep (
  id text NOT NULL,
  sid text,
  enafep_code text,
  result text,
  score numeric,
  registration_num text,
  notes text,
  year text,
  registered boolean,
  updated text
);

CREATE TABLE public.timetables (
  id text NOT NULL,
  cid text,
  day text,
  period numeric,
  matiere text,
  teacher_id text
);

CREATE TABLE public.users (
  id text NOT NULL,
  auth_user_id uuid,
  email text,
  name text NOT NULL,
  role text NOT NULL,
  initials text,
  phone text,
  photo_url text,
  status text NOT NULL,
  created_at timestamp with time zone NOT NULL,
  invitation_sent_at timestamp with time zone,
  updated_at timestamp with time zone NOT NULL,
  access_channel text NOT NULL,
  must_change_password boolean NOT NULL,
  temporary_access_expires_at timestamp with time zone,
  phone_access_updated_at timestamp with time zone,
  login_email_enabled boolean NOT NULL,
  login_phone_enabled boolean NOT NULL,
  contact_setup_complete boolean GENERATED ALWAYS AS (((email IS NOT NULL) AND (phone IS NOT NULL))) STORED,
  access_removed_at timestamp with time zone,
  access_removed_by text,
  access_removal_reason text,
  removed_auth_user_id uuid,
  identity_full_body_photo_url text,
  identity_document_type text,
  identity_document_last4 text,
  access_ready boolean NOT NULL,
  access_block_reason text
);

CREATE TABLE public.versements (
  id text NOT NULL,
  sid text,
  student_name text,
  mat text,
  fee_type_id text,
  fee_label text,
  compte_cat text,
  trimestre text,
  montant numeric,
  motif text,
  note text,
  payment_method text,
  mvt_type text,
  date text,
  "time" text,
  by text,
  by_name text,
  recu_no text,
  uid_perso text,
  annulled boolean,
  annulled_by text,
  annulled_by_name text,
  annulled_date text,
  annulled_reason text
);

COMMIT;
