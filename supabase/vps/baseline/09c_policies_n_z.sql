-- SchoolSafe VPS baseline - 09c RLS policies: public N-Z
-- 53 policies extracted from the current Cloud database.

BEGIN;
SET LOCAL search_path = public, private, auth;

CREATE POLICY notifs_insert ON public.notifs AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (private.can_notify(uid));
CREATE POLICY notifs_read ON public.notifs AS PERMISSIVE FOR SELECT TO authenticated USING (((uid = private.current_app_user_id()) OR private.is_direction() OR (created_by_user_id = private.current_app_user_id())));
CREATE POLICY notifs_update ON public.notifs AS PERMISSIVE FOR UPDATE TO authenticated USING (((uid = private.current_app_user_id()) OR private.is_direction())) WITH CHECK (((uid = private.current_app_user_id()) OR private.is_direction()));

CREATE POLICY palmares_history_read ON public.palmares_publication_history AS PERMISSIVE FOR SELECT TO authenticated USING (private.is_direction_any());
CREATE POLICY palmares_direction_read ON public.palmares_publications AS PERMISSIVE FOR SELECT TO authenticated USING ((private.is_direction_any() OR private.teaches_class(cid)));
CREATE POLICY palmares_direction_write ON public.palmares_publications AS PERMISSIVE FOR ALL TO authenticated USING (private.is_direction_any()) WITH CHECK (private.is_direction_any());

CREATE POLICY pae_read ON public.payment_access_exceptions AS PERMISSIVE FOR SELECT TO authenticated USING (((SELECT private.current_app_role()) = ANY (ARRAY['direction'::text,'direction3'::text]) OR private.owns_student(sid)));
CREATE POLICY pae_write ON public.payment_access_exceptions AS PERMISSIVE FOR ALL TO authenticated USING (((SELECT private.current_app_role()) = 'direction'::text)) WITH CHECK (((SELECT private.current_app_role()) = 'direction'::text));

CREATE POLICY pal_delete ON public.payment_allocations AS PERMISSIVE FOR DELETE TO authenticated USING (((SELECT private.current_app_role()) = 'direction'::text));
CREATE POLICY pal_insert ON public.payment_allocations AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (((SELECT private.current_app_role()) = ANY (ARRAY['direction'::text,'direction3'::text])));
CREATE POLICY pal_read ON public.payment_allocations AS PERMISSIVE FOR SELECT TO authenticated USING ((EXISTS (SELECT 1 FROM public.payment_transactions t WHERE ((t.id = payment_allocations.transaction_id) AND (((SELECT private.current_app_role()) = ANY (ARRAY['direction'::text,'direction3'::text])) OR private.owns_student(t.sid))))));
CREATE POLICY pal_update ON public.payment_allocations AS PERMISSIVE FOR UPDATE TO authenticated USING (((SELECT private.current_app_role()) = 'direction'::text)) WITH CHECK (((SELECT private.current_app_role()) = 'direction'::text));

CREATE POLICY payment_receipt_counters_deny_all ON public.payment_receipt_counters AS RESTRICTIVE FOR ALL TO authenticated USING (false) WITH CHECK (false);
CREATE POLICY psc_insert ON public.payment_scan_log AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((private.can_scan() AND (checked_by = (SELECT private.current_app_user_id())) AND (checked_role = (SELECT private.current_app_role()))));
CREATE POLICY psc_read ON public.payment_scan_log AS PERMISSIVE FOR SELECT TO authenticated USING (((SELECT private.current_app_role()) = ANY (ARRAY['direction'::text,'direction3'::text])));
CREATE POLICY ptx_read ON public.payment_transactions AS PERMISSIVE FOR SELECT TO authenticated USING ((((SELECT private.current_app_role()) = ANY (ARRAY['direction'::text,'direction3'::text])) OR private.owns_student(sid)));
CREATE POLICY payments_finance_read ON public.payments AS PERMISSIVE FOR SELECT TO authenticated USING (((private.current_app_role() = ANY (ARRAY['direction'::text,'direction3'::text])) OR private.owns_student(sid)));
CREATE POLICY payments_finance_write ON public.payments AS PERMISSIVE FOR ALL TO authenticated USING ((private.current_app_role() = ANY (ARRAY['direction'::text,'direction3'::text]))) WITH CHECK ((private.current_app_role() = ANY (ARRAY['direction'::text,'direction3'::text])));

CREATE POLICY preinscriptions_direction_read ON public.preinscriptions AS PERMISSIVE FOR SELECT TO authenticated USING (((SELECT private.current_app_role()) = 'direction'::text));
CREATE POLICY prevision_matiere_direction_all ON public.prevision_matiere AS PERMISSIVE FOR ALL TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));

CREATE POLICY profiles_delete ON public.profiles AS PERMISSIVE FOR DELETE TO authenticated USING (private.is_direction());
CREATE POLICY profiles_insert ON public.profiles AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK (private.is_direction());
CREATE POLICY profiles_select ON public.profiles AS PERMISSIVE FOR SELECT TO authenticated USING (((id = (SELECT auth.uid())) OR private.is_direction_any()));
CREATE POLICY profiles_update ON public.profiles AS PERMISSIVE FOR UPDATE TO authenticated USING (((id = (SELECT auth.uid())) OR private.is_direction())) WITH CHECK (((id = (SELECT auth.uid())) OR private.is_direction()));
CREATE POLICY push_subscriptions_no_direct_access ON public.push_subscriptions AS PERMISSIVE FOR ALL TO authenticated USING (false) WITH CHECK (false);

CREATE POLICY rattrapages_direction_all ON public.rattrapages AS PERMISSIVE FOR ALL TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));

CREATE POLICY salaries_authorized_select ON public.salaries AS PERMISSIVE FOR SELECT TO authenticated USING (((private.current_app_role() = 'direction'::text) OR (private.current_app_role() = 'direction3'::text) OR ((private.current_app_role() IS NOT NULL) AND (private.current_app_role() <> 'parent'::text) AND (COALESCE(user_id,teacher_id) = private.current_app_user_id()))));
CREATE POLICY salaries_direction_delete ON public.salaries AS PERMISSIVE FOR DELETE TO authenticated USING ((private.current_app_role() = 'direction'::text));
CREATE POLICY salaries_direction_insert ON public.salaries AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((private.current_app_role() = 'direction'::text));
CREATE POLICY salaries_direction_update ON public.salaries AS PERMISSIVE FOR UPDATE TO authenticated USING ((private.current_app_role() = 'direction'::text)) WITH CHECK ((private.current_app_role() = 'direction'::text));

CREATE POLICY sanctions_direction_all ON public.sanctions AS PERMISSIVE FOR ALL TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));
CREATE POLICY scan_log_direction_write ON public.scan_log AS PERMISSIVE FOR ALL TO authenticated USING (private.is_direction_any()) WITH CHECK (private.is_direction_any());
CREATE POLICY scan_log_read ON public.scan_log AS PERMISSIVE FOR SELECT TO authenticated USING ((private.is_direction_any() OR private.owns_student(sid) OR ((private.current_app_role() = ANY (ARRAY['gardien'::text,'direction3'::text])) AND (date = to_char(timezone('Africa/Kinshasa'::text,now()),'YYYY-MM-DD'::text))) OR ((private.current_app_role() = 'enseignant'::text) AND (date = to_char(timezone('Africa/Kinshasa'::text,now()),'YYYY-MM-DD'::text)) AND (EXISTS (SELECT 1 FROM public.students s WHERE ((s.id = scan_log.sid) AND private.teaches_class(s.cid)))))));

CREATE POLICY school_files_direction_select ON public.school_files AS PERMISSIVE FOR SELECT TO authenticated USING ((SELECT private.is_direction()));
CREATE POLICY school_profile_direction_update ON public.school_profile AS PERMISSIVE FOR UPDATE TO authenticated USING ((SELECT private.is_direction())) WITH CHECK (((SELECT private.is_direction()) AND (id = 1)));
CREATE POLICY school_profile_public_read ON public.school_profile AS PERMISSIVE FOR SELECT TO anon, authenticated USING (true);
CREATE POLICY settings_d1_all ON public.settings AS PERMISSIVE FOR ALL TO authenticated USING (private.is_direction()) WITH CHECK (private.is_direction());
CREATE POLICY site_content_public_read ON public.site_content AS PERMISSIVE FOR SELECT TO anon, authenticated USING ((id = 'main'::text));

CREATE POLICY student_exit_events_read ON public.student_exit_events AS PERMISSIVE FOR SELECT TO authenticated USING ((private.is_direction_any() OR private.owns_student(sid) OR ((private.current_app_role() = ANY (ARRAY['gardien'::text,'enseignant'::text])) AND (school_date = (timezone('Africa/Kinshasa'::text,now()))::date))));
CREATE POLICY sfo_read ON public.student_fee_obligations AS PERMISSIVE FOR SELECT TO authenticated USING ((((SELECT private.current_app_role()) = ANY (ARRAY['direction'::text,'direction3'::text])) OR private.owns_student(sid)));
CREATE POLICY sfo_write ON public.student_fee_obligations AS PERMISSIVE FOR ALL TO authenticated USING (((SELECT private.current_app_role()) = 'direction'::text)) WITH CHECK (((SELECT private.current_app_role()) = 'direction'::text));
CREATE POLICY primary_parent_history_read ON public.student_primary_parent_history AS PERMISSIVE FOR SELECT TO authenticated USING ((private.is_direction_any() OR (old_parent_id = private.current_app_user_id()) OR (new_parent_id = private.current_app_user_id())));
CREATE POLICY students_direction_write ON public.students AS PERMISSIVE FOR ALL TO authenticated USING (private.is_direction_any()) WITH CHECK (private.is_direction_any());
CREATE POLICY students_read ON public.students AS PERMISSIVE FOR SELECT TO authenticated USING (private.can_view_student(id));

CREATE POLICY teacher_absences_direction_all ON public.teacher_absences AS PERMISSIVE FOR ALL TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));
CREATE POLICY teacher_notes_direction_all ON public.teacher_notes AS PERMISSIVE FOR ALL TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));
CREATE POLICY tenafep_direction_all ON public.tenafep AS PERMISSIVE FOR ALL TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));
CREATE POLICY timetables_direction_all ON public.timetables AS PERMISSIVE FOR ALL TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));

CREATE POLICY users_d1_write ON public.users AS PERMISSIVE FOR ALL TO authenticated USING (private.is_direction()) WITH CHECK (private.is_direction());
CREATE POLICY users_read ON public.users AS PERMISSIVE FOR SELECT TO authenticated USING (((id = private.current_app_user_id()) OR private.is_direction_any()));

CREATE POLICY versements_direction_insert ON public.versements AS PERMISSIVE FOR INSERT TO authenticated WITH CHECK ((SELECT private.is_direction()));
CREATE POLICY versements_direction_read ON public.versements AS PERMISSIVE FOR SELECT TO authenticated USING ((SELECT private.is_direction()));
CREATE POLICY versements_direction_update ON public.versements AS PERMISSIVE FOR UPDATE TO authenticated USING ((SELECT private.is_direction())) WITH CHECK ((SELECT private.is_direction()));

COMMIT;
