# Migrations Supabase SchoolSafe

Ce dossier doit contenir les migrations SQL versionnées du projet.

## Migration appliquée

- Version Supabase : `20260802205234`
- Nom : `add_payment_control_backend_v1`
- Projet : `SchoolSafe`
- État : appliquée avec succès le 2 août 2026

Cette migration ajoute le backend du contrôle des frais : obligations, transactions, allocations, dérogations, journal de scan, RLS et RPC sécurisées.

Le SQL complet est actuellement enregistré dans l'historique de migrations Supabase. Lors de la prochaine synchronisation CLI, exécuter un `supabase db pull` vers une branche locale propre afin d'importer l'historique complet dans ce dossier sans inventer ni réécrire la migration à la main.

Ne jamais modifier rétroactivement une migration déjà appliquée. Toute correction doit utiliser une nouvelle migration.
