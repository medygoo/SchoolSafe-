# Ordre d'installation du baseline SchoolSafe VPS

Ne pas exécuter ce dossier par simple ordre alphabétique sans suivre cette liste.

## Préconditions obligatoires

1. Exécuter `../00_PRECHECK_READONLY.sql`.
2. Faire une sauvegarde PostgreSQL VPS fraîche.
3. Vérifier l'intégrité gzip.
4. Vérifier la copie Backblaze B2.
5. Confirmer que `public`/`private` ne contiennent pas une ancienne installation SchoolSafe non identifiée.

## Ordre SQL

1. `01_schemas_extensions.sql`
2. `02a_tables_private.sql`
3. `02b_tables_public_a_c.sql`
4. `02c_tables_public_d_m.sql`
5. `02d_tables_public_n_r.sql`
6. `02e_tables_public_s_z.sql`
7. `03a_functions_private_core.sql`
8. `03c_function_private_save_school_user.sql`
9. `03d_functions_private_parent_audit.sql`
10. `03b_functions_private_accounts.sql`
11. `03e_functions_private_payments.sql`
12. `03f_functions_private_notifications_exit.sql`
13. `03g_functions_private_files_admin.sql`
14. `03h_functions_private_palmares_aps.sql`
15. `03i_function_private_receipt_counter.sql`
16. `04a_functions_public_auth_login.sql`
17. `04b_functions_public_phone_access.sql`
18. `04c_functions_public_account_lifecycle.sql`
19. `04d_functions_public_payments.sql`
20. `04e_functions_public_scanner.sql`
21. `04f_functions_public_pickup.sql`
22. `04g_functions_public_exit.sql`
23. `04h_functions_public_notifications.sql`
24. `04i_functions_public_push.sql`
25. `04j_functions_public_admin_site.sql`
26. `04k_functions_public_student_pedagogy.sql`
27. `04l_functions_public_palmares_payroll.sql`
28. `04m_functions_public_preinscription.sql`
29. `04n_function_public_validate_preinscription.sql`
30. `05_defaults.sql`
31. `06a_constraints_primary_unique.sql`
32. `06b_constraints_check.sql`
33. `06c_constraints_foreign_keys.sql`
34. `07_indexes.sql`
35. `08_triggers.sql`
36. `09a_rls_state.sql`
37. `09b_policies_a_m.sql`
38. `09c_policies_n_z.sql`
39. `10_grants.sql`
40. `11_seed_non_sensitive_config.sql`
41. `12_runtime_secret_bootstrap.sql`
42. `99_verify_baseline.sql`

## Important

- Les schémas internes Supabase `auth`, `storage`, `realtime` ne sont jamais restaurés depuis le Cloud.
- Deux triggers SchoolSafe sont ajoutés sur `auth.users`, mais la table `auth.users` reste celle du VPS.
- Direction 1 n'est pas créée par ce baseline. Sa liaison Auth/application est une étape de migration séparée.
- Les Edge Functions et leurs secrets sont une étape séparée après validation SQL.
- Aucun basculement frontend avant validation SQL + Auth + Edge Functions + R2 + notifications.
