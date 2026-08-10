-- SchoolSafe VPS baseline - 09b RLS policies: private + public A-M
-- 74 policies extracted from the current Cloud database.

BEGIN;
SET LOCAL search_path = public, private, auth;

CREATE POLICY student_exit_outbox_read ON private.student_exit_notification_outbox AS PERMISSIVE FOR SELECT TO authenticated USING ((private.is_direction_any() OR (recipient_user_id = private.current_app_user_id())));

CREATE POLICY absences_direction_all ON public.absences AS PERMISSIVE FOR ALL TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));
CREATE POLICY activites_direction_all ON public.activites AS PERMISSIVE FOR ALL TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));
CREATE POLICY activites_inscriptions_direction_all ON public.activites_inscriptions AS PERMISSIVE FOR ALL TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));

CREATE POLICY administrative_document_types_direction_delete ON public.administrative_document_types AS PERMISSIVE FOR DELETE TO authenticated USING ((private.current_app_role() = 'direction'::text));
CREATE POLICY administrative_document_types_direction_insert ON public.administrative_document_types AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((private.current_app_role() = 'direction'::text));
CREATE POLICY administrative_document_types_direction_update ON public.administrative_document_types AS PERMISSIVE FOR UPDATE TO authenticated USING ((private.current_app_role() = 'direction'::text)) WITH CHECK ((private.current_app_role() = 'direction'::text));
CREATE POLICY administrative_document_types_read ON public.administrative_document_types AS PERMISSIVE FOR SELECT TO authenticated USING ((private.current_app_role() = ANY (ARRAY['direction'::text,'direction2'::text,'direction3'::text])));

CREATE POLICY administrative_documents_direction_delete ON public.administrative_documents AS PERMISSIVE FOR DELETE TO authenticated USING ((private.current_app_role() = 'direction'::text));
CREATE POLICY administrative_documents_insert ON public.administrative_documents AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((private.current_app_role() = 'direction'::text) OR ((private.current_app_role() = 'direction2'::text) AND (confidentiality = 'administrative'::text) AND (EXISTS (SELECT 1 FROM public.administrative_document_types t WHERE ((t.id = administrative_documents.document_type_id) AND t.active AND (NOT t.is_financial))))) OR ((private.current_app_role() = 'direction3'::text) AND (EXISTS (SELECT 1 FROM public.administrative_document_types t WHERE ((t.id = administrative_documents.document_type_id) AND t.active AND t.is_financial))))));
CREATE POLICY administrative_documents_read ON public.administrative_documents AS PERMISSIVE FOR SELECT TO authenticated USING (((private.current_app_role() = 'direction'::text) OR ((private.current_app_role() = 'direction2'::text) AND (NOT is_financial) AND (confidentiality = 'administrative'::text)) OR ((private.current_app_role() = 'direction3'::text) AND is_financial)));
CREATE POLICY administrative_documents_update ON public.administrative_documents AS PERMISSIVE FOR UPDATE TO authenticated USING (((status = ANY (ARRAY['draft'::text,'active'::text])) AND ((private.current_app_role() = 'direction'::text) OR ((private.current_app_role() = 'direction2'::text) AND (NOT is_financial) AND (confidentiality = 'administrative'::text)) OR ((private.current_app_role() = 'direction3'::text) AND is_financial)))) WITH CHECK (((status = ANY (ARRAY['draft'::text,'active'::text])) AND ((private.current_app_role() = 'direction'::text) OR ((private.current_app_role() = 'direction2'::text) AND (confidentiality = 'administrative'::text) AND (EXISTS (SELECT 1 FROM public.administrative_document_types t WHERE ((t.id = administrative_documents.document_type_id) AND t.active AND (NOT t.is_financial))))) OR ((private.current_app_role() = 'direction3'::text) AND (EXISTS (SELECT 1 FROM public.administrative_document_types t WHERE ((t.id = administrative_documents.document_type_id) AND t.active AND t.is_financial)))))));

CREATE POLICY advances_authorized_select ON public.advances AS PERMISSIVE FOR SELECT TO authenticated USING (((private.current_app_role() = 'direction'::text) OR (private.current_app_role() = 'direction3'::text) OR ((private.current_app_role() IS NOT NULL) AND (private.current_app_role() <> 'parent'::text) AND (COALESCE(user_id,teacher_id) = private.current_app_user_id()))));
CREATE POLICY advances_direction_delete ON public.advances AS PERMISSIVE FOR DELETE TO authenticated USING ((private.current_app_role() = 'direction'::text));
CREATE POLICY advances_direction_insert ON public.advances AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((private.current_app_role() = 'direction'::text));
CREATE POLICY advances_direction_update ON public.advances AS PERMISSIVE FOR UPDATE TO authenticated USING ((private.current_app_role() = 'direction'::text)) WITH CHECK ((private.current_app_role() = 'direction'::text));

CREATE POLICY appreciations_delete ON public.appreciations AS PERMISSIVE FOR DELETE TO authenticated USING (private.is_direction_any());
CREATE POLICY appreciations_read ON public.appreciations AS PERMISSIVE FOR SELECT TO authenticated USING ((private.is_direction_any() OR private.owns_student(sid) OR private.teaches_class(cid)));
CREATE POLICY appreciations_update ON public.appreciations AS PERMISSIVE FOR UPDATE TO authenticated USING ((private.is_direction_any() OR private.teaches_class(cid))) WITH CHECK ((private.is_direction_any() OR private.teaches_class(cid)));
CREATE POLICY appreciations_write ON public.appreciations AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((private.is_direction_any() OR private.teaches_class(cid)));

CREATE POLICY approbations_delete ON public.approbations AS PERMISSIVE FOR DELETE TO authenticated USING ((private.is_direction_any() OR ((by = private.current_app_user_id()) AND (status = 'pending'::text))));
CREATE POLICY approbations_insert ON public.approbations AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((private.can_scan() AND (by = private.current_app_user_id())));
CREATE POLICY approbations_select ON public.approbations AS PERMISSIVE FOR SELECT TO authenticated USING ((private.is_direction_any() OR (by = private.current_app_user_id())));
CREATE POLICY approbations_update ON public.approbations AS PERMISSIVE FOR UPDATE TO authenticated USING ((private.is_direction_any() OR ((by = private.current_app_user_id()) AND (status = 'pending'::text)))) WITH CHECK ((private.is_direction_any() OR ((by = private.current_app_user_id()) AND (status = 'pending'::text))));

CREATE POLICY aps_read ON public.aps AS PERMISSIVE FOR SELECT TO authenticated USING ((private.is_direction_any() OR private.owns_student(sid) OR ((private.current_app_role() = ANY (ARRAY['gardien'::text,'enseignant'::text,'direction3'::text])) AND (approval_status = 'approved'::text) AND active AND ((valid_until IS NULL) OR (valid_until >= (timezone('Africa/Kinshasa'::text,now()))::date)))));

CREATE POLICY attendance_delete ON public.attendance AS PERMISSIVE FOR DELETE TO authenticated USING (private.is_direction_any());
CREATE POLICY attendance_read ON public.attendance AS PERMISSIVE FOR SELECT TO authenticated USING ((private.is_direction_any() OR (private.current_app_role() = 'direction3'::text) OR private.owns_student(sid) OR private.teaches_class(cid) OR ((private.current_app_role() = 'gardien'::text) AND (date = to_char(timezone('Africa/Kinshasa'::text,now()),'YYYY-MM-DD'::text)))));
CREATE POLICY attendance_update ON public.attendance AS PERMISSIVE FOR UPDATE TO authenticated USING ((private.is_direction_any() OR private.teaches_class(cid))) WITH CHECK ((private.is_direction_any() OR private.teaches_class(cid)));
CREATE POLICY attendance_write ON public.attendance AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((private.is_direction_any() OR private.teaches_class(cid)));

CREATE POLICY audit_log_direction_insert ON public.audit_log AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((SELECT private.is_direction()));
CREATE POLICY audit_log_direction_read ON public.audit_log AS PERMISSIVE FOR SELECT TO authenticated USING ((SELECT private.is_direction()));

CREATE POLICY cahier_prep_delete ON public.cahier_prep AS PERMISSIVE FOR DELETE TO authenticated USING (((private.current_app_role() = 'direction'::text) OR ((private.current_app_role() = 'enseignant'::text) AND (teacher_id = private.current_app_user_id()) AND (COALESCE(statut,'brouillon'::text) = 'brouillon'::text))));
CREATE POLICY cahier_prep_insert ON public.cahier_prep AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((private.current_app_role() = 'direction'::text) OR ((private.current_app_role() = 'enseignant'::text) AND (teacher_id = private.current_app_user_id()))));
CREATE POLICY cahier_prep_select ON public.cahier_prep AS PERMISSIVE FOR SELECT TO authenticated USING (((private.current_app_role() = ANY (ARRAY['direction'::text,'direction2'::text])) OR ((private.current_app_role() = 'enseignant'::text) AND (teacher_id = private.current_app_user_id()))));
CREATE POLICY cahier_prep_update ON public.cahier_prep AS PERMISSIVE FOR UPDATE TO authenticated USING (((private.current_app_role() = ANY (ARRAY['direction'::text,'direction2'::text])) OR ((private.current_app_role() = 'enseignant'::text) AND (teacher_id = private.current_app_user_id())))) WITH CHECK (((private.current_app_role() = ANY (ARRAY['direction'::text,'direction2'::text])) OR ((private.current_app_role() = 'enseignant'::text) AND (teacher_id = private.current_app_user_id()))));

CREATE POLICY cahier_texte_direction_all ON public.cahier_texte AS PERMISSIVE FOR ALL TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));
CREATE POLICY cantine_direction_all ON public.cantine AS PERMISSIVE FOR ALL TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));
CREATE POLICY cantine_menus_direction_all ON public.cantine_menus AS PERMISSIVE FOR ALL TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));
CREATE POLICY cantine_presence_direction_all ON public.cantine_presence AS PERMISSIVE FOR ALL TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));

CREATE POLICY classes_direction_write ON public.classes AS PERMISSIVE FOR ALL TO authenticated USING (private.is_direction_any()) WITH CHECK (private.is_direction_any());
CREATE POLICY classes_read ON public.classes AS PERMISSIVE FOR SELECT TO authenticated USING (private.can_view_class(id));

CREATE POLICY conduct_delete ON public.conduct AS PERMISSIVE FOR DELETE TO authenticated USING (private.is_direction_any());
CREATE POLICY conduct_read ON public.conduct AS PERMISSIVE FOR SELECT TO authenticated USING ((private.is_direction_any() OR private.owns_student(sid) OR (EXISTS (SELECT 1 FROM public.students s WHERE ((s.id = conduct.sid) AND private.teaches_class(s.cid))))));
CREATE POLICY conduct_update ON public.conduct AS PERMISSIVE FOR UPDATE TO authenticated USING ((private.is_direction_any() OR (EXISTS (SELECT 1 FROM public.students s WHERE ((s.id = conduct.sid) AND private.teaches_class(s.cid)))))) WITH CHECK ((private.is_direction_any() OR (EXISTS (SELECT 1 FROM public.students s WHERE ((s.id = conduct.sid) AND private.teaches_class(s.cid))))));
CREATE POLICY conduct_write ON public.conduct AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((private.is_direction_any() OR (EXISTS (SELECT 1 FROM public.students s WHERE ((s.id = conduct.sid) AND private.teaches_class(s.cid))))));

CREATE POLICY convocations_direction_all ON public.convocations AS PERMISSIVE FOR ALL TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));
CREATE POLICY daily_expenses_direction_all ON public.daily_expenses AS PERMISSIVE FOR ALL TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));
CREATE POLICY daily_records_direction_all ON public.daily_records AS PERMISSIVE FOR ALL TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));
CREATE POLICY daily_reports_direction_all ON public.daily_reports AS PERMISSIVE FOR ALL TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));

CREATE POLICY devoirs_delete ON public.devoirs AS PERMISSIVE FOR DELETE TO authenticated USING (((private.current_app_role() = 'direction'::text) OR ((private.current_app_role() = 'enseignant'::text) AND (teacher_id = private.current_app_user_id()) AND private.teacher_has_class_access(cid) AND (COALESCE(status,'brouillon'::text) = ANY (ARRAY['brouillon'::text,'draft'::text])))));
CREATE POLICY devoirs_insert ON public.devoirs AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((private.current_app_role() = 'direction'::text) OR ((private.current_app_role() = 'enseignant'::text) AND (teacher_id = private.current_app_user_id()) AND private.teacher_has_class_access(cid))));
CREATE POLICY devoirs_select ON public.devoirs AS PERMISSIVE FOR SELECT TO authenticated USING (((private.current_app_role() = ANY (ARRAY['direction'::text,'direction2'::text])) OR ((private.current_app_role() = 'enseignant'::text) AND ((teacher_id = private.current_app_user_id()) OR private.teacher_has_class_access(cid))) OR private.parent_has_child_in_class(cid)));
CREATE POLICY devoirs_update ON public.devoirs AS PERMISSIVE FOR UPDATE TO authenticated USING (((private.current_app_role() = ANY (ARRAY['direction'::text,'direction2'::text])) OR ((private.current_app_role() = 'enseignant'::text) AND (teacher_id = private.current_app_user_id()) AND private.teacher_has_class_access(cid)))) WITH CHECK (((private.current_app_role() = ANY (ARRAY['direction'::text,'direction2'::text])) OR ((private.current_app_role() = 'enseignant'::text) AND (teacher_id = private.current_app_user_id()) AND private.teacher_has_class_access(cid))));

CREATE POLICY direct_primes_authorized_select ON public.direct_primes AS PERMISSIVE FOR SELECT TO authenticated USING (((private.current_app_role() = ANY (ARRAY['direction'::text,'direction2'::text])) OR ((private.current_app_role() = 'enseignant'::text) AND (teacher_id = private.current_app_user_id()))));
CREATE POLICY direct_primes_direction_delete ON public.direct_primes AS PERMISSIVE FOR DELETE TO authenticated USING ((private.current_app_role() = 'direction'::text));
CREATE POLICY direct_primes_direction_insert ON public.direct_primes AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((private.current_app_role() = 'direction'::text));
CREATE POLICY direct_primes_direction_update ON public.direct_primes AS PERMISSIVE FOR UPDATE TO authenticated USING ((private.current_app_role() = 'direction'::text)) WITH CHECK ((private.current_app_role() = 'direction'::text));

CREATE POLICY evaluations_direction_all ON public.evaluations AS PERMISSIVE FOR ALL TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));
CREATE POLICY events_direction_all ON public.events AS PERMISSIVE FOR ALL TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));
CREATE POLICY exetat_direction_all ON public.exetat AS PERMISSIVE FOR ALL TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));
CREATE POLICY fee_types_direction_all ON public.fee_types AS PERMISSIVE FOR ALL TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));

CREATE POLICY grades_delete ON public.grades AS PERMISSIVE FOR DELETE TO authenticated USING ((private.is_direction_any() OR private.teaches_class(cid)));
CREATE POLICY grades_read ON public.grades AS PERMISSIVE FOR SELECT TO authenticated USING ((private.is_direction_any() OR private.owns_student(sid) OR private.teaches_class(cid)));
CREATE POLICY grades_update ON public.grades AS PERMISSIVE FOR UPDATE TO authenticated USING ((private.is_direction_any() OR private.teaches_class(cid))) WITH CHECK ((private.is_direction_any() OR private.teaches_class(cid)));
CREATE POLICY grades_write ON public.grades AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((private.is_direction_any() OR private.teaches_class(cid)));

CREATE POLICY inscriptions_direction_all ON public.inscriptions AS PERMISSIVE FOR ALL TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));
CREATE POLICY journal_entries_direction_insert ON public.journal_entries AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((SELECT private.is_direction()));
CREATE POLICY journal_entries_direction_read ON public.journal_entries AS PERMISSIVE FOR SELECT TO authenticated USING ((SELECT private.is_direction()));
CREATE POLICY journal_entries_direction_update ON public.journal_entries AS PERMISSIVE FOR UPDATE TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));

CREATE POLICY matieres_direction_write ON public.matieres AS PERMISSIVE FOR ALL TO authenticated USING (private.is_direction_any()) WITH CHECK (private.is_direction_any());
CREATE POLICY matieres_read ON public.matieres AS PERMISSIVE FOR SELECT TO authenticated USING (private.can_view_class(cid));
CREATE POLICY medical_direction_all ON public.medical AS PERMISSIVE FOR ALL TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));
CREATE POLICY medical_visits_direction_all ON public.medical_visits AS PERMISSIVE FOR ALL TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));
CREATE POLICY messages_direction_all ON public.messages AS PERMISSIVE FOR ALL TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));

COMMIT;
