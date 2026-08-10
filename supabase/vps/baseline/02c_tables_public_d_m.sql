-- SchoolSafe VPS baseline - 02c public tables D-M
-- Structures uniquement : defaults, contraintes, index, triggers et RLS arrivent plus tard.

BEGIN;

CREATE TABLE public.daily_expenses (
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

CREATE TABLE public.direct_primes (
  id text NOT NULL,
  teacher_id text,
  amount numeric,
  motif text,
  month text,
  date text,
  by text
);

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

CREATE TABLE public.events (
  id text NOT NULL,
  title text,
  date text,
  type text,
  description text,
  by text
);

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

CREATE TABLE public.fee_types (
  id text NOT NULL,
  label text,
  category text,
  trimestre text,
  montant_defaut numeric,
  active boolean
);

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

CREATE TABLE public.inscriptions (
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

CREATE TABLE public.matieres (
  id text NOT NULL,
  cid text,
  name text,
  lang text,
  active boolean
);

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

CREATE TABLE public.medical_visits (
  id text NOT NULL,
  sid text,
  date text,
  reason text,
  treatment text,
  by text,
  "time" text
);

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

COMMIT;
