# P0-30 — Centre unique de notifications et push gratuit

Date : 6 août 2026  
Décisions fonctionnelles : Loms  
Backend, sécurité et recettes : ChatGPT  
Front-end et recette navigateur : Claude

## État production

Les migrations suivantes sont actives dans Supabase :

- `p0_30_unified_notification_center_core`
- `p0_30a_notification_actor_column_fix`
- `p0_31_push_outbox_and_exit_notification_alignment`
- `p0_32_notification_actor_and_device_token_hardening`

Edge Function active :

- `dispatch-school-push`, version 1, `verify_jwt=true`

Le centre interne et la file push sont prêts. L’envoi FCM réel reste volontairement bloqué jusqu’à l’ajout des secrets Firebase :

- `FIREBASE_PROJECT_ID`
- `FIREBASE_CLIENT_EMAIL`
- `FIREBASE_PRIVATE_KEY`

Aucun secret ne doit être déposé dans GitHub, le HTML ou le JavaScript public.

## Décision officielle

SchoolSafe utilise :

1. une notification conservée dans l’application ;
2. une notification push gratuite sur le téléphone ;
3. un lien qui ouvre directement la bonne page de SchoolSafe.

Les sorties d’élèves n’utilisent plus de file automatique WhatsApp ou e-mail. WhatsApp reste uniquement une solution manuelle de secours.

## Confidentialité sur l’écran verrouillé

Les catégories sensibles n’affichent pas le détail complet sur le téléphone :

- urgence ;
- sécurité ;
- convocation ;
- paiement et reçu ;
- résultat ;
- préparation, confirmation, refus ou expiration de sortie.

Exemple de push :

> SchoolSafe — Convocation  
> Une information concernant votre enfant est disponible. Ouvrez SchoolSafe.

Le détail complet reste dans l’application après authentification.

## Catégories disponibles

- `information`
- `emergency`
- `convocation`
- `exit_prepared`
- `exit_confirmed`
- `exit_cancelled`
- `exit_refused`
- `exit_expired`
- `absence`
- `lateness`
- `homework`
- `assessment`
- `result_available`
- `teacher_message`
- `direction_message`
- `announcement`
- `administrative_reminder`
- `payment`
- `receipt_available`
- `schedule_change`
- `document_available`
- `security`

Les urgences, convocations et notifications de sécurité exigent automatiquement un accusé : « J’ai pris connaissance ».

## Matrice serveur d’envoi

### Direction 1

Peut envoyer toutes les catégories et effectuer une diffusion par rôle.

### Direction 2

Peut envoyer les informations pédagogiques, administratives et de sécurité, mais jamais `payment` ou `receipt_available`.

### Enseignant

Peut notifier uniquement les parents des élèves de ses classes, pour :

- information ;
- absence ;
- retard ;
- devoir ;
- interrogation ;
- résultat ;
- message enseignant ;
- changement d’horaire ;
- préparation de sortie.

### Gardien

Peut notifier uniquement le parent principal de l’élève concerné, pour :

- information ;
- urgence ;
- sécurité ;
- confirmation ou refus de sortie.

### Caisse

Peut notifier uniquement les parents, pour :

- information ;
- rappel administratif ;
- paiement ;
- reçu disponible.

### Parent

Ne crée pas de notification destinée aux autres profils. Il lit, ouvre, accuse et archive ses propres notifications.

## RPC front-end

### Appareil et autorisation push

```text
register_push_device(
  p_provider,
  p_token,
  p_platform,
  p_app_instance_id,
  p_device_label,
  p_user_agent
)
```

Utiliser `p_provider='fcm'`.

```text
get_my_push_device_status()
disable_my_push_device(p_device_id)
```

Le jeton FCM n’est jamais lisible depuis le navigateur. Ne pas lire ou écrire directement `push_subscriptions`.

### Centre de notifications

```text
get_my_notification_center(p_limit, p_before, p_category)
mark_my_notification_opened(p_notification_id)
mark_my_notification_read(p_notification_id)
acknowledge_my_notification(p_notification_id)
archive_my_notification(p_notification_id)
```

Une notification n’est jamais supprimée. « Archiver » la masque du centre courant tout en conservant l’historique.

### Création

```text
send_school_notification(p_notification jsonb)
```

Champs principaux :

- `recipient_user_id` ou `recipient_user_ids` ;
- `student_id` ;
- `class_id` ;
- `target_role`, Direction 1 seulement ;
- `category` ;
- `title` ;
- `message` ;
- `action_url` ;
- `priority` ;
- `privacy_level` ;
- `requires_ack` ;
- `source_type` ;
- `source_id` ;
- `dedupe_key` ;
- `data`.

Ne jamais contourner un refus par une écriture directe dans `notifs`.

## Sortie des élèves

`private.queue_student_exit_notification` crée désormais :

- la notification dans SchoolSafe ;
- une tâche push pour chaque appareil actif du parent.

Il ne crée plus de tâche automatique WhatsApp ou e-mail.

La file push utilise `private.notification_push_outbox`. Elle est invisible au navigateur.

## Dispatcher FCM

`dispatch-school-push` :

- n’est accessible qu’à Direction 1 ou au service serveur ;
- prend un lot avec `claim_notification_push_batch` ;
- utilise FCM HTTP v1 ;
- confirme chaque résultat avec `complete_notification_push_delivery` ;
- réessaie les erreurs temporaires ;
- désactive un jeton définitivement invalide ;
- ne renvoie jamais les jetons dans sa réponse.

Le dispatcher renvoie `PUSH_NOT_CONFIGURED` tant que les trois secrets Firebase sont absents. Il ne réclame aucune tâche dans ce cas.

## Travail Claude

1. Ajouter la configuration publique Firebase Web, sans secret serveur.
2. Créer le service worker de messagerie FCM.
3. Demander l’autorisation à la suite d’un bouton explicite : « Activer les notifications ».
4. Obtenir le token FCM et appeler `register_push_device`.
5. Afficher l’état : activé, refusé, appareil enregistré ou aucun appareil.
6. Construire un centre unique avec filtres, compteur non lu et compteur « prise de connaissance requise ».
7. Ouvrir la notification ciblée depuis le push.
8. Afficher « J’ai pris connaissance » seulement lorsque `requires_ack=true`.
9. Utiliser « Archiver », jamais « Supprimer ».
10. Ne jamais afficher le token FCM ni lire `push_subscriptions`.
11. Pour les événements métiers, appeler `send_school_notification` ou les RPC métier déjà existantes.
12. Ne jamais annoncer « push envoyé » sur la seule création : utiliser `push_status` (`no_device`, `queued`, `sent`, `failed`).

## Recette navigateur attendue

- parent refuse l’autorisation : l’application continue avec notifications internes ;
- parent accepte : appareil enregistré ;
- token renouvelé : ancien token désactivé ;
- urgence : texte discret sur écran verrouillé ;
- ouverture du push : bonne notification ouverte ;
- lecture et accusé enregistrés ;
- archivage sans suppression ;
- même `dedupe_key` : un seul message ;
- enseignant hors de sa classe : refus ;
- Direction 2 essaye une notification financière : refus ;
- gardien essaye de notifier un autre parent : refus ;
- sortie préparée : notification interne + push, aucun WhatsApp automatique ;
- téléphone sans token : `push_status=no_device` ;
- jeton invalide : appareil désactivé sans bloquer le centre interne.

## Recettes serveur effectuées

Toutes les recettes ont utilisé `ROLLBACK` et n’ont laissé aucune donnée fictive :

- appareil FCM enregistré par le profil connecté ;
- notification urgente créée ;
- doublon refusé par `dedupe_key` ;
- ouverture, lecture, accusé et archivage ;
- suppression directe refusée ;
- écriture directe d’un appareil refusée ;
- convocation sensible : détail absent du push ;
- prise de lot, livraison et confirmation ;
- préparation de sortie : push créé, zéro tâche WhatsApp et zéro tâche e-mail ;
- tentative d’usurper l’auteur : auteur remplacé par le profil réel ;
- jeton FCM invisible au navigateur.
