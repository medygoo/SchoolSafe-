/*\nSchoolSafe — structural schema snapshot for frontend audit only.\nRange: q to t (exclusive).\nDO NOT EXECUTE. CREATE TABLE and CREATE POLICY statements are inside this comment\nbecause tools/audit-schema.mjs reads structural declarations from SQL text.\nContains no row data, API key, password, project reference, service_role or user identifier.\nPolicy predicates are omitted; operations exposed by pg_policies are recorded.\n\nCREATE TABLE public.rattrapages (
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
-- RLS enabled: true
CREATE POLICY "snapshot_rattrapages_delete" ON public.rattrapages FOR DELETE;
CREATE POLICY "snapshot_rattrapages_insert" ON public.rattrapages FOR INSERT;
CREATE POLICY "snapshot_rattrapages_select" ON public.rattrapages FOR SELECT;
CREATE POLICY "snapshot_rattrapages_update" ON public.rattrapages FOR UPDATE;

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
  payment_method text
);
-- RLS enabled: true
CREATE POLICY "snapshot_salaries_delete" ON public.salaries FOR DELETE;
CREATE POLICY "snapshot_salaries_insert" ON public.salaries FOR INSERT;
CREATE POLICY "snapshot_salaries_select" ON public.salaries FOR SELECT;
CREATE POLICY "snapshot_salaries_update" ON public.salaries FOR UPDATE;

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
-- RLS enabled: true
CREATE POLICY "snapshot_sanctions_delete" ON public.sanctions FOR DELETE;
CREATE POLICY "snapshot_sanctions_insert" ON public.sanctions FOR INSERT;
CREATE POLICY "snapshot_sanctions_select" ON public.sanctions FOR SELECT;
CREATE POLICY "snapshot_sanctions_update" ON public.sanctions FOR UPDATE;

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
  created_at timestamp with time zone NOT NULL
);
-- RLS enabled: true
CREATE POLICY "snapshot_scan_log_delete" ON public.scan_log FOR DELETE;
CREATE POLICY "snapshot_scan_log_insert" ON public.scan_log FOR INSERT;
CREATE POLICY "snapshot_scan_log_select" ON public.scan_log FOR SELECT;
CREATE POLICY "snapshot_scan_log_update" ON public.scan_log FOR UPDATE;

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
  uploaded_by uuid NOT NULL,
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
  compression_saved_bytes bigint,
  compression_ratio_pct numeric(6,2)
);
-- RLS enabled: true
CREATE POLICY "snapshot_school_files_select" ON public.school_files FOR SELECT;

CREATE TABLE public.school_profile (
  id smallint NOT NULL,
  legal_name text NOT NULL,
  display_name text NOT NULL,
  slogan text,
  locale text NOT NULL,
  timezone text NOT NULL,
  updated_at timestamp with time zone NOT NULL
);
-- RLS enabled: true
CREATE POLICY "snapshot_school_profile_select" ON public.school_profile FOR SELECT;
CREATE POLICY "snapshot_school_profile_update" ON public.school_profile FOR UPDATE;

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
-- RLS enabled: true
CREATE POLICY "snapshot_settings_delete" ON public.settings FOR DELETE;
CREATE POLICY "snapshot_settings_insert" ON public.settings FOR INSERT;
CREATE POLICY "snapshot_settings_select" ON public.settings FOR SELECT;
CREATE POLICY "snapshot_settings_update" ON public.settings FOR UPDATE;

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
-- RLS enabled: true
CREATE POLICY "snapshot_site_content_select" ON public.site_content FOR SELECT;

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
-- RLS enabled: true
CREATE POLICY "snapshot_student_fee_obligations_delete" ON public.student_fee_obligations FOR DELETE;
CREATE POLICY "snapshot_student_fee_obligations_insert" ON public.student_fee_obligations FOR INSERT;
CREATE POLICY "snapshot_student_fee_obligations_select" ON public.student_fee_obligations FOR SELECT;
CREATE POLICY "snapshot_student_fee_obligations_update" ON public.student_fee_obligations FOR UPDATE;

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
-- RLS enabled: true
CREATE POLICY "snapshot_students_delete" ON public.students FOR DELETE;
CREATE POLICY "snapshot_students_insert" ON public.students FOR INSERT;
CREATE POLICY "snapshot_students_select" ON public.students FOR SELECT;
CREATE POLICY "snapshot_students_update" ON public.students FOR UPDATE;
*/
