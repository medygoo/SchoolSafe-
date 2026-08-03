# SchoolSafe — registre vérifié des RPC et Edge Functions

**Source de vérité :** Supabase `lcnronymkccgyltttqry` — état contrôlé le 3 août 2026 après la migration `20260803200317_fix_school_user_profile_auth_permission`.

Format : **nom · rôles · paramètres · succès · erreurs/remarques**. Le frontend ne déduit aucun champ absent.

## 1. Identité de session

| Nom | Usage | Réponse | Remarques |
|---|---|---|---|
| `private.current_app_user_id()` | interne | `users.id` actif lié à `auth.uid()` | `NULL` si aucune ligne active reliée. |
| `private.current_app_role()` | interne | rôle actif normalisé | `direction_pedagogique → direction2`, `caisse → direction3`; `NULL` si aucune liaison active. |
| `private.can_scan()` | interne scanner | booléen | vrai pour `direction`, `direction2`, `direction3`, `enseignant`, `gardien`. |

Valeurs canoniques pour les nouveaux comptes :

```text
direction · direction2 · direction3 · enseignant · gardien · parent
```

Alias normalisés par `save_school_user_profile` :

```text
direction_pedagogique → direction2
caisse                 → direction3
enseignant_maternelle  → enseignant
disabled                → inactive
```

Statuts persistés : `active`, `inactive`, `suspended`.

## 2. Création et modification des profils

### `save_student_profile(p_student jsonb)`

- **Rôles :** `direction`, `direction2`.
- **Création obligatoire :** `id`, `name`, `cid`.
- **Optionnels :** `mat`, `pid`, `dob`, `photo`, `adresse`, `nom_papa`, `nom_maman`, `lieu_naissance`, `num_inscription`, `access_parent`, `may_leave_alone`, `leave_alone_until`.
- Une clé absente conserve la valeur existante lors d'une modification.
- **Succès :** `{ok:true, code:"STUDENT_CREATED|STUDENT_UPDATED", student:{...}}`.
- **Erreurs :** `INVALID_PAYLOAD`, `FORBIDDEN`, `ACTOR_NOT_FOUND`, `VALIDATION_ERROR` + `field`, `CLASS_NOT_FOUND`, `MATRICULE_IN_USE`, `PARENT_NOT_FOUND`, `PHOTO_MUST_BE_FILE_REFERENCE`, `LEAVE_AUTHORIZATION_DATE_REQUIRED`, `REFERENCE_NOT_FOUND`, `DUPLICATE_STUDENT`.

### `save_school_user_profile(p_user jsonb)`

- **Rôle :** `direction` uniquement.
- **Obligatoires :** `id`, `name`, `role`.
- **Optionnels :** `initials`, `phone`, `photo_url`, `email`, `status`.
- **Succès :** `{ok:true, code:"USER_CREATED|USER_UPDATED", requires_invitation:boolean, user:{...}}`.
- **Erreurs :** `INVALID_PAYLOAD`, `FORBIDDEN`, `VALIDATION_ERROR` + `field`, `PHOTO_MUST_BE_FILE_REFERENCE`, `EMAIL_IN_USE`, `AUTH_EMAIL_CHANGE_REQUIRED`, `AUTH_ROLE_CHANGE_REQUIRED`, `CANNOT_DISABLE_CURRENT_DIRECTION`, `DUPLICATE_USER`, `REFERENCE_NOT_FOUND`.
- La fonction reste `SECURITY INVOKER` et ne lit plus directement `auth.users`.
- L'unicité Auth de l'e-mail est vérifiée dans le parcours serveur d'invitation.

**Preuve transactionnelle après correction :**

```text
Parent actif avec e-mail                    → USER_CREATED, invitation requise
enseignant_maternelle + disabled            → enseignant + inactive, USER_CREATED
Parent + classe + élève lié                 → STUDENT_CREATED
Données de diagnostic restantes             → 0 utilisateur, 0 élève, 0 classe, 0 profil
```

### Edge `invite-school-account` v1

- JWT obligatoire ; appel par Direction 1, contrôle répété côté serveur.
- `POST {app_user_id,email,redirect_to?}`.
- Origines : GitHub Pages, `https://cslesage.com`, `https://www.cslesage.com`, localhost autorisé.
- **Succès HTTP 201 :** `{ok:true,code:"ACCOUNT_INVITED",app_user_id,auth_user_id,email,role,status,request_id}`.
- **Erreurs :** `AUTH_REQUIRED`, `AUTH_INVALID`, `ORIGIN_FORBIDDEN`, `VALIDATION_ERROR`, `ACTOR_NOT_FOUND`, `FORBIDDEN`, `TARGET_NOT_FOUND`, `ALREADY_LINKED`, `EMAIL_IN_USE`, `TARGET_DISABLED`, `UNSUPPORTED_ROLE`, `DB_PREPARE_FAILED`, `INVITE_FAILED`, `LINK_NOT_CONFIRMED`, `SERVER_CONFIGURATION_ERROR`.

### PIN

Le parcours actif est **e-mail + mot de passe Supabase Auth** : ne plus créer, réinitialiser ni utiliser de PIN pour la connexion.

## 3. Configuration sûre

### `get_safe_settings()`

- Tout compte applicatif actif.
- Retourne : `id`, `year`, `school`, `toggles`, `horaires`, `lockdown`, `retention`, `trimlocks`, `currenttrimestre`, `school_type`, `session_timeout_min`, `rattrapage_rate`, `rattrapage_threshold`.
- `fees` et `feescontrol` seulement pour `direction`, `direction3`, `parent`.
- Erreur `Session inactive` si aucune liaison active.
- Les rôles autres que Direction 1 ne chargent jamais directement la table `settings`.

## 4. Frais et paiements

| Nom | Rôles | Paramètres | Succès / remarques |
|---|---|---|---|
| `get_parent_fee_summary(p_sid)` | parent propriétaire | `p_sid` | état, accès, totaux par devise, obligations, reçus. Aucun calcul navigateur. |
| `get_cashier_student_fee_detail(p_sid)` | direction, direction3 | `p_sid` | même forme détaillée. |
| `record_payment_transaction(...)` | direction, direction3 | `p_sid`, `p_amount`, puis devise/méthode/référence/note/date/allocations optionnelles | `{transaction_id,receipt_no,student_id,amount,currency,payment_date,status}`. |
| `grant_payment_access_exception(...)` | direction | élève, dates, motif | `{exception_id,student_id,starts_at,ends_at}`. |
| `revoke_payment_access_exception(...)` | direction | exception, motif | `{exception_id,status:"revoked"}`. |

Le numéro actuel est serveur : `SS-YYYYMMDD-XXXXXXXX`. Il n'est pas encore séquentiel par année scolaire.

`reverse_payment_transaction` **n'existe pas** : ne pas l'appeler.

## 5. Scanner et portail

| Nom | Rôles | Paramètres | Réponse / raisons |
|---|---|---|---|
| `get_scanner_students()` | direction, direction2, direction3, enseignant, gardien | aucun | `id,mat,name,photo,cid,blocked,access_blocked,may_leave_alone,leave_alone_until,pid,primary_guardian_name,primary_guardian_phone`. |
| `get_scanner_aps()` | mêmes rôles | aucun | personnes approuvées, actives et valides. |
| `verify_student_qr(p_mat,p_date,p_signature)` | mêmes rôles | matricule/date/signature | `{valid:true,sid,mat,date}` ou raisons `unknown_student|expired|invalid_signature`. |
| `issue_student_qr(p_sid)` | rôles scanner ou parent propriétaire | élève | `{sid,mat,date,signature,payload,expires_at}`. |
| `get_gate_access_status(p_sid)` | rôles scanner | élève | identité minimale, `access_status`, `allowed`, `instruction`, `checked_at`; aucun détail financier. |
| `check_gate_access_status(p_sid,p_source='qr')` | rôles scanner | élève/source | même réponse + journalisation si l'élève existe. Porte à utiliser au portail. |
| `record_entry_scan(p_sid,p_status,p_arr_time,p_manual)` | rôles scanner | entrée | `{recorded:true,allowed:true,status,date,time}` ou `unknown_student|denied|duplicate`. |
| `record_exit_scan(p_sid,p_escort_kind,p_escort_id,p_escort_name,p_manual)` | rôles scanner | sortie | `{recorded:true,status:"authorized",time,escort_name}` ou `unknown_student|missing_entry|duplicate|invalid_escort`. |
| `record_scan_incident(...)` | rôles scanner | élève/type/code/note/manuel | `{recorded:true}` ou `unknown_student`; note libre réservée à direction/direction3. |

Cache de décision portail : **5 minutes maximum** ; après expiration : `Contrôle manuel requis`.

## 6. Palmarès

### `get_my_palmares_publications()`

Retour : `id,cid,year,trimestre,status,formula_version,snapshot,version,published_at`, filtré par le contrat serveur. Ne jamais télécharger les publications d'autres profils puis les masquer.

## 7. R2

| Endpoint | Version | Usage |
|---|---:|---|
| `r2-upload` | 4 | endpoint obligatoire pour tout nouvel upload d'image ; validation, compression, JWT, limites 8 Mo source / 5 Mo final. |
| `r2-files` | 5 | liste, lecture, suppression et usages non-image autorisés. |
| `r2-archives` | 1 | archives, Direction 1 uniquement. |

## 8. Sémantique frontend

```text
{ok:true,  data, code}
{ok:false, data:null, code, error, http_status}
```

- confirmation seulement après `ok:true` ;
- hors ligne = `queued`, jamais `saved` ;
- 401 = session ; 403 = rôle ; 409 = conflit ; 422 = validation ; réseau/5xx = indisponible ;
- un code inconnu s'affiche tel quel ;
- formulaire conservé ouvert en cas d'échec.

## 9. Avertissements de sécurité restants

Le conseiller Supabase ne signale aucun nouvel avertissement pour `save_school_user_profile`. Il signale encore les anciennes RPC publiques `SECURITY DEFINER` du scanner/palmarès/configuration et la protection contre les mots de passe compromis désactivée. Elles restent dans le lot sécurité prévu ; ne pas les contourner côté frontend.
