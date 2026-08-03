# SchoolSafe — registre vérifié des RPC et Edge Functions

**Source de vérité :** projet Supabase `lcnronymkccgyltttqry`, contrôlé le 3 août 2026.

Format : **nom · rôles autorisés · paramètres · réponse succès · erreurs / remarques**.

> Ce registre décrit ce qui est réellement déployé. Le frontend ne doit jamais inventer un champ absent. Les fonctions privées sont documentées pour comprendre la sécurité ; elles ne sont pas appelées directement par le navigateur.

## 1. Identité de session

| Nom | Rôles / appel | Paramètres | Réponse | Erreurs / remarques |
|---|---|---|---|---|
| `private.current_app_user_id()` | interne aux RLS/RPC | aucun | `text` : `users.id` du compte actif lié à `auth.uid()` | Retourne `NULL` si la session Auth n'est reliée à aucune ligne active de `public.users` ou si le compte applicatif est inactif. |
| `private.current_app_role()` | interne aux RLS/RPC | aucun | `text` normalisé | Cherche une ligne active de `users` liée à `auth.uid()`. Retourne `NULL` si aucune liaison active. Normalise `direction_pedagogique → direction2` et `caisse → direction3`. |
| `private.can_scan()` | interne aux RPC scanner | aucun | `boolean` | Vrai pour `direction`, `direction2`, `direction3`, `enseignant`, `gardien`; faux/NULL sinon. |

### Valeurs de rôle autorisées par les contraintes actuelles

Stockage accepté dans `users.role` et `profiles.role` :

```text
direction
direction_pedagogique
caisse
enseignant
gardien
parent
direction2
direction3
```

Valeurs canoniques à envoyer pour les nouveaux comptes :

```text
direction
direction2
direction3
enseignant
gardien
parent
```

Les valeurs `direction_pedagogique` et `caisse` sont des alias historiques tolérés en base et normalisés à la lecture. `enseignant_maternelle` n'est pas accepté par les contraintes actuelles : le frontend doit l'envoyer comme `enseignant` et conserver la distinction maternelle dans les affectations/classes, pas dans le rôle d'autorisation.

### Incompatibilité backend actuellement connue

`save_school_user_profile` accepte aujourd'hui :

```text
roles  : direction, direction2, direction3, enseignant, enseignant_maternelle, parent, gardien
status : active, disabled
```

Mais les contraintes des tables acceptent :

```text
roles  : direction, direction_pedagogique, caisse, enseignant, gardien, parent, direction2, direction3
status : active, inactive, suspended
```

Conséquences :

- ne pas envoyer `enseignant_maternelle` ; envoyer `enseignant` ;
- ne pas envoyer `disabled` tant que le contrat backend n'est pas aligné ;
- pour le raccordement immédiat, les créations utilisent `status: "active"` ;
- l'écran de désactivation reste bloqué jusqu'à correction coordonnée du contrat.

## 2. Création et modification des profils

| Nom | Rôles autorisés | Paramètres | Réponse succès | Erreurs / remarques |
|---|---|---|---|---|
| `save_student_profile(p_student jsonb)` | `direction`, `direction2` | Objet. Obligatoires en création : `id`, `name`, `cid`. Optionnels : `mat`, `pid`, `dob`, `photo`, `adresse`, `nom_papa`, `nom_maman`, `lieu_naissance`, `num_inscription`, `access_parent`, `may_leave_alone`, `leave_alone_until`. Une clé absente conserve la valeur existante en modification. | `{ok:true, code:"STUDENT_CREATED|STUDENT_UPDATED", student:{...ligne students}}` | `INVALID_PAYLOAD`, `FORBIDDEN`, `ACTOR_NOT_FOUND`, `VALIDATION_ERROR` + `field`, `CLASS_NOT_FOUND`, `MATRICULE_IN_USE`, `PARENT_NOT_FOUND`, `PHOTO_MUST_BE_FILE_REFERENCE`, `LEAVE_AUTHORIZATION_DATE_REQUIRED`, `REFERENCE_NOT_FOUND`, `DUPLICATE_STUDENT`. Le navigateur doit fournir l'`id` avant l'appel. |
| `save_school_user_profile(p_user jsonb)` | `direction` uniquement | Objet. Obligatoires : `id`, `name`, `role`. Optionnels : `initials`, `phone`, `photo_url`, `email`, `status`. | `{ok:true, code:"USER_CREATED|USER_UPDATED", requires_invitation:boolean, user:{...ligne users}}` | `INVALID_PAYLOAD`, `FORBIDDEN`, `VALIDATION_ERROR` + `field`, `PHOTO_MUST_BE_FILE_REFERENCE`, `EMAIL_IN_USE`, `AUTH_EMAIL_CHANGE_REQUIRED`, `AUTH_ROLE_CHANGE_REQUIRED`, `CANNOT_DISABLE_CURRENT_DIRECTION`, `DUPLICATE_USER`, `REFERENCE_NOT_FOUND`. Appliquer les valeurs canoniques indiquées plus haut. |
| Edge `invite-school-account` v1 | appel par Direction 1 authentifiée ; contrôle réel fait côté serveur | `POST` JSON `{app_user_id, email, redirect_to?}` avec JWT. Redirections autorisées : GitHub Pages et `cslesage.com`/`www.cslesage.com`. | HTTP `201`, `{ok:true, code:"ACCOUNT_INVITED", app_user_id, auth_user_id, email, role, status, request_id}` | `AUTH_REQUIRED`, `AUTH_INVALID`, `ORIGIN_FORBIDDEN`, `METHOD_NOT_ALLOWED`, `INVALID_JSON`, `VALIDATION_ERROR`, `ACTOR_NOT_FOUND`, `FORBIDDEN`, `TARGET_NOT_FOUND`, `ALREADY_LINKED`, `EMAIL_IN_USE`, `TARGET_DISABLED`, `UNSUPPORTED_ROLE`, `DB_PREPARE_FAILED`, `INVITE_FAILED`, `LINK_NOT_CONFIRMED`, `SERVER_CONFIGURATION_ERROR`. |

### Décision sur le PIN

Le PIN n'appartient ni à `save_school_user_profile` ni au parcours Supabase Auth actif. Les comptes utilisent **e-mail + mot de passe**. Pour cette installation dont les données sont encore de test :

- ne plus créer ni modifier de PIN dans le parcours actif ;
- ne pas appeler `resetUserPin` ;
- ne pas faire dépendre la connexion d'un PIN local ;
- conserver uniquement le parcours d'invitation puis création de mot de passe Supabase Auth.

## 3. Configuration sûre

| Nom | Rôles autorisés | Paramètres | Réponse succès | Erreurs / remarques |
|---|---|---|---|---|
| `get_safe_settings()` | tout compte applicatif actif | aucun | JSON avec `id`, `year`, `school`, `toggles`, `horaires`, `lockdown`, `retention`, `trimlocks`, `currenttrimestre`, `school_type`, `session_timeout_min`, `rattrapage_rate`, `rattrapage_threshold`; ajoute `fees` et `feescontrol` seulement pour `direction`, `direction3`, `parent`. | Exception `Session inactive` si aucune liaison active. Ne jamais charger directement la table `settings` pour les rôles non-Direction 1 : elle contient notamment des secrets/configurations internes. |

## 4. Frais et paiements

| Nom | Rôles autorisés | Paramètres | Réponse succès | Erreurs / remarques |
|---|---|---|---|---|
| `get_parent_fee_summary(p_sid text)` | `parent` propriétaire de l'élève | `p_sid` | Résumé serveur : état, accès, totaux par devise, obligations et reçus | Exception `Accès refusé` si mauvais rôle ou enfant non lié. Aucun recalcul navigateur. |
| `get_cashier_student_fee_detail(p_sid text)` | `direction`, `direction3` | `p_sid` | Même forme détaillée que le résumé parent | Exception `Accès refusé`. |
| `record_payment_transaction(...)` | `direction`, `direction3` | `p_sid`, `p_amount`; options `p_currency='USD'`, `p_payment_method='cash'`, `p_external_reference`, `p_note`, `p_payment_date`, `p_allocations` | `{transaction_id, receipt_no, student_id, amount, currency, payment_date, status:"confirmed"}` | Exceptions : accès refusé, montant invalide, paramètres invalides, élève introuvable, allocation invalide/incompatible, somme incorrecte, montant supérieur au solde ou aucune obligation. Le reçu est actuellement généré par le serveur sous forme `SS-YYYYMMDD-XXXXXXXX`; il n'est pas encore séquentiel par année scolaire. |
| `grant_payment_access_exception(p_sid,p_ends_at,p_reason,p_starts_at?)` | `direction` | dates + motif ≥ 3 caractères | `{exception_id, student_id, starts_at, ends_at}` | `Accès refusé`, `Dérogation invalide`. |
| `revoke_payment_access_exception(p_exception_id,p_reason)` | `direction` | identifiant + motif ≥ 3 caractères | `{exception_id,status:"revoked"}` | `Accès refusé`, `Motif obligatoire`, `Dérogation introuvable ou déjà révoquée`. |

`reverse_payment_transaction` n'existe pas dans la base à cette date. Le frontend ne doit pas l'appeler. Toute annulation reste bloquée jusqu'à ajout d'un contrat serveur explicite.

## 5. Scanner et contrôle du portail

| Nom | Rôles autorisés | Paramètres | Réponse succès | Erreurs / remarques |
|---|---|---|---|---|
| `get_scanner_students()` | `direction`, `direction2`, `direction3`, `enseignant`, `gardien` | aucun | Lignes : `id, mat, name, photo, cid, blocked, access_blocked, may_leave_alone, leave_alone_until, pid, primary_guardian_name, primary_guardian_phone` | Exception `Accès refusé`. **Le matricule est bien fourni** pour résoudre le QR vers `sid`. |
| `get_scanner_aps()` | mêmes rôles scanner | aucun | Personnes approuvées et actives : `id, sid, name, relation, photo, phone, valid_until, approval_status, active` | Exception `Accès refusé`. Les propositions non approuvées ne sont pas retournées. |
| `verify_student_qr(p_mat,p_date,p_signature)` | mêmes rôles scanner | matricule, date `YYYYMMDD`, signature | `{valid:true,sid,mat,date}` | `{valid:false,reason:"unknown_student|expired|invalid_signature"}` ou exception `Accès refusé`. |
| `issue_student_qr(p_sid)` | rôles scanner ou parent propriétaire de l'enfant | `p_sid` | `{sid,mat,date,signature,payload,expires_at}` | Exceptions `Accès refusé`, `Élève introuvable`. Pour l'émission administrative, utiliser Direction 1/2 ; parent : affichage du QR de son propre enfant. |
| `get_gate_access_status(p_sid)` | mêmes rôles scanner | `p_sid` | `{student_id,student_name,matricule,class_id,class_name,photo_url,access_status,allowed,instruction,checked_at}` | Exception `Accès refusé`; élève inconnu → `access_status:"unavailable"`, `allowed:false`, instruction de contrôle manuel. Aucun montant/devise/trimestre. |
| `check_gate_access_status(p_sid,p_source='qr')` | mêmes rôles scanner | `p_sid`, source `qr|manual` | Même réponse que `get_gate_access_status`, avec journalisation dans `payment_scan_log` si l'élève existe | Exception `Accès refusé`. Utiliser cette porte pour le contrôle réel au portail. |
| `record_entry_scan(p_sid,p_status,p_arr_time,p_manual)` | mêmes rôles scanner | statut `late` ou autre→`ontime`; heure optionnelle; manuel booléen | `{recorded:true,allowed:true,status,date,time}` | `{recorded:false,reason:"unknown_student|denied|duplicate",...}`. Un refus n'est pas enregistré comme passage autorisé. |
| `record_exit_scan(p_sid,p_escort_kind,p_escort_id,p_escort_name,p_manual)` | mêmes rôles scanner | `escort_kind: self|primary|accredited` | `{recorded:true,status:"authorized",time,escort_name}` | `{recorded:false,reason:"unknown_student|missing_entry|duplicate|invalid_escort"}`. |
| `record_scan_incident(p_sid,p_type,p_code,p_note,p_manual)` | mêmes rôles scanner | type `entry|exit`, code, note, manuel | `{recorded:true}` | `{recorded:false,reason:"unknown_student"}`; note libre conservée seulement pour `direction`/`direction3`, autres rôles limités à un message administratif générique. |

Cache du statut portail : **5 minutes maximum** à partir de `checked_at`; après expiration afficher `Contrôle manuel requis`.

## 6. Palmarès

| Nom | Rôles autorisés | Paramètres | Réponse succès | Erreurs / remarques |
|---|---|---|---|---|
| `get_my_palmares_publications()` | comptes authentifiés autorisés par la fonction/RLS | aucun | table `id,cid,year,trimestre,status,formula_version,snapshot,version,published_at` filtrée pour l'utilisateur | Ne pas charger les publications d'autres classes/enfants puis masquer côté écran. |

## 7. Stockage R2

| Nom | Rôles autorisés | Paramètres | Réponse succès | Erreurs / remarques |
|---|---|---|---|---|
| Edge `r2-upload` v4 | selon propriétaire/catégorie et matrice serveur | multipart avec JWT ; profils photo/identité/carte/document | fichier validé, éventuellement compressé, puis ligne `school_files` | **Endpoint obligatoire pour les nouveaux uploads d'images.** JPEG/PNG/WebP/PDF source ≤ 8 Mo, final ≤ 5 Mo, images invalides → HTTP 415. |
| Edge `r2-files` v5 | selon rôle/propriété | opérations liste/lecture/suppression et fichiers non-image autorisés | réponse selon action | Ne plus utiliser son ancien upload direct pour les images après intégration de `r2-upload`. |
| Edge `r2-archives` v1 | `direction` uniquement | actions archive/liste/restauration/téléchargement | réponse selon action | JWT obligatoire. |

## 8. Sémantique frontend obligatoire

Tous les appels RPC utilisent une enveloppe frontend unique :

```text
{ ok: true,  data, code }
{ ok: false, data: null, code, error, http_status }
```

- aucune confirmation avant `ok:true` ;
- une opération hors ligne est `queued`, jamais `saved` ;
- une erreur inconnue affiche son `code` réel ;
- HTTP 401 → session expirée/invalide ;
- HTTP 403 → rôle interdit ;
- HTTP 409 → conflit/doublon ;
- HTTP 422 → validation ;
- réseau/5xx → indisponible, formulaire conservé ouvert.
