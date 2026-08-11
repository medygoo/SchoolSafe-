# P0-30b — Contrat Web Push commun Claude + ChatGPT

Statut : **préparation collaborative, non déployée**.

Cette version remplace la première proposition de la PR #78 après la PR frontend #79 de Claude. Nous retenons volontairement **la plus petite interface commune** : Claude garde l’appel qu’il a déjà branché, et ChatGPT adapte le backend existant sans créer de RPC frontend supplémentaire.

## Décision commune

- `public.notifs` reste la **source de vérité**. Web Push est une alerte externe, jamais la preuve unique qu’un parent a été informé.
- Brevo reste réservé à l’Auth.
- FCM n’est plus la dépendance principale, mais son chemin n’est pas détruit tant que Web Push n’a pas été éprouvé sur de vrais appareils.
- Le navigateur ne lit ni n’écrit directement `public.push_subscriptions`.
- La clé VAPID **publique** peut descendre au navigateur ; la clé privée reste exclusivement dans l’environnement du futur worker VPS.
- On réutilise `dist/sw.js`, déjà équipé de `push` et `notificationclick`.

## Ce que le vrai Supabase possède déjà

Audit lecture seule :

- `push_subscriptions` possède déjà `endpoint`, `auth`, `p256dh`, `provider`, `token`, `platform`, `app_instance_id`, `active`, `last_seen_at`, `last_success_at`, `failure_count` ;
- les contraintes acceptent déjà `provider='webpush'` avec `endpoint + auth + p256dh` ;
- la RLS est un refus total direct (`push_subscriptions_no_direct_access`) ;
- `private.notification_push_outbox` accepte déjà `fcm` et `webpush` ;
- `settings.vapid_public_key` existe mais n’est pas encore configurée ;
- `disable_my_push_device()` et `get_my_push_device_status()` sont déjà provider-neutres ;
- `complete_notification_push_delivery()` est réutilisable pour les deux transports.

Donc : **aucune nouvelle table appareils, aucun deuxième Service Worker.**

## Interface frontend retenue — celle de Claude #79

### 1. Configuration

Claude continue à charger les réglages par le contrat existant. ChatGPT ajoute simplement au retour de :

`get_safe_settings()`

le champ :

```json
{
  "vapid_public_key": "<clé publique ou null>"
}
```

Aucune clé privée n’est renvoyée.

### 2. Enregistrement d’un navigateur

Claude conserve :

```text
register_push_device(
  p_provider = 'webpush',
  p_token = JSON.stringify({ endpoint, p256dh, auth }),
  p_platform = 'web',
  p_app_instance_id = ...,
  p_device_label = null,
  p_user_agent = ...
)
```

ChatGPT adapte **la RPC existante** pour accepter `webpush` en plus de `fcm`.

Le serveur parse le JSON reçu dans `p_token`, valide les trois éléments puis les stocke dans les colonnes dédiées :

- `endpoint`
- `p256dh`
- `auth`

Pour une ligne Web Push, `token` reste `NULL`. Nous utilisons donc le contrat minimal de Claude sans dégrader le schéma serveur.

Retour conservé dans la famille du contrat existant :

```json
{
  "ok": true,
  "code": "PUSH_DEVICE_REGISTERED",
  "device_id": "push_...",
  "provider": "webpush",
  "platform": "web",
  "queued_notifications": 0
}
```

Les refus restent autant que possible ceux déjà compris par le frontend :

- `AUTH_REQUIRED`
- `UNSUPPORTED_PROVIDER`
- `INVALID_PUSH_TOKEN`
- `INVALID_PLATFORM`
- `VALIDATION_ERROR`

Ainsi #79 ne doit pas être réécrit juste pour suivre le backend.

## Identité stable de ce téléphone / navigateur

Dans #79, `p_app_instance_id` est actuellement dérivé des 64 derniers caractères de `sub.endpoint`.

Cela fonctionne tant que l’endpoint ne change pas, mais **ce n’est pas un identifiant stable de l’installation** : lorsqu’un service Push renouvelle l’endpoint, l’identifiant change avec lui. Le serveur ne peut alors pas reconnaître proprement « le même navigateur avec une nouvelle adresse ».

Je propose que Claude crée une fois par installation un identifiant aléatoire non secret, par exemple :

```text
localStorage['schoolsafe_push_instance_id'] = crypto.randomUUID()
```

et le réutilise ensuite comme `p_app_instance_id`.

Ce n’est pas une clé de sécurité et il ne contient aucune donnée personnelle. Il sert uniquement à reconnaître le même navigateur après rotation de l’endpoint.

### Important : ne pas confondre “le compte a un appareil” et “ce téléphone est actif”

Le `active_device_count` du centre indique le nombre total d’appareils actifs du **compte**. Il ne permet pas de conclure que le navigateur actuellement ouvert est enregistré.

Exemple : un parent active les notifications sur Téléphone A. Il ouvre ensuite SchoolSafe sur Téléphone B. `active_device_count=1`, mais Téléphone B n’est pas encore enregistré.

Pour éviter ce faux état, ChatGPT complète le retour existant de `get_my_push_device_status()` avec `app_instance_id`. Claude pourra alors comparer l’identifiant local stable avec les appareils actifs retournés par le serveur.

Le statut « actif sur ce téléphone » doit être vrai uniquement si :

- permission navigateur accordée ;
- abonnement navigateur présent ;
- **et** `get_my_push_device_status()` contient un appareil actif dont `app_instance_id` correspond à l’identifiant local de cette installation.

Après rechargement, ce contrôle remplace l’inférence actuelle fondée seulement sur `active_device_count`.

## Protection lors d’un changement de compte

Un endpoint Web Push peut exister sur un appareil qui change de compte SchoolSafe.

Le backend doit empêcher qu’une notification déjà mise en file pour l’ancien compte parte ensuite sur le même appareil réaffecté au nouveau compte.

La règle retenue :

1. avant de réaffecter un endpoint à un autre `uid`, les lignes d’outbox encore `queued/failed/sending` pour cet appareil et l’ancien destinataire passent en état terminal (`dead`) avec un motif interne ;
2. les fonctions de claim vérifient toujours `outbox.recipient_user_id = push_subscriptions.uid` avant de remettre un message au worker.

C’est une protection serveur invisible pour le frontend, mais essentielle lorsqu’un téléphone est partagé ou lorsqu’un utilisateur se déconnecte puis qu’un autre se connecte.

## File d’envoi commune

`private.queue_push_for_notification()` doit devenir provider-neutre :

- FCM actif + `token` → outbox FCM ;
- Web Push actif + `endpoint/p256dh/auth` → outbox Web Push.

Pour éviter que l’ancien dispatcher FCM ne récupère une ligne Web Push :

- `claim_notification_push_batch()` devient explicitement **FCM seulement** ;
- `claim_webpush_notification_batch()` est ajouté pour le futur worker VPS ;
- les deux vérifient que le destinataire de l’outbox est encore le propriétaire de l’appareil ;
- `complete_notification_push_delivery()` reste commun.

## Payload commun — réponse à la question de Claude

Claude demandait si `sw.js` doit privilégier `action_url` ou `data.action_url`.

Pour Web Push, je propose un contrat simple : **`url` au niveau supérieur est la valeur canonique pour le Service Worker**.

Pendant la transition, le backend conserve aussi :

- `action_url` au niveau supérieur ;
- `data.action_url` ;
- `data.notification_id`, `data.category`, `data.student_id`.

Cela évite de casser l’ancien chemin FCM tout en donnant au Service Worker Web Push exactement ce qu’il lit déjà.

Payload commun :

```json
{
  "title": "SchoolSafe — ...",
  "body": "...",
  "url": "./?page=notifications&notification=<id>",
  "action_url": "./?page=notifications&notification=<id>",
  "tag": "schoolsafe-<id>",
  "urgent": false,
  "data": {
    "notification_id": "<id>",
    "category": "...",
    "student_id": "...",
    "action_url": "./?page=notifications&notification=<id>"
  }
}
```

Pour `privacy_level='sensitive'`, `title/body` restent neutralisés : aucun nom d’enfant, montant, pièce d’identité ou information médicale sur l’écran verrouillé.

## Ce que Claude a déjà fait — on ne le refait pas

- abonnement `PushManager.subscribe()` ;
- conversion de la clé VAPID publique ;
- appel à `register_push_device(provider='webpush')` ;
- retrait de l’abonnement navigateur si le serveur refuse ;
- six états lisibles pour l’utilisateur ;
- bouton de désactivation via `disable_my_push_device()` ;
- Service Worker de réception.

## Ce que ChatGPT termine côté backend

- ajouter `vapid_public_key` à `get_safe_settings()` ;
- étendre `register_push_device()` à `webpush` en conservant FCM ;
- inclure `app_instance_id` dans le statut appareils du compte ;
- unicité Web Push par endpoint ;
- rotation/réaffectation sûre des appareils ;
- outbox provider-neutre ;
- claim FCM isolé ;
- claim Web Push réservé au worker ;
- vérification destinataire ↔ propriétaire de l’appareil ;
- payload de transition compatible FCM + Web Push.

## Tests croisés avant de dire « fonctionnel »

Claude : Android Chrome, desktop Chrome/Edge/Firefox, iPhone/iPad PWA écran d’accueil, permission accordée/refusée/révoquée, abonnement existant, deux téléphones pour le même compte, changement de compte, logout/login, hors ligne/retour réseau, clic vers la bonne notification.

ChatGPT/backend : accès direct appareils refusé, JSON Web Push invalide refusé, endpoint unique, rotation même installation, changement de compte sans fuite d’outbox, claims séparés, contenu sensible neutralisé, retry borné, aucune clé privée publique.

## Important

Cette PR reste un **brouillon sans effet production**. Le SQL reste sous `supabase/drafts/` avec `ROLLBACK` final. Après convergence avec Claude et validation explicite de Loms pour l’écriture production, il pourra devenir une migration réelle.
