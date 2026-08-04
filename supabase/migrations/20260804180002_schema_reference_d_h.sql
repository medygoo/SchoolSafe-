/*\nSchoolSafe — structural schema snapshot for frontend audit only.\nRange: d to i (exclusive).\nDO NOT EXECUTE. CREATE TABLE and CREATE POLICY statements are inside this comment\nbecause tools/audit-schema.mjs reads structural declarations from SQL text.\nContains no row data, API key, password, project reference, service_role or user identifier.\nPolicy predicates are omitted; operations exposed by pg_policies are recorded.\n\nCREATE TABLE public.daily_expenses (
  id text NOT NULL,
  amount numeric,
  motif text,
  date text,
  "time" text,
  by text,
  validated boolean,
  by_name text,
  category_label text,
  beneficiary text,
  category_code text,
  invoice_ref text,
  payment_method text
);
-- RLS enabled: true
CREATE POLICY "snapshot_daily_expenses_delete" ON public.daily_expenses FOR DELETE;
CREATE POLICY "snapshot_daily_expenses_insert" ON public.daily_expenses FOR INSERT;
CREATE POLICY "snapshot_daily_expenses_select" ON public.daily_expenses FOR SELECT;
CREATE POLICY "snapshot_daily_expenses_update" ON public.daily_expenses FOR UPDATE;

CREATE TABLE public.daily_records (
  id text NOT NULL,
  sid text,
  student_name text,
  mat text,
  type text,
  type_label text,
  trimestre text,
  amount numeric,
  note text,
  date text,
  "time" text,
  by text,
  validated boolean,
  assigned boolean,
  mvt_type text,
  ref text,
  recu_no text,
  annulled boolean
);
-- RLS enabled: true
CREATE POLICY "snapshot_daily_records_delete" ON public.daily_records FOR DELETE;
CREATE POLICY "snapshot_daily_records_insert" ON public.daily_records FOR INSERT;
CREATE POLICY "snapshot_daily_records_select" ON public.daily_records FOR SELECT;
CREATE POLICY "snapshot_daily_records_update" ON public.daily_records FOR UPDATE;

CREATE TABLE public.daily_reports (
  id text NOT NULL,
  date text,
  "time" text,
  by text,
  status text,
  records jsonb,
  expenses jsonb,
  summary jsonb,
  validatedat text
);
-- RLS enabled: true
CREATE POLICY "snapshot_daily_reports_delete" ON public.daily_reports FOR DELETE;
CREATE POLICY "snapshot_daily_reports_insert" ON public.daily_reports FOR INSERT;
CREATE POLICY "snapshot_daily_reports_select" ON public.daily_reports FOR SELECT;
CREATE POLICY "snapshot_daily_reports_update" ON public.daily_reports FOR UPDATE;

CREATE TABLE public.devoirs (
  id text NOT NULL,
  cid text,
  title text,
  type text,
  content text,
  lang text,
  matiere text,
  description text,
  chapters text,
  duration numeric,
  category text,
  date text,
  deadline text,
  teacher_id text,
  status text,
  expires_at text,
  pdf_local_only boolean,
  sigs jsonb
);
-- RLS enabled: true
CREATE POLICY "snapshot_devoirs_delete" ON public.devoirs FOR DELETE;
CREATE POLICY "snapshot_devoirs_insert" ON public.devoirs FOR INSERT;
CREATE POLICY "snapshot_devoirs_select" ON public.devoirs FOR SELECT;
CREATE POLICY "snapshot_devoirs_update" ON public.devoirs FOR UPDATE;

CREATE TABLE public.direct_primes (
  id text NOT NULL,
  teacher_id text,
  amount numeric,
  motif text,
  month text,
  date text,
  by text
);
-- RLS enabled: true
CREATE POLICY "snapshot_direct_primes_delete" ON public.direct_primes FOR DELETE;
CREATE POLICY "snapshot_direct_primes_insert" ON public.direct_primes FOR INSERT;
CREATE POLICY "snapshot_direct_primes_select" ON public.direct_primes FOR SELECT;
CREATE POLICY "snapshot_direct_primes_update" ON public.direct_primes FOR UPDATE;

CREATE TABLE public.evaluations (
  id text NOT NULL,
  teacher_id text,
  by text,
  date text,
  trimestre text,
  comment text,
  year text,
  criteria jsonb
);
-- RLS enabled: true
CREATE POLICY "snapshot_evaluations_delete" ON public.evaluations FOR DELETE;
CREATE POLICY "snapshot_evaluations_insert" ON public.evaluations FOR INSERT;
CREATE POLICY "snapshot_evaluations_select" ON public.evaluations FOR SELECT;
CREATE POLICY "snapshot_evaluations_update" ON public.evaluations FOR UPDATE;

CREATE TABLE public.events (
  id text NOT NULL,
  title text,
  date text,
  type text,
  description text,
  by text
);
-- RLS enabled: true
CREATE POLICY "snapshot_events_delete" ON public.events FOR DELETE;
CREATE POLICY "snapshot_events_insert" ON public.events FOR INSERT;
CREATE POLICY "snapshot_events_select" ON public.events FOR SELECT;
CREATE POLICY "snapshot_events_update" ON public.events FOR UPDATE;

CREATE TABLE public.exetat (
  id text NOT NULL,
  sid text,
  exetat_code text,
  option text,
  result text,
  score numeric,
  registration_num text,
  notes text,
  year text,
  registered boolean,
  updated text
);
-- RLS enabled: true
CREATE POLICY "snapshot_exetat_delete" ON public.exetat FOR DELETE;
CREATE POLICY "snapshot_exetat_insert" ON public.exetat FOR INSERT;
CREATE POLICY "snapshot_exetat_select" ON public.exetat FOR SELECT;
CREATE POLICY "snapshot_exetat_update" ON public.exetat FOR UPDATE;

CREATE TABLE public.fee_types (
  id text NOT NULL,
  label text,
  category text,
  trimestre text,
  montant_defaut numeric,
  active boolean
);
-- RLS enabled: true
CREATE POLICY "snapshot_fee_types_delete" ON public.fee_types FOR DELETE;
CREATE POLICY "snapshot_fee_types_insert" ON public.fee_types FOR INSERT;
CREATE POLICY "snapshot_fee_types_select" ON public.fee_types FOR SELECT;
CREATE POLICY "snapshot_fee_types_update" ON public.fee_types FOR UPDATE;

CREATE TABLE public.grades (
  id text NOT NULL,
  sid text,
  cid text,
  type text,
  matiere text,
  note numeric,
  max numeric,
  weight numeric,
  trimestre text,
  date text,
  label text,
  devoir_id text,
  comment text,
  by text,
  corrected_at text,
  pct numeric,
  trimester text,
  edited_by text,
  edited_date text,
  edit_reason text,
  year text
);
-- RLS enabled: true
CREATE POLICY "snapshot_grades_delete" ON public.grades FOR DELETE;
CREATE POLICY "snapshot_grades_insert" ON public.grades FOR INSERT;
CREATE POLICY "snapshot_grades_select" ON public.grades FOR SELECT;
CREATE POLICY "snapshot_grades_update" ON public.grades FOR UPDATE;
*/
