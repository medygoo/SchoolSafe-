/*\nSchoolSafe — structural schema snapshot for frontend audit only.\nRange: t to { (exclusive).\nDO NOT EXECUTE. CREATE TABLE and CREATE POLICY statements are inside this comment\nbecause tools/audit-schema.mjs reads structural declarations from SQL text.\nContains no row data, API key, password, project reference, service_role or user identifier.\nPolicy predicates are omitted; operations exposed by pg_policies are recorded.\n\nCREATE TABLE public.teacher_absences (
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
-- RLS enabled: true
CREATE POLICY "snapshot_teacher_absences_delete" ON public.teacher_absences FOR DELETE;
CREATE POLICY "snapshot_teacher_absences_insert" ON public.teacher_absences FOR INSERT;
CREATE POLICY "snapshot_teacher_absences_select" ON public.teacher_absences FOR SELECT;
CREATE POLICY "snapshot_teacher_absences_update" ON public.teacher_absences FOR UPDATE;

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
-- RLS enabled: true
CREATE POLICY "snapshot_teacher_notes_delete" ON public.teacher_notes FOR DELETE;
CREATE POLICY "snapshot_teacher_notes_insert" ON public.teacher_notes FOR INSERT;
CREATE POLICY "snapshot_teacher_notes_select" ON public.teacher_notes FOR SELECT;
CREATE POLICY "snapshot_teacher_notes_update" ON public.teacher_notes FOR UPDATE;

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
-- RLS enabled: true
CREATE POLICY "snapshot_tenafep_delete" ON public.tenafep FOR DELETE;
CREATE POLICY "snapshot_tenafep_insert" ON public.tenafep FOR INSERT;
CREATE POLICY "snapshot_tenafep_select" ON public.tenafep FOR SELECT;
CREATE POLICY "snapshot_tenafep_update" ON public.tenafep FOR UPDATE;

CREATE TABLE public.timetables (
  id text NOT NULL,
  cid text,
  day text,
  period numeric,
  matiere text,
  teacher_id text
);
-- RLS enabled: true
CREATE POLICY "snapshot_timetables_delete" ON public.timetables FOR DELETE;
CREATE POLICY "snapshot_timetables_insert" ON public.timetables FOR INSERT;
CREATE POLICY "snapshot_timetables_select" ON public.timetables FOR SELECT;
CREATE POLICY "snapshot_timetables_update" ON public.timetables FOR UPDATE;

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
  updated_at timestamp with time zone NOT NULL
);
-- RLS enabled: true
CREATE POLICY "snapshot_users_delete" ON public.users FOR DELETE;
CREATE POLICY "snapshot_users_insert" ON public.users FOR INSERT;
CREATE POLICY "snapshot_users_select" ON public.users FOR SELECT;
CREATE POLICY "snapshot_users_update" ON public.users FOR UPDATE;

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
-- RLS enabled: true
CREATE POLICY "snapshot_versements_insert" ON public.versements FOR INSERT;
CREATE POLICY "snapshot_versements_select" ON public.versements FOR SELECT;
CREATE POLICY "snapshot_versements_update" ON public.versements FOR UPDATE;
*/
