-- SchoolSafe VPS baseline - 02b public tables A-C
-- Structures uniquement : defaults, contraintes, index, triggers et RLS arrivent plus tard.

BEGIN;

CREATE TABLE public.absences (
  id text NOT NULL,
  sid text,
  pid text,
  dates text,
  motif text,
  note text,
  status text,
  date text,
  "time" text,
  by text,
  submitted text,
  validated_by text,
  validated_at text
);

CREATE TABLE public.activites (
  id text NOT NULL,
  name text,
  description text,
  color text,
  frais numeric,
  date text,
  by text,
  emoji text,
  jour text,
  heure text,
  lieu text
);

CREATE TABLE public.activites_inscriptions (
  id text NOT NULL,
  sid text,
  activity_id text,
  date_inscription text,
  by text,
  active boolean,
  act_id text,
  date text
);

CREATE TABLE public.administrative_document_types (
  id text NOT NULL,
  code text NOT NULL,
  label text NOT NULL,
  group_code text NOT NULL,
  is_financial boolean NOT NULL,
  active boolean NOT NULL,
  sort_order integer NOT NULL,
  created_at timestamp with time zone NOT NULL,
  updated_at timestamp with time zone NOT NULL
);

CREATE TABLE public.administrative_documents (
  id text NOT NULL,
  document_type_id text NOT NULL,
  title text NOT NULL,
  document_number text,
  document_date date,
  period_start date,
  period_end date,
  provider text,
  amount numeric(14,2),
  currency text NOT NULL,
  notes text,
  school_year text NOT NULL,
  confidentiality text NOT NULL,
  is_financial boolean NOT NULL,
  status text NOT NULL,
  created_by text,
  created_at timestamp with time zone NOT NULL,
  updated_at timestamp with time zone NOT NULL,
  archived_at timestamp with time zone,
  archived_by text,
  restored_at timestamp with time zone,
  restored_by text
);

CREATE TABLE public.advances (
  id text NOT NULL,
  teacher_id text,
  amount numeric,
  reason text,
  month text,
  date text,
  by text,
  user_id text
);

CREATE TABLE public.appreciations (
  id text NOT NULL,
  sid text,
  cid text,
  "trim" text,
  text text,
  by text,
  date text,
  updated text
);

CREATE TABLE public.approbations (
  id text NOT NULL,
  type text,
  status text,
  content text,
  data jsonb,
  date text,
  "time" text,
  by text,
  sid text
);

CREATE TABLE public.aps (
  id text NOT NULL,
  sid text NOT NULL,
  name text NOT NULL,
  relation text NOT NULL,
  photo text,
  active boolean NOT NULL,
  phone text NOT NULL,
  approval_status text NOT NULL,
  proposed_by text,
  proposed_at timestamp with time zone NOT NULL,
  approved_by text,
  approved_at timestamp with time zone,
  rejection_reason text,
  id_doc_type text,
  id_doc_last4 text,
  valid_until date,
  created_at timestamp with time zone NOT NULL,
  photo_full_body text,
  valid_from date NOT NULL,
  created_by text,
  created_by_name text,
  updated_at timestamp with time zone NOT NULL,
  suspended_by text,
  suspended_at timestamp with time zone,
  status_note text
);

CREATE TABLE public.attendance (
  id text NOT NULL,
  sid text,
  cid text,
  date text,
  status text,
  arr_time text,
  manual boolean,
  marked_by text,
  note text,
  excused boolean,
  teacher_validated boolean,
  by text,
  year text,
  trimestre text,
  created_at timestamp with time zone NOT NULL
);

CREATE TABLE public.audit_log (
  id text NOT NULL,
  by text,
  by_name text,
  action text,
  detail text,
  target_id text,
  date text,
  "time" text
);

CREATE TABLE public.cahier_prep (
  id text NOT NULL,
  cid text,
  matiere text,
  content text,
  lang text,
  date_prevue text,
  date text,
  status text,
  validated boolean,
  remark text,
  teacher_id text,
  by text,
  by_name text,
  "time" text,
  titre text,
  date_lesson text,
  linked_day text,
  linked_period numeric,
  objectifs text,
  prerequis text,
  intro text,
  developpement text,
  conclusion text,
  materiel text,
  evaluation text,
  devoir_note text,
  statut text,
  created_at text,
  updated_at text,
  ct_id text
);

CREATE TABLE public.cahier_texte (
  id text NOT NULL,
  cid text,
  by text,
  matiere text,
  content text,
  date text,
  status text,
  lang text,
  chapitre text,
  devoirs text,
  prochain text
);

CREATE TABLE public.cantine (
  id text NOT NULL,
  sid text,
  type text,
  amount numeric,
  active boolean,
  date_inscription text,
  by text
);

CREATE TABLE public.cantine_menus (
  id text NOT NULL,
  date text,
  plat text,
  dessert text,
  boisson text,
  prix numeric,
  photo_url text,
  emoji text
);

CREATE TABLE public.cantine_presence (
  id text NOT NULL,
  sid text,
  date text,
  present boolean
);

CREATE TABLE public.classes (
  id text NOT NULL,
  name text,
  cycle text,
  teacher_id text,
  teacher_id_en text,
  titulaire_id text,
  option text,
  card_color text,
  card_color_soft text,
  card_color_dark text
);

CREATE TABLE public.conduct (
  id text NOT NULL,
  sid text,
  score text,
  remark text,
  date text,
  by text,
  year text NOT NULL,
  trimestre text NOT NULL,
  created_at timestamp with time zone NOT NULL
);

CREATE TABLE public.convocations (
  id text NOT NULL,
  sid text,
  date text,
  reason text,
  body text,
  note text,
  status text,
  rdv_date text,
  score numeric,
  trimestre text,
  auto_generated boolean,
  weak_mats text,
  by text,
  convoc_type text,
  parent_confirmed boolean,
  parent_confirmed_at text
);

COMMIT;
