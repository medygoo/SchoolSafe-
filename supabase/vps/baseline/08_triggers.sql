-- SchoolSafe VPS baseline - 08 triggers
-- Includes 28 application triggers plus 2 SchoolSafe triggers on auth.users.
-- The VPS keeps its own Supabase Auth tables; only these SchoolSafe hooks are added.

BEGIN;
SET LOCAL search_path = public, private, auth;

CREATE TRIGGER before_auth_user_access_ready BEFORE INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION private.guard_auth_user_access_ready();
CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION private.handle_new_auth_user();

CREATE TRIGGER trg_invitation_target_ready BEFORE INSERT OR UPDATE OF app_user_id ON private.account_invitations FOR EACH ROW EXECUTE FUNCTION private.guard_invitation_target_ready();
CREATE TRIGGER trg_phone_request_target_ready BEFORE INSERT OR UPDATE OF app_user_id ON private.parent_phone_access_requests FOR EACH ROW EXECUTE FUNCTION private.guard_phone_request_target_ready();

CREATE TRIGGER trg_administrative_document_types_updated BEFORE UPDATE ON public.administrative_document_types FOR EACH ROW EXECUTE FUNCTION private.touch_administrative_document_type();
CREATE TRIGGER trg_administrative_documents_fields BEFORE INSERT OR UPDATE ON public.administrative_documents FOR EACH ROW EXECUTE FUNCTION private.set_administrative_document_fields();
CREATE TRIGGER advances_sync_user_reference BEFORE INSERT OR UPDATE OF teacher_id, user_id ON public.advances FOR EACH ROW EXECUTE FUNCTION private.sync_payroll_user_reference();
CREATE TRIGGER aps_decision_notifications AFTER INSERT OR UPDATE OF approval_status ON public.aps FOR EACH ROW EXECUTE FUNCTION private.notify_aps_decision();
CREATE TRIGGER aps_max_three_guard BEFORE INSERT OR UPDATE OF sid, approval_status, active ON public.aps FOR EACH ROW EXECUTE FUNCTION private.enforce_max_three_accredited_people();
CREATE TRIGGER trg_conduct_period BEFORE INSERT OR UPDATE ON public.conduct FOR EACH ROW EXECUTE FUNCTION private.stamp_conduct_period();
CREATE TRIGGER notifs_protect_update BEFORE UPDATE ON public.notifs FOR EACH ROW EXECUTE FUNCTION private.protect_notification_update();
CREATE TRIGGER notifs_queue_push AFTER INSERT ON public.notifs FOR EACH ROW EXECUTE FUNCTION private.queue_push_for_notification();
CREATE TRIGGER notifs_stamp_metadata BEFORE INSERT ON public.notifs FOR EACH ROW EXECUTE FUNCTION private.stamp_notification_record();
CREATE TRIGGER palmares_archive_revision BEFORE UPDATE ON public.palmares_publications FOR EACH ROW EXECUTE FUNCTION private.archive_palmares_revision();
CREATE TRIGGER palmares_publication_notifications AFTER INSERT OR UPDATE ON public.palmares_publications FOR EACH ROW EXECUTE FUNCTION private.notify_palmares_publication();
CREATE TRIGGER trg_validate_payment_allocation BEFORE INSERT OR UPDATE ON public.payment_allocations FOR EACH ROW EXECUTE FUNCTION private.validate_payment_allocation();
CREATE TRIGGER trg_ptx_touch_updated_at BEFORE UPDATE ON public.payment_transactions FOR EACH ROW EXECUTE FUNCTION private.touch_payment_updated_at();
CREATE TRIGGER trg_payments_server_provenance BEFORE INSERT OR DELETE OR UPDATE ON public.payments FOR EACH ROW EXECUTE FUNCTION private.stamp_legacy_payment_provenance();
CREATE TRIGGER protect_profile_identity_fields BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION private.protect_profile_identity_fields();
CREATE TRIGGER salaries_sync_user_reference BEFORE INSERT OR UPDATE OF teacher_id, user_id ON public.salaries FOR EACH ROW EXECUTE FUNCTION private.sync_payroll_user_reference();
CREATE TRIGGER scan_event_notifications AFTER INSERT ON public.scan_log FOR EACH ROW EXECUTE FUNCTION private.notify_scan_event();
CREATE TRIGGER school_files_enforce_archive_audit BEFORE INSERT OR UPDATE OF archived_at, archived_by, restored_at, restored_by ON public.school_files FOR EACH ROW EXECUTE FUNCTION private.enforce_school_file_archive_audit();
CREATE TRIGGER school_files_validate_metadata BEFORE INSERT OR UPDATE OF owner_type, owner_id, category, academic_year, payment_transaction_id, cahier_prep_id, administrative_document_id ON public.school_files FOR EACH ROW EXECUTE FUNCTION private.validate_school_file_metadata();
CREATE TRIGGER trg_school_files_uploader_snapshot BEFORE INSERT OR UPDATE ON public.school_files FOR EACH ROW EXECUTE FUNCTION private.stamp_school_file_uploader();
CREATE TRIGGER trg_student_exit_history_guard BEFORE DELETE OR UPDATE ON public.student_exit_events FOR EACH ROW EXECUTE FUNCTION private.protect_student_exit_history();
CREATE TRIGGER trg_sfo_touch_updated_at BEFORE UPDATE ON public.student_fee_obligations FOR EACH ROW EXECUTE FUNCTION private.touch_payment_updated_at();
CREATE TRIGGER trg_primary_parent_history_immutable BEFORE DELETE OR UPDATE ON public.student_primary_parent_history FOR EACH ROW EXECUTE FUNCTION private.protect_primary_parent_history();
CREATE TRIGGER trg_students_primary_parent_history AFTER INSERT OR UPDATE OF pid, archived ON public.students FOR EACH ROW EXECUTE FUNCTION private.track_primary_parent_change();
CREATE TRIGGER trg_users_parent_access_ready BEFORE INSERT OR UPDATE OF role ON public.users FOR EACH ROW EXECUTE FUNCTION private.enforce_parent_access_ready_on_user();
CREATE TRIGGER users_disable_push_devices AFTER UPDATE OF status ON public.users FOR EACH ROW EXECUTE FUNCTION private.disable_push_devices_for_inactive_user();

COMMIT;
