/*\nSchoolSafe — structural schema snapshot for frontend audit only.\nRange: a to d (exclusive).\nDO NOT EXECUTE. CREATE TABLE and CREATE POLICY statements are inside this comment\nbecause tools/audit-schema.mjs reads structural declarations from SQL text.\nContains no row data, API key, password, project reference, service_role or user identifier.\nPolicy predicates are omitted; operations exposed by pg_policies are recorded.\n\nCREATE TABLE public.absences (
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
-- RLS enabled: true
CREATE POLICY "snapshot_absences_delete" ON public.absences FOR DELETE;
CREATE POLICY "snapshot_absences_insert" ON public.absences FOR INSERT;
CREATE POLICY "snapshot_absences_select" ON public.absences FOR SELECT;
CREATE POLICY "snapshot_absences_update" ON public.absences FOR UPDATE;

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
-- RLS enabled: true
CREATE POLICY "snapshot_activites_delete" ON public.activites FOR DELETE;
CREATE POLICY "snapshot_activites_insert" ON public.activites FOR INSERT;
CREATE POLICY "snapshot_activites_select" ON public.activites FOR SELECT;
CREATE POLICY "snapshot_activites_update" ON public.activites FOR UPDATE;

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
-- RLS enabled: true
CREATE POLICY "snapshot_activites_inscriptions_delete" ON public.activites_inscriptions FOR DELETE;
CREATE POLICY "snapshot_activites_inscriptions_insert" ON public.activites_inscriptions FOR INSERT;
CREATE POLICY "snapshot_activites_inscriptions_select" ON public.activites_inscriptions FOR SELECT;
CREATE POLICY "snapshot_activites_inscriptions_update" ON public.activites_inscriptions FOR UPDATE;

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
-- RLS enabled: true
CREATE POLICY "snapshot_administrative_document_types_delete" ON public.administrative_document_types FOR DELETE;
CREATE POLICY "snapshot_administrative_document_types_insert" ON public.administrative_document_types FOR INSERT;
CREATE POLICY "snapshot_administrative_document_types_select" ON public.administrative_document_types FOR SELECT;
CREATE POLICY "snapshot_administrative_document_types_update" ON public.administrative_document_types FOR UPDATE;

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
-- RLS enabled: true
CREATE POLICY "snapshot_administrative_documents_delete" ON public.administrative_documents FOR DELETE;
CREATE POLICY "snapshot_administrative_documents_insert" ON public.administrative_documents FOR INSERT;
CREATE POLICY "snapshot_administrative_documents_select" ON public.administrative_documents FOR SELECT;
CREATE POLICY "snapshot_administrative_documents_update" ON public.administrative_documents FOR UPDATE;

CREATE TABLE public.advances (
  id text NOT NULL,
  teacher_id text,
  amount numeric,
  reason text,
  month text,
  date text,
  by text
);
-- RLS enabled: true
CREATE POLICY "snapshot_advances_delete" ON public.advances FOR DELETE;
CREATE POLICY "snapshot_advances_insert" ON public.advances FOR INSERT;
CREATE POLICY "snapshot_advances_select" ON public.advances FOR SELECT;
CREATE POLICY "snapshot_advances_update" ON public.advances FOR UPDATE;

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
-- RLS enabled: true
CREATE POLICY "snapshot_appreciations_delete" ON public.appreciations FOR DELETE;
CREATE POLICY "snapshot_appreciations_insert" ON public.appreciations FOR INSERT;
CREATE POLICY "snapshot_appreciations_select" ON public.appreciations FOR SELECT;
CREATE POLICY "snapshot_appreciations_update" ON public.appreciations FOR UPDATE;

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
-- RLS enabled: true
CREATE POLICY "snapshot_approbations_delete" ON public.approbations FOR DELETE;
CREATE POLICY "snapshot_approbations_insert" ON public.approbations FOR INSERT;
CREATE POLICY "snapshot_approbations_select" ON public.approbations FOR SELECT;
CREATE POLICY "snapshot_approbations_update" ON public.approbations FOR UPDATE;

CREATE TABLE public.aps (
  id text NOT NULL,
  sid text,
  name text,
  relation text,
  photo text,
  active boolean,
  phone text,
  approval_status text NOT NULL,
  proposed_by text,
  proposed_at timestamp with time zone NOT NULL,
  approved_by text,
  approved_at timestamp with time zone,
  rejection_reason text,
  id_doc_type text,
  id_doc_last4 text,
  valid_until date,
  created_at timestamp with time zone NOT NULL
);
-- RLS enabled: true
CREATE POLICY "snapshot_aps_delete" ON public.aps FOR DELETE;
CREATE POLICY "snapshot_aps_insert" ON public.aps FOR INSERT;
CREATE POLICY "snapshot_aps_select" ON public.aps FOR SELECT;
CREATE POLICY "snapshot_aps_update" ON public.aps FOR UPDATE;

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
-- RLS enabled: true
CREATE POLICY "snapshot_attendance_delete" ON public.attendance FOR DELETE;
CREATE POLICY "snapshot_attendance_insert" ON public.attendance FOR INSERT;
CREATE POLICY "snapshot_attendance_select" ON public.attendance FOR SELECT;
CREATE POLICY "snapshot_attendance_update" ON public.attendance FOR UPDATE;

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
-- RLS enabled: true
CREATE POLICY "snapshot_audit_log_insert" ON public.audit_log FOR INSERT;
CREATE POLICY "snapshot_audit_log_select" ON public.audit_log FOR SELECT;

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
-- RLS enabled: true
CREATE POLICY "snapshot_cahier_prep_delete" ON public.cahier_prep FOR DELETE;
CREATE POLICY "snapshot_cahier_prep_insert" ON public.cahier_prep FOR INSERT;
CREATE POLICY "snapshot_cahier_prep_select" ON public.cahier_prep FOR SELECT;
CREATE POLICY "snapshot_cahier_prep_update" ON public.cahier_prep FOR UPDATE;

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
-- RLS enabled: true
CREATE POLICY "snapshot_cahier_texte_delete" ON public.cahier_texte FOR DELETE;
CREATE POLICY "snapshot_cahier_texte_insert" ON public.cahier_texte FOR INSERT;
CREATE POLICY "snapshot_cahier_texte_select" ON public.cahier_texte FOR SELECT;
CREATE POLICY "snapshot_cahier_texte_update" ON public.cahier_texte FOR UPDATE;

CREATE TABLE public.cantine (
  id text NOT NULL,
  sid text,
  type text,
  amount numeric,
  active boolean,
  date_inscription text,
  by text
);
-- RLS enabled: true
CREATE POLICY "snapshot_cantine_delete" ON public.cantine FOR DELETE;
CREATE POLICY "snapshot_cantine_insert" ON public.cantine FOR INSERT;
CREATE POLICY "snapshot_cantine_select" ON public.cantine FOR SELECT;
CREATE POLICY "snapshot_cantine_update" ON public.cantine FOR UPDATE;

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
-- RLS enabled: true
CREATE POLICY "snapshot_cantine_menus_delete" ON public.cantine_menus FOR DELETE;
CREATE POLICY "snapshot_cantine_menus_insert" ON public.cantine_menus FOR INSERT;
CREATE POLICY "snapshot_cantine_menus_select" ON public.cantine_menus FOR SELECT;
CREATE POLICY "snapshot_cantine_menus_update" ON public.cantine_menus FOR UPDATE;

CREATE TABLE public.cantine_presence (
  id text NOT NULL,
  sid text,
  date text,
  present boolean
);
-- RLS enabled: true
CREATE POLICY "snapshot_cantine_presence_delete" ON public.cantine_presence FOR DELETE;
CREATE POLICY "snapshot_cantine_presence_insert" ON public.cantine_presence FOR INSERT;
CREATE POLICY "snapshot_cantine_presence_select" ON public.cantine_presence FOR SELECT;
CREATE POLICY "snapshot_cantine_presence_update" ON public.cantine_presence FOR UPDATE;

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
-- RLS enabled: true
CREATE POLICY "snapshot_classes_delete" ON public.classes FOR DELETE;
CREATE POLICY "snapshot_classes_insert" ON public.classes FOR INSERT;
CREATE POLICY "snapshot_classes_select" ON public.classes FOR SELECT;
CREATE POLICY "snapshot_classes_update" ON public.classes FOR UPDATE;

CREATE TABLE public.conduct (
  id text NOT NULL,
  sid text,
  score text,
  remark text,
  date text,
  by text,
  year text,
  trimestre text,
  created_at timestamp with time zone NOT NULL
);
-- RLS enabled: true
CREATE POLICY "snapshot_conduct_delete" ON public.conduct FOR DELETE;
CREATE POLICY "snapshot_conduct_insert" ON public.conduct FOR INSERT;
CREATE POLICY "snapshot_conduct_select" ON public.conduct FOR SELECT;
CREATE POLICY "snapshot_conduct_update" ON public.conduct FOR UPDATE;

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
-- RLS enabled: true
CREATE POLICY "snapshot_convocations_delete" ON public.convocations FOR DELETE;
CREATE POLICY "snapshot_convocations_insert" ON public.convocations FOR INSERT;
CREATE POLICY "snapshot_convocations_select" ON public.convocations FOR SELECT;
CREATE POLICY "snapshot_convocations_update" ON public.convocations FOR UPDATE;
*/
