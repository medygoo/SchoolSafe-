/*\nSchoolSafe — structural schema snapshot for frontend audit only.\nRange: i to q (exclusive).\nDO NOT EXECUTE. CREATE TABLE and CREATE POLICY statements are inside this comment\nbecause tools/audit-schema.mjs reads structural declarations from SQL text.\nContains no row data, API key, password, project reference, service_role or user identifier.\nPolicy predicates are omitted; operations exposed by pg_policies are recorded.\n\nCREATE TABLE public.inscriptions (
  id text NOT NULL,
  nom text,
  prenom text,
  dob text,
  classe text,
  nom_parent text,
  telephone text,
  email text,
  message text,
  date text,
  status text,
  statut text,
  motif_refus text
);
-- RLS enabled: true
CREATE POLICY "snapshot_inscriptions_delete" ON public.inscriptions FOR DELETE;
CREATE POLICY "snapshot_inscriptions_insert" ON public.inscriptions FOR INSERT;
CREATE POLICY "snapshot_inscriptions_select" ON public.inscriptions FOR SELECT;
CREATE POLICY "snapshot_inscriptions_update" ON public.inscriptions FOR UPDATE;

CREATE TABLE public.journal_entries (
  id text NOT NULL,
  date text,
  "time" text,
  libelle text,
  debit text,
  credit text,
  montant numeric,
  type text,
  ref text,
  by text
);
-- RLS enabled: true
CREATE POLICY "snapshot_journal_entries_insert" ON public.journal_entries FOR INSERT;
CREATE POLICY "snapshot_journal_entries_select" ON public.journal_entries FOR SELECT;
CREATE POLICY "snapshot_journal_entries_update" ON public.journal_entries FOR UPDATE;

CREATE TABLE public.matieres (
  id text NOT NULL,
  cid text,
  name text,
  lang text,
  active boolean
);
-- RLS enabled: true
CREATE POLICY "snapshot_matieres_delete" ON public.matieres FOR DELETE;
CREATE POLICY "snapshot_matieres_insert" ON public.matieres FOR INSERT;
CREATE POLICY "snapshot_matieres_select" ON public.matieres FOR SELECT;
CREATE POLICY "snapshot_matieres_update" ON public.matieres FOR UPDATE;

CREATE TABLE public.medical (
  id text NOT NULL,
  sid text,
  blood_type text,
  allergies text,
  vaccines jsonb,
  vax_dates jsonb,
  doctor_name text,
  doctor_phone text,
  medical_notes text,
  updated text
);
-- RLS enabled: true
CREATE POLICY "snapshot_medical_delete" ON public.medical FOR DELETE;
CREATE POLICY "snapshot_medical_insert" ON public.medical FOR INSERT;
CREATE POLICY "snapshot_medical_select" ON public.medical FOR SELECT;
CREATE POLICY "snapshot_medical_update" ON public.medical FOR UPDATE;

CREATE TABLE public.medical_visits (
  id text NOT NULL,
  sid text,
  date text,
  reason text,
  treatment text,
  by text,
  "time" text
);
-- RLS enabled: true
CREATE POLICY "snapshot_medical_visits_delete" ON public.medical_visits FOR DELETE;
CREATE POLICY "snapshot_medical_visits_insert" ON public.medical_visits FOR INSERT;
CREATE POLICY "snapshot_medical_visits_select" ON public.medical_visits FOR SELECT;
CREATE POLICY "snapshot_medical_visits_update" ON public.medical_visits FOR UPDATE;

CREATE TABLE public.messages (
  id text NOT NULL,
  "from" text,
  from_role text,
  "to" text,
  to_role text,
  to_class_cid text,
  subject text,
  body text,
  msg_type text,
  date text,
  "time" text,
  status text,
  read boolean,
  type text,
  name text,
  from_name text,
  to_name text,
  about_sid text,
  about_name text,
  to_class text
);
-- RLS enabled: true
CREATE POLICY "snapshot_messages_delete" ON public.messages FOR DELETE;
CREATE POLICY "snapshot_messages_insert" ON public.messages FOR INSERT;
CREATE POLICY "snapshot_messages_select" ON public.messages FOR SELECT;
CREATE POLICY "snapshot_messages_update" ON public.messages FOR UPDATE;

CREATE TABLE public.notifs (
  id text NOT NULL,
  uid text,
  "from" text,
  msg text,
  type text,
  date text,
  "time" text,
  read boolean,
  devoir_id text,
  status text,
  to_role text,
  by text,
  wa_links jsonb,
  receipt jsonb
);
-- RLS enabled: true
CREATE POLICY "snapshot_notifs_delete" ON public.notifs FOR DELETE;
CREATE POLICY "snapshot_notifs_insert" ON public.notifs FOR INSERT;
CREATE POLICY "snapshot_notifs_select" ON public.notifs FOR SELECT;
CREATE POLICY "snapshot_notifs_update" ON public.notifs FOR UPDATE;

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
-- RLS enabled: true
CREATE POLICY "snapshot_palmares_publication_history_select" ON public.palmares_publication_history FOR SELECT;

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
-- RLS enabled: true
CREATE POLICY "snapshot_palmares_publications_delete" ON public.palmares_publications FOR DELETE;
CREATE POLICY "snapshot_palmares_publications_insert" ON public.palmares_publications FOR INSERT;
CREATE POLICY "snapshot_palmares_publications_select" ON public.palmares_publications FOR SELECT;
CREATE POLICY "snapshot_palmares_publications_update" ON public.palmares_publications FOR UPDATE;

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
-- RLS enabled: true
CREATE POLICY "snapshot_payment_access_exceptions_delete" ON public.payment_access_exceptions FOR DELETE;
CREATE POLICY "snapshot_payment_access_exceptions_insert" ON public.payment_access_exceptions FOR INSERT;
CREATE POLICY "snapshot_payment_access_exceptions_select" ON public.payment_access_exceptions FOR SELECT;
CREATE POLICY "snapshot_payment_access_exceptions_update" ON public.payment_access_exceptions FOR UPDATE;

CREATE TABLE public.payment_allocations (
  id text NOT NULL,
  transaction_id text NOT NULL,
  obligation_id text NOT NULL,
  amount numeric(14,2) NOT NULL,
  created_at timestamp with time zone NOT NULL
);
-- RLS enabled: true
CREATE POLICY "snapshot_payment_allocations_delete" ON public.payment_allocations FOR DELETE;
CREATE POLICY "snapshot_payment_allocations_insert" ON public.payment_allocations FOR INSERT;
CREATE POLICY "snapshot_payment_allocations_select" ON public.payment_allocations FOR SELECT;
CREATE POLICY "snapshot_payment_allocations_update" ON public.payment_allocations FOR UPDATE;

CREATE TABLE public.payment_receipt_counters (
  school_year text NOT NULL,
  last_no bigint NOT NULL,
  updated_at timestamp with time zone NOT NULL
);
-- RLS enabled: true
CREATE POLICY "snapshot_payment_receipt_counters_delete" ON public.payment_receipt_counters FOR DELETE;
CREATE POLICY "snapshot_payment_receipt_counters_insert" ON public.payment_receipt_counters FOR INSERT;
CREATE POLICY "snapshot_payment_receipt_counters_select" ON public.payment_receipt_counters FOR SELECT;
CREATE POLICY "snapshot_payment_receipt_counters_update" ON public.payment_receipt_counters FOR UPDATE;

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
-- RLS enabled: true
CREATE POLICY "snapshot_payment_scan_log_insert" ON public.payment_scan_log FOR INSERT;
CREATE POLICY "snapshot_payment_scan_log_select" ON public.payment_scan_log FOR SELECT;

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
-- RLS enabled: true
CREATE POLICY "snapshot_payment_transactions_insert" ON public.payment_transactions FOR INSERT;
CREATE POLICY "snapshot_payment_transactions_select" ON public.payment_transactions FOR SELECT;
CREATE POLICY "snapshot_payment_transactions_update" ON public.payment_transactions FOR UPDATE;

CREATE TABLE public.payments (
  id text NOT NULL,
  sid text,
  t text,
  paid boolean,
  date text,
  by text,
  note text
);
-- RLS enabled: true
CREATE POLICY "snapshot_payments_delete" ON public.payments FOR DELETE;
CREATE POLICY "snapshot_payments_insert" ON public.payments FOR INSERT;
CREATE POLICY "snapshot_payments_select" ON public.payments FOR SELECT;
CREATE POLICY "snapshot_payments_update" ON public.payments FOR UPDATE;

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
-- RLS enabled: true
CREATE POLICY "snapshot_preinscriptions_select" ON public.preinscriptions FOR SELECT;

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
-- RLS enabled: true
CREATE POLICY "snapshot_prevision_matiere_delete" ON public.prevision_matiere FOR DELETE;
CREATE POLICY "snapshot_prevision_matiere_insert" ON public.prevision_matiere FOR INSERT;
CREATE POLICY "snapshot_prevision_matiere_select" ON public.prevision_matiere FOR SELECT;
CREATE POLICY "snapshot_prevision_matiere_update" ON public.prevision_matiere FOR UPDATE;

CREATE TABLE public.profiles (
  id uuid NOT NULL,
  email text NOT NULL,
  full_name text NOT NULL,
  role text NOT NULL,
  status text NOT NULL,
  phone text,
  avatar_path text,
  created_at timestamp with time zone NOT NULL,
  updated_at timestamp with time zone NOT NULL
);
-- RLS enabled: true
CREATE POLICY "snapshot_profiles_delete" ON public.profiles FOR DELETE;
CREATE POLICY "snapshot_profiles_insert" ON public.profiles FOR INSERT;
CREATE POLICY "snapshot_profiles_select" ON public.profiles FOR SELECT;
CREATE POLICY "snapshot_profiles_update" ON public.profiles FOR UPDATE;

CREATE TABLE public.push_subscriptions (
  id text NOT NULL,
  uid text,
  endpoint text,
  auth text,
  p256dh text,
  ua text,
  updated_at text
);
-- RLS enabled: true
CREATE POLICY "snapshot_push_subscriptions_delete" ON public.push_subscriptions FOR DELETE;
CREATE POLICY "snapshot_push_subscriptions_insert" ON public.push_subscriptions FOR INSERT;
CREATE POLICY "snapshot_push_subscriptions_select" ON public.push_subscriptions FOR SELECT;
CREATE POLICY "snapshot_push_subscriptions_update" ON public.push_subscriptions FOR UPDATE;
*/
