# Passation backend SchoolSafe à Claude — 4 août 2026

**Branche backend :** `agent/payment-control-backend-v1`  
**Projet Supabase :** `lcnronymkccgyltttqry`  
**État :** migrations appliquées dans Supabase ; aucune fusion dans `main`, aucune publication.

Ce document répond aux blocages recensés dans `coordination/DEMANDES_A_CHATGPT.md` de la PR Claude nº6.

---

## 1. Décisions définitives à intégrer côté frontend

### Paiements

Les nouveaux encaissements utilisent exclusivement :

- `public.record_payment_transaction(...)` ;
- `public.payment_transactions` ;
- `public.payment_allocations` ;
- `public.reverse_payment_transaction(...)`.

L’ancien booléen `public.payments.paid` reste uniquement un mécanisme de compatibilité pour les anciennes données. Il ne faut pas lui ajouter un nouvel auteur.

Chaque nouvelle transaction contient maintenant :

- `recorded_by` ;
- `recorded_by_name` ;
- `recorded_by_role` ;
- `created_at` ;
- un numéro permanent et séquentiel par année scolaire.

Format du numéro :

```text
REC-2025-2026-000001
```

Une réimpression conserve ce numéro. Une contrepassation ne supprime jamais le reçu.

### Réponse de `record_payment_transaction`

Réponse JSON directe, sans enveloppe `{ok,data}` :

```json
{
  "contract_version": 2,
  "transaction_id": "ptx_...",
  "receipt_no": "REC-2025-2026-000001",
  "student_id": "...",
  "amount": 40,
  "currency": "USD",
  "payment_date": "2026-08-04",
  "school_year": "2025-2026",
  "status": "confirmed",
  "recorded_by": "...",
  "recorded_by_name": "Nom de la caissière",
  "recorded_by_role": "direction3",
  "created_at": "..."
}
```

### Réponse de `reverse_payment_transaction`

Réponse JSON directe :

```json
{
  "contract_version": 2,
  "transaction_id": "ptx_...",
  "student_id": "...",
  "receipt_no": "REC-2025-2026-000001",
  "amount": 40,
  "currency": "USD",
  "status": "reversed",
  "reversed_by": "...",
  "reversed_by_name": "Nom de l’agent",
  "reversed_by_role": "direction3",
  "reversed_at": "...",
  "reason": "Erreur de saisie"
}
```

---

## 2. Scanner — contrat définitif

### Sens de `orient`

`orient` signifie :

- l’accès n’est pas encore validé ;
- `allowed = false` ;
- l’élève doit être orienté vers la Caisse ;
- aucune présence et aucune entrée ne sont enregistrées tant que la situation n’est pas validée.

### Enveloppe de `record_entry_scan`

Réponse JSON directe, jamais `{ok:true,data:{...}}`.

Succès :

```json
{
  "contract_version": 2,
  "recorded": true,
  "allowed": true,
  "access_status": "allowed",
  "status": "ontime",
  "date": "2026-08-04",
  "time": "07:15",
  "attendance_id": "att_..."
}
```

Orientation :

```json
{
  "contract_version": 2,
  "recorded": false,
  "allowed": false,
  "access_status": "orient",
  "reason": "orientation_required",
  "public_reason": "Accès en attente — orienter vers la Caisse"
}
```

Blocage :

```json
{
  "contract_version": 2,
  "recorded": false,
  "allowed": false,
  "access_status": "blocked",
  "reason": "denied"
}
```

Doublon :

```json
{
  "contract_version": 2,
  "recorded": false,
  "allowed": true,
  "reason": "duplicate"
}
```

### Enveloppe de `record_exit_scan`

Réponse JSON directe avec :

- `recorded` ;
- `allowed` ;
- `reason` en cas de refus ;
- `escort_name` en cas de succès.

Codes possibles :

- `unknown_student` ;
- `missing_entry` ;
- `duplicate` ;
- `invalid_escort`.

### Confidentialité scanner

- le Gardien et Direction 1 peuvent recevoir le téléphone du tuteur principal ou de la personne accréditée ;
- Direction 2, la Caisse et les enseignants ne reçoivent plus ces numéros via les RPC scanner ;
- aucun rôle Gardien ne reçoit montant, devise, trimestre ou solde financier ;
- `financial_reason` est réservé à Direction 1 et à la Caisse.

---

## 3. Création de profils et invitations Auth — cause réparée

### Cause principale trouvée

Le déclencheur `private.handle_new_auth_user()` créait une **deuxième ligne** dans `public.users` avec l’identifiant Auth, au lieu de relier l’identité Auth au profil SchoolSafe préparé par Direction 1.

Conséquence :

1. le profil initial restait sans `auth_user_id` ;
2. l’Edge Function vérifiait ce profil initial ;
3. elle renvoyait `LINK_NOT_CONFIRMED` ;
4. le compte semblait créé partiellement, mais le profil restait inutilisable.

Deux autres incompatibilités ont été trouvées :

- les RPC utilisaient des colonnes d’invitation absentes ;
- elles écrivaient dans d’anciens noms de colonnes de `audit_log`.

### Nouveau comportement

Le déclencheur :

- recherche l’invitation active par email ;
- verrouille le profil SchoolSafe ciblé ;
- crée ou met à jour `public.profiles` ;
- écrit `auth_user_id` sur la ligne `public.users` existante ;
- marque l’invitation comme acceptée ;
- ne crée plus de profil SchoolSafe en double.

`prepare_account_invitation` et `cancel_account_invitation` ont été réparées et sont exécutables uniquement avec la clé serveur depuis l’Edge Function. L’acteur transmis doit être Direction 1.

### Ce que Claude doit faire

Après la réussite de `save_school_user_profile`, appeler l’Edge Function :

```text
invite-school-account
```

Corps :

```json
{
  "app_user_id": "identifiant du profil SchoolSafe retourné par save_school_user_profile",
  "email": "adresse@exemple.com",
  "redirect_to": "https://medygoo.github.io/SchoolSafe-/auth.html"
}
```

Ne jamais afficher « compte créé » tant que la réponse ne contient pas :

```json
{
  "ok": true,
  "code": "ACCOUNT_INVITED",
  "app_user_id": "...",
  "auth_user_id": "..."
}
```

---

## 4. Parent — nouveau contrat pédagogique

RPC :

```text
get_parent_pedagogic_context(p_sid)
```

Accès : parent connecté et propriétaire de l’élève uniquement.

Réponse :

- élève minimal ;
- classe ;
- titulaires/enseignants avec nom et rôle, sans téléphone ni email ;
- emploi du temps de la classe ;
- cahier de texte uniquement lorsque le statut est `approved`, `published` ou `validated`.

Structure :

```json
{
  "contract_version": 1,
  "student": {},
  "class": {},
  "teachers": [],
  "timetable": [],
  "cahier_texte": [],
  "generated_at": "..."
}
```

Claude peut donc remplacer les messages provisoires « pas encore accessible » par ce RPC unique.

---

## 5. Site connecté à l’application

### Table publique

```text
public.site_content
```

Une seule ligne :

```text
id = main
```

Champs :

- `school_name`, `school_name_en`, `tagline` ;
- `about_text`, `mission`, `founded_year` ;
- `address`, `city`, `phone`, `whatsapp`, `email` ;
- `programs`, `pillars`, `stats`, `staff` ;
- `gallery`, `hero_photos`, `hero_url`, `logo_url` ;
- `theme`, `primary_color` ;
- `published_at`, `updated_at`.

### Lecture

Le site public peut exécuter :

```http
GET /rest/v1/site_content?id=eq.main&select=*
```

avec la clé publique Supabase. La clé publique peut être présente dans le JavaScript du site : elle n’est pas un secret. Sa sécurité dépend des RLS et des privilèges.

Vérification effectuée : le rôle `anon` peut lire `site_content`, mais ne peut pas lire `public.users`.

### Écriture

RPC :

```text
save_site_content(p_content jsonb)
```

- Direction 1 uniquement ;
- aucune écriture directe accordée à `anon` ou `authenticated` ;
- audit automatique ;
- tableaux JSON validés ;
- couleur validée en `#RRGGBB` ;
- `hero_photos` exige des URL HTTPS.

Les photos ajoutées depuis l’application doivent être téléversées dans R2, puis leurs URL HTTPS enregistrées dans `gallery`, `hero_photos`, `staff.photo_url`, `hero_url` ou `logo_url`.

Claude peut retirer :

- `CENTRAL_URL` ;
- `CENTRAL_KEY` ;
- `SITE_LICENSE_KEY` ;
- `license_key` ;
- `?school=`.

---

## 6. Tests déjà exécutés

### Réussis

1. Numérotation annuelle testée dans une transaction avec rollback :
   - `REC-2025-2026-000001` ;
   - `REC-2025-2026-000002`.
2. Préparation d’une invitation fictive : `INVITATION_PREPARED`.
3. Annulation de la même invitation : `INVITATION_CANCELLED`.
4. Toutes les données fictives de ce test ont été annulées par `ROLLBACK`.
5. Lecture anonyme de `site_content` réussie.
6. Lecture anonyme de `public.users` refusée.
7. Advisors Supabase relancés après les migrations.

### À jouer dans le navigateur avec une vraie session

- invitation complète et réception du courriel ;
- première définition du mot de passe ;
- connexion du nouveau compte ;
- paiement réel de test avec Direction 3 ;
- contrepassation ;
- entrée `allowed`, `orient`, `blocked` ;
- sortie par tuteur principal, personne accréditée et sortie autonome ;
- affichage Parent du nouveau RPC ;
- publication du site depuis Direction 1.

---

## 7. Migrations Supabase appliquées dans ce lot

```text
20260804090600 harden_payment_authorship_receipts
20260804090649 upgrade_payment_rpc_contract_v2
20260804090716 expose_payment_authors_in_fee_summary
20260804091101 enforce_scanner_orientation_contract_v2
20260804091117 limit_scanner_contact_directory
20260804091206 upgrade_scanner_recording_rpc_contract_v2
20260804091650 repair_account_invitation_linkage_contract
20260804091731 repair_account_invitation_prepare_cancel_rpcs
20260804091901 align_account_invitation_audit_log
2026080409.... add_parent_pedagogic_context_rpc
2026080409.... add_secure_public_site_content
2026080409.... optimize_profile_rls_and_payment_indexes
```

Les versions exactes des trois dernières doivent être récupérées dans l’historique Supabase au moment de la synchronisation des fichiers SQL.

---

## 8. Restant côté ChatGPT

- déposer tous les SQL exacts de ce lot dans `supabase/migrations/` ;
- supprimer les Edge Functions de diagnostic désactivées ;
- compléter les tests authentifiés multi-rôles ;
- activer la protection contre les mots de passe compromis dans la configuration Auth ;
- finaliser la livraison publique R2 des images du site ;
- refaire les advisors après les tests de volume.

## 9. Restant côté Claude

- rebaser sur le dernier `main` avant intégration ;
- appeler les contrats ci-dessus sans recalcul local ;
- raccorder l’Edge Function d’invitation ;
- raccorder le nouveau RPC Parent ;
- raccorder `site_content` et `save_site_content` ;
- traiter `orient` comme `allowed=false` ;
- retirer les sources Parent incompatibles avec RLS ;
- ajouter les audits au workflow de publication ;
- exécuter la recette navigateur et mobile avant fusion.
