# Vérification complète P0-20 — Parent par téléphone + WhatsApp

Date : 6 août 2026  
Branche : `agent/parent-phone-auth-v1`  
PR : #46  
Responsable backend : ChatGPT  
Responsable intégration, recette navigateur, fusion et publication : Claude

## 1. Décision prise par Loms et mise en œuvre

Loms a retenu un parcours Parent qui ne dépend pas de `cslesage.com`, LWS, Brevo ou SMTP :

- le numéro de téléphone est l'identifiant de connexion du Parent ;
- WhatsApp sert uniquement à transmettre manuellement un code temporaire ;
- le Parent remplace ce code à sa première connexion ;
- un même compte Parent peut être rattaché à plusieurs enfants ;
- Supabase reste la base des profils, relations, droits et données structurées ;
- Cloudflare R2 reste le stockage des photos et documents lourds ; ce lot ne modifie pas R2.

Le numéro privé communiqué par Loms dans la conversation n'est écrit ni dans GitHub, ni dans les migrations, ni dans les tests, ni dans un profil réel.

## 2. État réellement déployé dans Supabase

- téléphone normalisé au format E.164 ;
- formats RDC `08...`, `+243...`, `243...` réconciliés vers une valeur unique ;
- unicité globale du téléphone dans `public.users` ;
- `email` facultatif uniquement pour un Parent en canal `phone_whatsapp` ;
- e-mail toujours obligatoire pour Direction, Direction 2, Caisse, Enseignant et Gardien ;
- Direction 1 et Direction 2 autorisées à créer un Parent téléphone ;
- demandes privées `provision`, `reset`, `change_phone` ;
- code temporaire valable 30 minutes ;
- nouvelle demande limitée à une fois par minute pour le même Parent ;
- aucun accès aux données métier tant que le code temporaire n'a pas été remplacé ;
- confirmation du changement par comparaison de l'empreinte du hash Auth ;
- aucun mot de passe ou code stocké en clair ;
- préinscription téléphone sans e-mail acceptée ;
- `parent-phone-access` version 1 ACTIVE avec `verify_jwt=true`.

## 3. Défaut trouvé pendant la vérification et corrigé

La première recette profonde a révélé une vraie incompatibilité avec le déclencheur existant `protect_profile_identity_fields`.

Symptôme exact :

```text
42501 — Les champs d’identité et de rôle sont protégés
```

Le changement de code personnel pouvait être accepté par Supabase Auth, puis la synchronisation de `public.profiles` était refusée. Le même défaut pouvait toucher la finalisation d'un `reset` ou d'un changement de numéro.

Correction livrée et déployée :

```text
supabase/migrations/20260805235000_fix_parent_phone_profile_sync.sql
```

La correction :

- conserve la protection normale des champs d'identité ;
- déplace les anciennes implémentations sensibles dans le schéma `private` ;
- expose seulement trois enveloppes contrôlées ;
- autorise la synchronisation uniquement pour l'identifiant Auth exact placé dans un contexte transactionnel interne ;
- retire tout accès direct `anon`/`authenticated` aux implémentations privées ;
- conserve `finalize` pour `service_role` uniquement.

Après correction, la finalisation et la confirmation du nouveau code passent réellement.

## 4. Recette serveur exécutée avec rollback

Toutes les données ci-dessous étaient synthétiques et chaque scénario a fini par `ROLLBACK`.

| Scénario | Résultat vérifié |
|---|---|
| Session Direction reconnue | `auth.uid()` présent, rôle `direction` |
| Direction 1 crée Parent sans e-mail | `USER_CREATED`, `requires_phone_provisioning=true` |
| Numéro RDC local | normalisé vers `+243...` |
| Même numéro sous une autre écriture | `PHONE_IN_USE` |
| Enseignant sans e-mail | `VALIDATION_ERROR`, `field=email` |
| Direction 2 crée Parent téléphone | accepté |
| Enseignant tente de créer Parent | `FORBIDDEN` |
| Préparation première identité | `PHONE_ACCESS_PREPARED` |
| Double demande immédiate | `TOO_SOON` avec `next_allowed_at` |
| Reset avant liaison Auth | `ACCOUNT_NOT_LINKED` |
| Parent encore sur code temporaire | `TEMPORARY_PASSWORD_MUST_CHANGE` |
| Rôle métier avant changement du code | `current_app_role()` et `current_app_user_id()` retournent `NULL` |
| Lecture des enfants avant changement | 0 ligne visible |
| Code temporaire expiré | `TEMPORARY_PASSWORD_EXPIRED` |
| Confirmation sans vrai changement | `PASSWORD_NOT_CHANGED` |
| Confirmation après changement de hash | `ACCESS_READY` |
| Rôle après confirmation | `parent` restauré |
| Finalisation serveur `reset` | `PHONE_ACCESS_READY`, demande `ready` |
| Synchronisation `users` et `profiles` | téléphone, rôle et état identiques |
| Préinscription téléphone sans e-mail | `PREINSCRIPTION_CREATED` |
| Validation de cette préinscription | `PREINSCRIPTION_VALIDATED` |
| Parent créé par préinscription | `phone_whatsapp`, e-mail nul, provision téléphone requise |
| E-mail technique temporaire | 0 restant |

## 5. Parent avec plusieurs enfants — absence de mélange

Recette RLS exécutée avec un seul compte Parent et cinq enfants synthétiques :

- deux enfants réellement rattachés au Parent ;
- un enfant d'un autre Parent ;
- un enfant dont `access_parent=false` ;
- un enfant archivé.

Résultat en session Parent :

```text
visibles : les 2 enfants rattachés
invisibles : enfant d'un autre Parent, accès bloqué, enfant archivé
```

Quand `must_change_password=true`, même les deux enfants rattachés deviennent invisibles jusqu'au remplacement du code temporaire.

## 6. Matrice des permissions vérifiée

### `anon`

Aucun droit sur :

- `save_school_user_profile` ;
- `save_parent_phone_profile` ;
- `prepare_parent_phone_access` ;
- `finalize_parent_phone_access` ;
- `fail_parent_phone_access_request` ;
- `get_my_access_state` ;
- `confirm_parent_phone_password_change`.

La seule exception publique volontaire reste `submit_preinscription`, car le formulaire du site doit pouvoir déposer une demande.

### `authenticated`

Autorisé :

- `save_school_user_profile` ;
- `save_parent_phone_profile` ;
- `get_my_access_state` ;
- `confirm_parent_phone_password_change`.

Chaque fonction refait ses contrôles de rôle, d'identité, de cible et d'état côté serveur.

Refusé :

- `prepare_parent_phone_access` ;
- `finalize_parent_phone_access` ;
- `fail_parent_phone_access_request`.

### `service_role`

Autorisé pour l'Edge Function :

- préparation ;
- finalisation ;
- marquage d'échec.

La table `private.parent_phone_access_requests` n'est directement lisible ni par `anon`, ni par `authenticated`, ni par `service_role` via le contrat SQL public.

## 7. Nettoyage final vérifié

Après toutes les recettes :

```text
utilisateurs synthétiques       0
élèves synthétiques             0
préinscriptions synthétiques    0
demandes téléphone synthétiques 0
e-mails @phone.invalid          0
compte Direction actif          1
```

Aucun vrai profil Parent n'a été créé avec le numéro privé de Loms.

## 8. Conseillers Supabase

- la FK `parent_phone_access_requests.requested_by` est maintenant couverte par un index ;
- les index du nouveau lot apparaissent encore comme « unused » parce qu'aucune utilisation réelle en production n'a encore eu lieu ; ce n'est pas une erreur ;
- les avertissements `SECURITY DEFINER` sur `get_my_access_state`, `confirm_parent_phone_password_change`, `save_parent_phone_profile` et `submit_preinscription` sont attendus : ces fonctions sont les portes contrôlées du contrat ;
- les implémentations sensibles ont été déplacées dans `private` et leurs droits directs ont été retirés ;
- la protection Supabase contre les mots de passe compromis reste indisponible/désactivée sur la configuration actuelle et n'a pas été modifiée dans ce lot.

## 9. Ce que Claude doit intégrer exactement

### Connexion

Ajouter un choix visible :

```text
Adresse e-mail | Numéro de téléphone
```

Téléphone :

```js
await supabase.auth.signInWithPassword({
  phone: telephoneNormalise,
  password: codeOuMotDePasse
});
```

Après tout succès Auth :

```js
const { data } = await supabase.rpc('get_my_access_state');
```

Ne jamais charger les pages Parent avant `ACCESS_READY`.

### Première connexion

Sur `TEMPORARY_PASSWORD_MUST_CHANGE` :

1. afficher seulement « Créer mon code personnel » ;
2. appeler `auth.updateUser({ password: nouveauMotDePasse })` ;
3. appeler `confirm_parent_phone_password_change()` ;
4. ouvrir l'espace Parent seulement si la RPC rend `ACCESS_READY`.

Sur `PASSWORD_NOT_CHANGED`, refuser l'ancien code temporaire comme nouveau code.

Sur `TEMPORARY_PASSWORD_EXPIRED`, demander à la Direction de générer un nouveau code.

### Création du Parent

Continuer à appeler :

```text
save_school_user_profile(p_user)
```

Quand la réponse contient :

```text
requires_phone_provisioning=true
```

appeler l'Edge Function :

```json
{"app_user_id":"...","action":"provision"}
```

### Réinitialisation et changement de numéro

```json
{"app_user_id":"...","action":"reset"}
```

```json
{"app_user_id":"...","action":"change_phone","phone":"nouveau numéro"}
```

Ne pas appeler `provision` sur un compte déjà lié. Ne pas appeler `reset` sur un compte non lié.

### WhatsApp

Le message doit contenir seulement :

```text
Bonjour, votre accès SchoolSafe est prêt.
Identifiant : +243...
Code temporaire : ...
Expiration : ...
Créez votre code personnel à la première connexion.
Ne transmettez ce code à personne.
```

Interdiction d'ajouter :

- nom d'enfant ;
- classe ;
- notes ;
- dette ou paiement ;
- reçu ;
- donnée médicale ;
- QR ou historique d'entrée/sortie.

### Messages d'erreur à traiter

- `PHONE_IN_USE` : numéro déjà rattaché ;
- `TOO_SOON` : afficher le compte à rebours ;
- `ALREADY_LINKED` : utiliser `reset` ;
- `ACCOUNT_NOT_LINKED` : utiliser `provision` ;
- `TARGET_DISABLED` : compte inactif ;
- `PASSWORD_NOT_CHANGED` : choisir un code différent ;
- `TEMPORARY_PASSWORD_EXPIRED` : nouveau code Direction nécessaire ;
- `ACCOUNT_UPDATED_FINALIZE_FAILED` : ne pas afficher ni envoyer le code reçu, attendre puis recommencer ;
- `AUTH_CREATE_FAILED` / `AUTH_UPDATE_FAILED` : aucun message de réussite.

## 10. Vérifications qui restent obligatoirement côté Claude / tableau de bord

ChatGPT ne peut pas vérifier ces points par le connecteur disponible :

1. état réel de `Authentication → Providers → Phone` dans le tableau de bord Supabase ;
2. appel HTTP complet de `parent-phone-access` avec le JWT d'une vraie session Direction ;
3. connexion réelle `phone + password` dans le navigateur ;
4. ouverture WhatsApp depuis Android ;
5. comportement visuel sur réseau mobile lent et double-clic ;
6. fusion de la PR #46 ;
7. publication GitHub Pages et vérification de l'URL publique.

Aucune invocation réelle de `parent-phone-access` n'apparaît encore dans les journaux Edge. L'Edge Function est compilée et ACTIVE, mais elle doit être appelée par l'interface intégrée avant de déclarer le parcours entièrement opérationnel.

## 11. Ordre de recette Claude avant publication

1. vérifier/activer Provider Phone ;
2. intégrer la PR #46 sans réécrire le backend ;
3. créer un Parent synthétique depuis l'écran Direction ;
4. appeler `provision` ;
5. vérifier que WhatsApp reçoit uniquement le message autorisé ;
6. se connecter avec téléphone + code temporaire ;
7. confirmer qu'aucune donnée enfant n'est visible avant changement ;
8. créer un nouveau code personnel ;
9. confirmer `ACCESS_READY` ;
10. vérifier deux enfants rattachés sans voir ceux des autres familles ;
11. tester expiration, double-clic, doublon, reset et changement de numéro ;
12. exécuter les audits du dépôt ;
13. fusionner ;
14. publier ;
15. vérifier l'application publique sur téléphone.

## 12. Séparation avec les autres lots

- SMTP/Brevo : reste utile pour les comptes e-mail, mais ne bloque plus le parcours Parent téléphone ;
- R2/compression : déjà séparé pour les fichiers lourds, aucun changement dans P0-20 ;
- paie : PR #38 toujours ouverte, ne pas mélanger son intégration avec P0-20 ;
- fusionner la PR n'est pas encore publier : la publication doit être contrôlée séparément.
