# P0-30 — Vérification finale du 6 août 2026

## Production Supabase

Migrations actives :

- `p0_30_unified_notification_center_core`
- `p0_30a_notification_actor_column_fix`
- `p0_31_push_outbox_and_exit_notification_alignment`
- `p0_32_notification_actor_and_device_token_hardening`
- `p0_32a_explicit_device_registry_deny_policy`

Edge Function :

- `dispatch-school-push`
- version 1
- état `ACTIVE`
- `verify_jwt=true`

## Compte Direction 1

- nom : Loms Medy
- rôle : `direction`
- statut : `active`
- identité Auth reliée : oui

Le compte n’a pas été utilisé comme donnée de test et n’a pas été modifié.

## État des données après recettes

- notifications réelles ou fictives : 0
- appareils push : 0
- tâches push : 0
- notifications de test restantes : 0
- appareils de test restants : 0
- événements de sortie de test restants : 0

Toutes les recettes ont utilisé des transactions avec `ROLLBACK`.

## Contrats présents

- `send_school_notification`
- `register_push_device`
- `get_my_push_device_status`
- `get_my_notification_center`
- `mark_my_notification_opened`
- `mark_my_notification_read`
- `acknowledge_my_notification`
- `archive_my_notification`
- `claim_notification_push_batch`
- `complete_notification_push_delivery`

## Sécurité vérifiée

- RLS actif sur `notifs` ;
- RLS actif sur `push_subscriptions` ;
- politique explicite de refus direct sur `push_subscriptions` ;
- aucun `SELECT` direct du jeton pour `authenticated` ;
- aucun `INSERT` direct d’appareil pour `authenticated` ;
- aucune suppression directe de notification pour `authenticated` ;
- prise de lot push interdite à `authenticated` ;
- prise de lot push autorisée uniquement à `service_role` ;
- auteur d’une notification estampillé par le serveur ;
- contenu sensible absent du push de l’écran verrouillé.

## Sortie des élèves

La préparation de sortie crée :

- une notification dans SchoolSafe ;
- une tâche push si le parent possède un appareil actif.

Elle ne crée plus :

- de tâche WhatsApp automatique ;
- de tâche e-mail automatique.

## Seul blocage restant

L’envoi réel vers les téléphones ne peut pas commencer avant :

1. création ou connexion d’un projet Firebase ;
2. ajout des secrets serveur `FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY` dans Supabase ;
3. intégration par Claude du service worker FCM et du bouton « Activer les notifications ».

Les secrets Firebase ne doivent jamais être placés dans GitHub, le HTML ou le JavaScript public.
