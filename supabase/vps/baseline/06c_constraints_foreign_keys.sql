-- SchoolSafe VPS baseline - 06c foreign keys
-- Requires all 02* tables and 06a PK/UNIQUE constraints.
-- References to auth.users deliberately point to the VPS's OWN Supabase Auth schema.

BEGIN;
SET LOCAL search_path = public, private, auth;

ALTER TABLE private.account_invitations ADD CONSTRAINT account_invitations_auth_user_id_fkey FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE private.notification_push_outbox ADD CONSTRAINT notification_push_outbox_device_id_fkey FOREIGN KEY (device_id) REFERENCES push_subscriptions(id) ON DELETE RESTRICT;
ALTER TABLE private.notification_push_outbox ADD CONSTRAINT notification_push_outbox_notification_id_fkey FOREIGN KEY (notification_id) REFERENCES notifs(id) ON DELETE CASCADE;
ALTER TABLE private.notification_push_outbox ADD CONSTRAINT notification_push_outbox_recipient_user_id_fkey FOREIGN KEY (recipient_user_id) REFERENCES users(id) ON DELETE RESTRICT;
ALTER TABLE private.parent_phone_access_requests ADD CONSTRAINT parent_phone_access_requests_app_user_id_fkey FOREIGN KEY (app_user_id) REFERENCES users(id) ON DELETE CASCADE;
ALTER TABLE private.parent_phone_access_requests ADD CONSTRAINT parent_phone_access_requests_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES users(id);
ALTER TABLE private.student_exit_notification_outbox ADD CONSTRAINT student_exit_notification_outbox_exit_event_id_fkey FOREIGN KEY (exit_event_id) REFERENCES student_exit_events(id) ON DELETE RESTRICT;
ALTER TABLE private.student_exit_notification_outbox ADD CONSTRAINT student_exit_notification_outbox_recipient_user_id_fkey FOREIGN KEY (recipient_user_id) REFERENCES users(id) ON DELETE RESTRICT;

ALTER TABLE public.administrative_documents ADD CONSTRAINT administrative_documents_archived_by_fkey FOREIGN KEY (archived_by) REFERENCES users(id) ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE public.administrative_documents ADD CONSTRAINT administrative_documents_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(id) ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE public.administrative_documents ADD CONSTRAINT administrative_documents_document_type_id_fkey FOREIGN KEY (document_type_id) REFERENCES administrative_document_types(id) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE public.administrative_documents ADD CONSTRAINT administrative_documents_restored_by_fkey FOREIGN KEY (restored_by) REFERENCES users(id) ON UPDATE CASCADE ON DELETE SET NULL;
ALTER TABLE public.advances ADD CONSTRAINT advances_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE public.aps ADD CONSTRAINT aps_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES users(id) ON DELETE RESTRICT;
ALTER TABLE public.aps ADD CONSTRAINT aps_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE RESTRICT;
ALTER TABLE public.aps ADD CONSTRAINT aps_proposed_by_fkey FOREIGN KEY (proposed_by) REFERENCES users(id) ON DELETE RESTRICT;
ALTER TABLE public.aps ADD CONSTRAINT aps_sid_fkey FOREIGN KEY (sid) REFERENCES students(id) ON DELETE RESTRICT;
ALTER TABLE public.aps ADD CONSTRAINT aps_suspended_by_fkey FOREIGN KEY (suspended_by) REFERENCES users(id) ON DELETE RESTRICT;
ALTER TABLE public.notifs ADD CONSTRAINT notifs_created_by_user_id_fkey FOREIGN KEY (created_by_user_id) REFERENCES users(id) ON DELETE RESTRICT;
ALTER TABLE public.notifs ADD CONSTRAINT notifs_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE RESTRICT;
ALTER TABLE public.notifs ADD CONSTRAINT notifs_uid_fkey FOREIGN KEY (uid) REFERENCES users(id) ON DELETE RESTRICT;
ALTER TABLE public.payment_access_exceptions ADD CONSTRAINT payment_access_exceptions_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES users(id) ON DELETE RESTRICT;
ALTER TABLE public.payment_access_exceptions ADD CONSTRAINT payment_access_exceptions_revoked_by_fkey FOREIGN KEY (revoked_by) REFERENCES users(id) ON DELETE RESTRICT;
ALTER TABLE public.payment_access_exceptions ADD CONSTRAINT payment_access_exceptions_sid_fkey FOREIGN KEY (sid) REFERENCES students(id) ON DELETE CASCADE;
ALTER TABLE public.payment_allocations ADD CONSTRAINT payment_allocations_obligation_id_fkey FOREIGN KEY (obligation_id) REFERENCES student_fee_obligations(id) ON DELETE RESTRICT;
ALTER TABLE public.payment_allocations ADD CONSTRAINT payment_allocations_transaction_id_fkey FOREIGN KEY (transaction_id) REFERENCES payment_transactions(id) ON DELETE RESTRICT;
ALTER TABLE public.payment_scan_log ADD CONSTRAINT payment_scan_log_checked_by_fkey FOREIGN KEY (checked_by) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE public.payment_scan_log ADD CONSTRAINT payment_scan_log_sid_fkey FOREIGN KEY (sid) REFERENCES students(id) ON DELETE CASCADE;
ALTER TABLE public.payment_transactions ADD CONSTRAINT payment_transactions_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES users(id) ON DELETE RESTRICT;
ALTER TABLE public.payment_transactions ADD CONSTRAINT payment_transactions_reversed_by_fkey FOREIGN KEY (reversed_by) REFERENCES users(id) ON DELETE RESTRICT;
ALTER TABLE public.payment_transactions ADD CONSTRAINT payment_transactions_sid_fkey FOREIGN KEY (sid) REFERENCES students(id) ON DELETE RESTRICT;
ALTER TABLE public.payments ADD CONSTRAINT payments_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES users(id) ON DELETE RESTRICT;
ALTER TABLE public.preinscriptions ADD CONSTRAINT preinscriptions_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE public.preinscriptions ADD CONSTRAINT preinscriptions_student_id_fkey FOREIGN KEY (student_id) REFERENCES students(id) ON DELETE SET NULL;
ALTER TABLE public.preinscriptions ADD CONSTRAINT preinscriptions_traite_par_fkey FOREIGN KEY (traite_par) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE public.push_subscriptions ADD CONSTRAINT push_subscriptions_uid_fkey FOREIGN KEY (uid) REFERENCES users(id) ON DELETE RESTRICT;
ALTER TABLE public.salaries ADD CONSTRAINT salaries_user_id_fkey FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE public.scan_log ADD CONSTRAINT scan_log_exit_event_id_fkey FOREIGN KEY (exit_event_id) REFERENCES student_exit_events(id) ON DELETE RESTRICT;
ALTER TABLE public.school_files ADD CONSTRAINT school_files_administrative_document_id_fkey FOREIGN KEY (administrative_document_id) REFERENCES administrative_documents(id) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE public.school_files ADD CONSTRAINT school_files_archived_by_fkey FOREIGN KEY (archived_by) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.school_files ADD CONSTRAINT school_files_cahier_prep_id_fkey FOREIGN KEY (cahier_prep_id) REFERENCES cahier_prep(id) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE public.school_files ADD CONSTRAINT school_files_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.school_files ADD CONSTRAINT school_files_payment_transaction_id_fkey FOREIGN KEY (payment_transaction_id) REFERENCES payment_transactions(id) ON UPDATE CASCADE ON DELETE RESTRICT;
ALTER TABLE public.school_files ADD CONSTRAINT school_files_restored_by_fkey FOREIGN KEY (restored_by) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.school_files ADD CONSTRAINT school_files_uploaded_by_app_user_id_fkey FOREIGN KEY (uploaded_by_app_user_id) REFERENCES users(id) ON DELETE RESTRICT;
ALTER TABLE public.school_files ADD CONSTRAINT school_files_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.student_exit_events ADD CONSTRAINT student_exit_events_gate_scanned_by_user_id_fkey FOREIGN KEY (gate_scanned_by_user_id) REFERENCES users(id) ON DELETE RESTRICT;
ALTER TABLE public.student_exit_events ADD CONSTRAINT student_exit_events_parent_id_snapshot_fkey FOREIGN KEY (parent_id_snapshot) REFERENCES users(id) ON DELETE RESTRICT;
ALTER TABLE public.student_exit_events ADD CONSTRAINT student_exit_events_prepared_by_user_id_fkey FOREIGN KEY (prepared_by_user_id) REFERENCES users(id) ON DELETE RESTRICT;
ALTER TABLE public.student_exit_events ADD CONSTRAINT student_exit_events_sid_fkey FOREIGN KEY (sid) REFERENCES students(id) ON DELETE RESTRICT;
ALTER TABLE public.student_exit_events ADD CONSTRAINT student_exit_events_validated_by_user_id_fkey FOREIGN KEY (validated_by_user_id) REFERENCES users(id) ON DELETE RESTRICT;
ALTER TABLE public.student_fee_obligations ADD CONSTRAINT student_fee_obligations_created_by_fkey FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL;
ALTER TABLE public.student_fee_obligations ADD CONSTRAINT student_fee_obligations_fee_type_id_fkey FOREIGN KEY (fee_type_id) REFERENCES fee_types(id) ON DELETE RESTRICT;
ALTER TABLE public.student_fee_obligations ADD CONSTRAINT student_fee_obligations_sid_fkey FOREIGN KEY (sid) REFERENCES students(id) ON DELETE CASCADE;
ALTER TABLE public.student_primary_parent_history ADD CONSTRAINT student_primary_parent_history_changed_by_user_id_fkey FOREIGN KEY (changed_by_user_id) REFERENCES users(id) ON DELETE RESTRICT;
ALTER TABLE public.student_primary_parent_history ADD CONSTRAINT student_primary_parent_history_new_parent_id_fkey FOREIGN KEY (new_parent_id) REFERENCES users(id) ON DELETE RESTRICT;
ALTER TABLE public.student_primary_parent_history ADD CONSTRAINT student_primary_parent_history_old_parent_id_fkey FOREIGN KEY (old_parent_id) REFERENCES users(id) ON DELETE RESTRICT;
ALTER TABLE public.student_primary_parent_history ADD CONSTRAINT student_primary_parent_history_sid_fkey FOREIGN KEY (sid) REFERENCES students(id) ON DELETE RESTRICT;
ALTER TABLE public.users ADD CONSTRAINT users_access_removed_by_fkey FOREIGN KEY (access_removed_by) REFERENCES users(id) ON DELETE RESTRICT;
ALTER TABLE public.users ADD CONSTRAINT users_auth_user_id_fkey FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

COMMIT;
