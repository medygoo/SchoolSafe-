# P0-30b — Contrat backend Web Push pour Claude

Statut : **préparation collaborative, non déployée**.

Cette note répond à la demande de Claude dans #66 après la PR #77. Elle ne remplace pas le centre de notifications déjà livré ; elle complète uniquement le transport externe.

## Décision commune

- La notification enregistrée dans `public.notifs` reste la **source de vérité**.
- Web Push sert uniquement d’alerte externe.
- Brevo reste réservé à l’Auth.
- FCM n’est plus la dépendance principale, mais son chemin existant n’est pas détruit tant que Web Push n’a pas passé les tests réels.
- Aucune écriture directe dans `public.push_subscriptions` depuis le navigateur.
- Aucune clé VAPID privée dans GitHub, Supabase public, le navigateur ou les logs.

## Ce que le Supabase réel possède déjà

Audit lecture seule du 10 août 2026 :

- `public.push_subscriptions` possède déjà `endpoint`, `auth`, `p256dh`, `provider`, `token`, `platform`, `app_instance_id`, `active`, `last_seen_at`, `last_success_at`, `failure_count` ;
- les contraintes acceptent déjà `provider='webpush'` avec `endpoint + auth + p256dh` ;
- la RLS est un refus total direct : `push_subscriptions_no_direct_access` ;
- `private.notification_push_outbox` accepte déjà les providers `fcm` et `webpush` ;
- `settings.vapid_public_key` existe déjà, mais sa valeur est actuellement vide ;
- `disable_my_push_device()` et `get_my_push_device_status()` sont déjà provider-neutres ;
- `dist/sw.js` existe déjà et porte déjà les handlers `push` et `notificationclick`.

Donc : **ne pas créer une deuxième table appareils, ne pas créer un deuxième Service Worker.**

## RPC frontend à ajouter

### `get_webpush_public_config()`

Aucun paramètre.

Retour :

```json
{
  "ok": true,
  "enabled": true,
  "vapid_public_key": "<clé publique seulement>"
}
```

Si la clé publique n’est pas configurée :

```json
{
  "ok": true,
  "enabled": false,
  "vapid_public_key": null
}
```

Le frontend ne doit pas considérer `Notification.permission='granted'` comme « appareil enregistré ». Il doit attendre le succès de l’enregistrement serveur.

### `register_webpush_device(...)`

Paramètres proposés :

```text
p_endpoint text
p_p256dh text
p_auth text
p_platform text = 'web'
p_app_instance_id text = null
p_device_label text = null
p_user_agent text = null
```

Retour attendu :

```json
{
  "ok": true,
  "code": "WEBPUSH_DEVICE_REGISTERED",
  "device_id": "push_...",
  "provider": "webpush",
  "platform": "web",
  "queued_notifications": 0
}
```

Codes de refus frontend :

- `AUTH_REQUIRED`
- `INVALID_WEBPUSH_ENDPOINT`
- `INVALID_WEBPUSH_KEY`
- `INVALID_PLATFORM`
- `VALIDATION_ERROR`

Le navigateur conserve le `device_id` retourné uniquement pour pouvoir demander plus tard sa désactivation par `disable_my_push_device(p_device_id)`.

## Service Worker à utiliser

Réutiliser **`dist/sw.js`**. Il contient déjà :

- `self.addEventListener('push', ...)`
- `self.addEventListener('notificationclick', ...)`

Le payload du VPS doit respecter le format que ce Service Worker sait déjà lire :

```json
{
  "title": "SchoolSafe — ...",
  "body": "...",
  "url": "./?page=notifications&notification=<id>",
  "tag": "schoolsafe-<notification_id>",
  "urgent": false
}
```

Pour une notification `privacy_level='sensitive'`, le serveur ne doit pas mettre le nom de l’enfant, le montant, la pièce d’identité ou une donnée médicale dans `title/body`. Il envoie un texte neutre puis l’application récupère le détail après Auth.

## File d’envoi backend

Le trigger actuel `private.queue_push_for_notification()` ne met en file que les appareils FCM. Il doit devenir provider-neutre :

- FCM actif avec `token` → file FCM ;
- Web Push actif avec `endpoint + p256dh + auth` → file Web Push.

Pour ne pas casser le dispatcher FCM existant :

- `claim_notification_push_batch()` reste le claim FCM et doit filtrer explicitement `provider='fcm'` ;
- ajouter `claim_webpush_notification_batch()` pour le worker VPS Web Push ;
- `complete_notification_push_delivery()` reste commun aux deux transports.

Le worker VPS Web Push utilisera VAPID côté serveur et appellera uniquement les RPC service-role de claim/complete. La clé privée VAPID reste dans l’environnement du VPS.

## Contrat frontend Claude

Après feu vert backend réel :

1. lire `get_webpush_public_config()` ;
2. si `enabled=false`, afficher honnêtement « transport externe non configuré » ;
3. demander la permission uniquement après un geste utilisateur ;
4. attendre `navigator.serviceWorker.ready` ;
5. récupérer ou créer la subscription avec la clé VAPID publique ;
6. envoyer `endpoint`, `keys.p256dh`, `keys.auth` à `register_webpush_device()` ;
7. considérer l’appareil comme enregistré **uniquement** si la RPC retourne `ok:true` ;
8. afficher le statut réel via `get_my_push_device_status()` ;
9. désactiver via `disable_my_push_device()` quand l’utilisateur le demande ;
10. ne jamais écrire directement dans `push_subscriptions`.

### iPhone / iPad

Le parcours frontend devra distinguer le cas iOS/iPadOS où l’application doit être installée sur l’écran d’accueil avant de demander les notifications. Ne pas afficher un faux bouton « Activer » si le contexte ne permet pas l’abonnement.

## Tests croisés avant de dire « fonctionnel »

Claude :

- Android Chrome ;
- Chrome/Edge/Firefox desktop ;
- iPhone/iPad PWA écran d’accueil ;
- permission accordée/refusée/révoquée ;
- abonnement déjà existant ;
- changement de compte sur le même appareil ;
- logout/login ;
- navigateur hors ligne puis retour réseau ;
- clic sur notification ouvrant la bonne page.

ChatGPT/backend :

- RLS refuse toute lecture/écriture directe des abonnements ;
- RPC ne peut enregistrer que l’utilisateur courant ;
- endpoint dupliqué réaffecté proprement au compte courant ;
- ancien endpoint désactivé lorsqu’un même `app_instance_id` change ;
- aucune clé privée dans la DB publique ;
- file Web Push séparée du claim FCM ;
- endpoint expiré peut être désactivé ;
- payload sensible neutralisé ;
- retry borné et pas de boucle infinie.

## Important pour Claude

Tu peux proposer une amélioration de ce contrat avant raccordement. Si tu vois un besoin frontend que le contrat ne couvre pas, signale-le dans #69/#66 : on ajuste ensemble avant de publier.

Ne réintroduis pas l’ancien `pushSync('push_subscriptions', ...)`.
