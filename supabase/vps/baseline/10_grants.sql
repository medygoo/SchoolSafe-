-- SchoolSafe VPS baseline - 10 explicit grants
-- Purpose: reproduce API capabilities without relying on implicit PostgreSQL PUBLIC grants.

BEGIN;

-- Schema access
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA private TO authenticated;
REVOKE ALL ON SCHEMA private FROM anon;

-- Start from a closed application-table baseline.
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon, authenticated, service_role;
REVOKE ALL ON ALL TABLES IN SCHEMA private FROM anon, authenticated, service_role;

-- Server role: current Cloud behavior is full access to public application tables.
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO service_role;

-- Anonymous public website only.
GRANT SELECT ON public.school_profile, public.site_content TO anon;

-- Authenticated: tables with ordinary CRUD guarded by RLS.
GRANT SELECT, INSERT, UPDATE, DELETE ON
  public.absences,
  public.activites,
  public.activites_inscriptions,
  public.advances,
  public.appreciations,
  public.approbations,
  public.attendance,
  public.cahier_prep,
  public.cahier_texte,
  public.cantine,
  public.cantine_menus,
  public.cantine_presence,
  public.classes,
  public.conduct,
  public.convocations,
  public.daily_expenses,
  public.daily_records,
  public.daily_reports,
  public.devoirs,
  public.direct_primes,
  public.evaluations,
  public.events,
  public.exetat,
  public.fee_types,
  public.grades,
  public.inscriptions,
  public.matieres,
  public.medical,
  public.medical_visits,
  public.messages,
  public.payments,
  public.prevision_matiere,
  public.profiles,
  public.rattrapages,
  public.salaries,
  public.sanctions,
  public.scan_log,
  public.settings,
  public.students,
  public.teacher_absences,
  public.teacher_notes,
  public.tenafep,
  public.timetables,
  public.users
TO authenticated;

-- Current Cloud tables that were granted ALL to authenticated.
GRANT ALL PRIVILEGES ON
  public.administrative_document_types,
  public.administrative_documents,
  public.palmares_publication_history,
  public.palmares_publications,
  public.payment_access_exceptions,
  public.payment_allocations,
  public.payment_scan_log,
  public.student_fee_obligations
TO authenticated;

GRANT SELECT, INSERT ON public.audit_log TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.journal_entries, public.notifs, public.versements TO authenticated;
GRANT SELECT ON
  public.aps,
  public.payment_transactions,
  public.preinscriptions,
  public.school_files,
  public.site_content,
  public.student_exit_events,
  public.student_primary_parent_history
TO authenticated;
GRANT SELECT, UPDATE ON public.school_profile TO authenticated;

-- Explicitly unavailable as direct tables to authenticated; only secure RPCs use them.
REVOKE ALL ON public.payment_receipt_counters, public.push_subscriptions FROM authenticated;

-- Only this private audit/outbox view is directly readable, still protected by RLS.
GRANT SELECT ON private.student_exit_notification_outbox TO authenticated;

-- Functions are closed by default, then re-opened explicitly.
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA public FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA private FROM PUBLIC, anon, authenticated;

-- Server-side Edge Functions/admin client may invoke all public RPC contracts.
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO service_role;

-- Public/anonymous entry points.
GRANT EXECUTE ON FUNCTION public.schoolsafe_health_check() TO anon;
GRANT EXECUTE ON FUNCTION public.submit_preinscription(jsonb) TO anon;
-- Present in current Cloud grants; function itself still enforces Direction 1 and therefore anon cannot perform the action.
GRANT EXECUTE ON FUNCTION public.restore_administrative_document(text) TO anon;

-- Authenticated private helpers used by RLS or direct wrapper execution in the current contract.
GRANT EXECUTE ON FUNCTION private.build_fee_summary(text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_notify(text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_scan() TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_view_class(text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.can_view_student(text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.compute_payment_state(text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.current_app_role() TO authenticated;
GRANT EXECUTE ON FUNCTION private.current_app_user_id() TO authenticated;
GRANT EXECUTE ON FUNCTION private.current_school_year() TO authenticated;
GRANT EXECUTE ON FUNCTION private.is_direction() TO authenticated;
GRANT EXECUTE ON FUNCTION private.is_direction_any() TO authenticated;
GRANT EXECUTE ON FUNCTION private.next_payment_receipt_no(text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.owns_student(text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.parent_has_child_in_class(text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.set_administrative_document_archive_state(text,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION private.teacher_has_class_access(text) TO authenticated;
GRANT EXECUTE ON FUNCTION private.teaches_class(text) TO authenticated;

-- Authenticated public RPCs.
GRANT EXECUTE ON FUNCTION public.acknowledge_my_notification(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.archive_administrative_document(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.archive_my_notification(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_student_exit_preparation(text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_gate_access_status(text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.confirm_parent_phone_password_change() TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_administrative_document(text,text,text,date,date,date,text,numeric,text,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.disable_my_push_device(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.evaluate_student_access(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_archive_summary() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_cashier_student_fee_detail(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_gate_access_status(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_access_state() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_notification_center(integer,timestamp with time zone,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_palmares_publications() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_my_push_device_status() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_parent_fee_summary(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_parent_pedagogic_context(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_safe_settings() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_scanner_aps() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_scanner_students() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_student_exit_status(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_student_pickup_context(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.grant_payment_access_exception(text,timestamp with time zone,text,timestamp with time zone) TO authenticated;
GRANT EXECUTE ON FUNCTION public.issue_student_qr(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_my_notification_opened(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_my_notification_read(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_salary_paid(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.prepare_student_exit(text,text,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reactivate_school_account(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_entry_scan(text,text,text,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_exit_scan(text,text,text,text,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_payment_transaction(text,numeric,text,text,text,text,date,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_scan_incident(text,text,text,text,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.refuse_preinscription(text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.register_push_device(text,text,text,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.restore_administrative_document(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reverse_payment_transaction(text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_payment_access_exception(text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_authorized_pickup_person(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_parent_phone_profile(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_primary_parent_pickup_identity(text,text,text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_school_user_profile(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_school_user_profile_email(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_site_content(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_student_profile(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.scan_student_exit_at_gate(text,text,text,text,text,text,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.schoolsafe_health_check() TO authenticated;
GRANT EXECUTE ON FUNCTION public.send_school_notification(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_authorized_pickup_person_status(text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_student_primary_parent(text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_preinscription(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.suspend_school_account(text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.validate_preinscription(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.validate_student_exit(text,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.verify_student_qr(text,text,text) TO authenticated;

COMMIT;
