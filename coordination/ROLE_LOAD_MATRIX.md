# SchoolSafe — matrice de chargement des données par rôle

**Décision technique pour le raccordement frontend — 3 août 2026**

Objectif : remplacer le `Promise.all` commun de 47 tables. Le navigateur ne demande que les données utiles au rôle et le serveur/RLS filtre les lignes avant leur arrivée sur l'appareil.

## 1. Règles communes du chargeur

1. Au démarrage, appeler `get_safe_settings()`.
2. Charger ensuite uniquement les entrées déclarées dans la présente matrice.
3. Ne jamais appeler une table non déclarée pour le rôle.
4. Utiliser des colonnes explicites pour les rôles non-Direction 1.
5. Appliquer les filtres indiqués en plus des politiques RLS.
6. Les modules non ouverts sont chargés à la demande, pas au démarrage.
7. Une ligne RLS invisible ne doit jamais être contournée par une clé serveur dans le navigateur.

### États de réponse à distinguer

```text
200 + lignes       → loaded
200 + []           → empty (requête autorisée, aucune ligne visible)
401                → session_expired
403                → forbidden
404 / PGRST        → contract_missing
réseau / timeout   → unavailable
5xx                → server_error
rôle non concerné  → not_applicable (aucune requête envoyée)
```

La différence entre « vide » et « refusé » ne se déduit pas du contenu. Elle vient du statut HTTP et de la liste blanche du rôle. Une table absente de la matrice n'est pas interrogée et reçoit l'état `not_applicable`, jamais un faux tableau vide.

## 2. Données communes à tout compte actif

| Source | Colonnes / réponse | Filtre | Moment |
|---|---|---|---|
| RPC `get_safe_settings()` | réponse du registre RPC | aucun | démarrage, obligatoire |
| `school_profile` | `id,legal_name,display_name,slogan,locale,timezone,updated_at` | `id=eq.1` | démarrage |
| `users` | `id,name,role,initials,phone,photo_url,status` | RLS limite au compte courant, sauf directions | démarrage ; pour les directions, appliquer en plus le besoin de l'écran |
| `notifs` | `id,uid,from,msg,type,date,time,read,devoir_id,status,to_role,by,wa_links,receipt` | `uid=eq.<app_user_id>`; ordre date/heure desc; pagination | démarrage léger puis arrière-plan |

Ne jamais charger directement `settings` pour Direction 2, Caisse, Enseignant, Parent ou Gardien. Cette table contient des champs internes (`qr_secret`, `msg_enc_key`, clés/configurations). Utiliser `get_safe_settings()`.

## 3. Direction 1 — `direction`

Direction 1 peut accéder à l'ensemble autorisé, mais le chargement reste modulaire.

### Démarrage

| Source | Colonnes | Filtre |
|---|---|---|
| `classes` | `*` | aucune |
| `students` | `id,name,mat,cid,pid,photo,access_blocked,blocked,access_parent,archived,may_leave_alone,leave_alone_until` | `archived=eq.false` pour le tableau actif |
| `users` | `id,name,role,initials,phone,photo_url,email,status,created_at` | aucune; ne pas charger `auth_user_id` sauf écran comptes |
| `notifs` | colonnes communes | pagination |

### Modules à charger à l'ouverture de l'écran

| Module | Tables / RPC |
|---|---|
| Pédagogie | `matieres`, `attendance`, `devoirs`, `grades`, `appreciations`, `conduct`, `cahier_prep`, `cahier_texte`, `evaluations`, `prevision_matiere`, `timetables`, `rattrapages`, `palmares_publications`, `palmares_publication_history`, `tenafep`, `exetat` |
| Élèves / sécurité | `students`, `aps`, `scan_log`, RPC scanner, `approbations`, `medical`, `medical_visits`, `sanctions`, `convocations`, `absences` |
| Activités / cantine | `activites`, `activites_inscriptions`, `cantine`, `cantine_menus`, `cantine_presence` |
| Communication | `messages`, `notifs`, `events`, `push_subscriptions` |
| Personnel | `teacher_absences`, `teacher_notes`, `salaries`, `advances`, `direct_primes` |
| Finance | `fee_types`, `student_fee_obligations`, `payment_transactions`, `payment_allocations`, `payment_access_exceptions`, `payment_scan_log`, `payments` (héritage), `versements`, `journal_entries`, `daily_expenses`, `daily_records`, `daily_reports`, `inscriptions` |
| Administration | `administrative_document_types`, `administrative_documents`, Edge R2 autorisées, `audit_log` |

Même pour Direction 1, ne pas tirer toutes ces tables au démarrage. Chaque groupe est chargé quand son module devient actif.

## 4. Direction 2 — `direction2`

Règle Loms : tout ce qui est pédagogique et administratif non financier, aucune donnée monétaire.

### Démarrage

| Source | Colonnes | Filtre |
|---|---|---|
| `classes` | `id,name,cycle,teacher_id,teacher_id_en,titulaire_id,option,card_color,card_color_soft,card_color_dark` | aucune |
| `students` | `id,name,mat,cid,pid,dob,photo,adresse,nom_papa,nom_maman,access_blocked,blocked,access_parent,archived,created_at,lieu_naissance,num_inscription,may_leave_alone,leave_alone_until` | `archived=eq.false` par défaut |
| `users` | `id,name,role,initials,phone,photo_url,status` | aucune; exclure `email`, `auth_user_id` |
| `matieres` | `id,cid,name,lang,active` | aucune |
| `notifs` | colonnes communes | `uid=eq.<app_user_id>` uniquement |

### Modules autorisés

```text
attendance
devoirs
grades
appreciations
conduct
cahier_prep
approbations
aps
scan_log
palmares_publications
palmares_publication_history
administrative_document_types
administrative_documents (RLS : uniquement non financiers + confidentialité administrative)
```

Pour `administrative_documents`, sélectionner :

```text
id,document_type_id,title,document_number,document_date,period_start,period_end,
provider,notes,school_year,confidentiality,is_financial,status,created_by,
created_at,updated_at,archived_at
```

Ne pas sélectionner `amount` ni `currency` pour Direction 2, même si une ancienne ligne mal classée passait la RLS.

### Sources interdites

```text
fee_types
student_fee_obligations
payment_transactions
payment_allocations
payment_access_exceptions
payment_scan_log
payments
versements
journal_entries
daily_expenses
salaries
advances
direct_primes
audit_log financier
```

Direction 2 ne reçoit aucune notification financière. Le scanner financier est masqué ; dans un autre contexte de scan, seule une instruction administrative générique peut être affichée.

## 5. Caisse / Direction 3 — `direction3`

### Démarrage

| Source | Colonnes | Filtre |
|---|---|---|
| `classes` | `id,name,cycle` | aucune |
| `students` | `id,name,mat,cid,photo,access_blocked,blocked,archived` | `archived=eq.false` |
| `notifs` | colonnes communes | `uid=eq.<app_user_id>` |

### Chargement financier à la demande

| Source | Colonnes / usage | Filtre |
|---|---|---|
| RPC `get_cashier_student_fee_detail(p_sid)` | détail d'un élève | après sélection/scan |
| RPC `record_payment_transaction(...)` | écriture paiement | jamais d'insert direct depuis l'écran |
| `payment_transactions` | `id,sid,school_year,amount,currency,payment_date,payment_method,external_reference,receipt_no,status,recorded_by,note,created_at,reversed_at,reversal_reason` | année courante; pagination |
| `payment_allocations` | `id,transaction_id,obligation_id,amount,created_at` | seulement transactions affichées |
| `student_fee_obligations` | `id,sid,fee_type_id,school_year,label,installment_no,amount_due,currency,due_date,active,updated_at` | élève ou classe/année sélectionnée |
| `payment_access_exceptions` | `id,sid,starts_at,ends_at,reason,granted_by,revoked_at,revoke_reason,created_at` | élève sélectionné |
| `payment_scan_log` | `id,sid,checked_by,checked_role,source,result_code,details,created_at` | écran de contrôle; pagination |
| `administrative_document_types` | colonnes complètes | `is_financial=eq.true` |
| `administrative_documents` | colonnes complètes | RLS limite aux documents financiers |

Ne pas charger les salaires, le journal comptable général ou les données pédagogiques complètes au démarrage. Les anciens `payments` booléens sont maintenus seulement pour compatibilité temporaire ; ils ne définissent plus le solde affiché.

## 6. Enseignant — `enseignant`

### Démarrage

| Source | Colonnes | Filtre |
|---|---|---|
| `classes` | `id,name,cycle,teacher_id,teacher_id_en,titulaire_id,option,card_color,card_color_soft,card_color_dark` | RLS : uniquement classes autorisées |
| `students` | `id,name,mat,cid,photo,dob,access_blocked,blocked,archived` | RLS : élèves de ses classes; `archived=eq.false` |
| `matieres` | `id,cid,name,lang,active` | classes visibles |
| `notifs` | colonnes communes | `uid=eq.<app_user_id>` |

### Modules à la demande

| Table | Colonnes | Filtre |
|---|---|---|
| `attendance` | `id,sid,cid,date,status,arr_time,manual,marked_by,note,excused,teacher_validated,by,year,trimestre,created_at` | `cid` dans ses classes; période affichée |
| `devoirs` | `id,cid,title,type,content,lang,matiere,description,chapters,duration,category,date,deadline,teacher_id,status,expires_at,sigs` | RLS classe/enseignant |
| `grades` | colonnes complètes | `cid` dans ses classes; trimestre/année |
| `appreciations` | `id,sid,cid,trim,text,by,date,updated` | classes autorisées |
| `conduct` | `id,sid,score,remark,date,by,year,trimestre,created_at` | élèves de ses classes |
| `cahier_prep` | colonnes complètes | `teacher_id=eq.<app_user_id>` |
| `scan_log` | `id,sid,type,status,date,time,name,label,by_uid,by_name,description,note,by_role,manual,escort_kind,escort_id,escort_name,created_at` | date du jour + élèves de ses classes, conformément RLS |
| `aps` | `id,sid,name,relation,photo,active,phone,approval_status,valid_until` | seulement approuvées, actives et valides |

L'Enseignant ne charge aucune table financière et n'appelle pas les résumés de frais.

## 7. Parent — `parent`

### Démarrage prioritaire

| Source | Colonnes | Filtre |
|---|---|---|
| `students` | `id,name,mat,cid,dob,photo,access_parent,archived,lieu_naissance,num_inscription,may_leave_alone,leave_alone_until` | RLS : ses enfants; `archived=eq.false`; `access_parent=neq.false` |
| `classes` | `id,name,cycle,option,card_color,card_color_soft,card_color_dark` | classes de ses enfants via RLS |
| `notifs` | colonnes communes | `uid=eq.<app_user_id>` |

### Modules à la demande

| Source | Colonnes / réponse | Filtre |
|---|---|---|
| `attendance` | colonnes nécessaires à l'historique | RLS : propres enfants; période |
| `scan_log` | `id,sid,type,status,date,time,name,label,description,manual,escort_kind,escort_name,created_at` | propres enfants; période |
| `devoirs` | colonnes complètes nécessaires à l'écran | classes de ses enfants; statuts publiés côté UI selon contrat |
| `grades` | colonnes complètes nécessaires au bulletin | propres enfants; année/trimestre |
| `appreciations` | colonnes complètes | propres enfants |
| `conduct` | colonnes complètes | propres enfants |
| `aps` | colonnes complètes autorisées | propres enfants |
| RPC `get_parent_fee_summary(p_sid)` | résumé financier serveur | un enfant lié à la fois |
| RPC `get_my_palmares_publications()` | publications autorisées | aucun filtre navigateur supplémentaire de sécurité |
| RPC `issue_student_qr(p_sid)` | QR quotidien | propre enfant uniquement |

Ne jamais charger directement : `users` des autres personnes, `profiles`, salaires, comptabilité, audit, médical global, paiements d'autres élèves ou notes d'autres classes.

## 8. Gardien — `gardien`

Le Gardien utilise des RPC minimales ; il ne charge pas directement tous les élèves.

### Démarrage

| Source | Réponse / colonnes | Filtre |
|---|---|---|
| RPC `get_scanner_students()` | contrat du registre | aucun; serveur retourne élèves actifs non archivés |
| RPC `get_scanner_aps()` | contrat du registre | serveur retourne uniquement personnes approuvées/actives/valides |
| `attendance` | `id,sid,cid,date,status,arr_time,manual,created_at` | `date=eq.<aujourd'hui Kinshasa>` |
| `scan_log` | `id,sid,type,status,date,time,name,label,description,manual,escort_kind,escort_id,escort_name,created_at` | `date=eq.<aujourd'hui Kinshasa>` |
| `notifs` | colonnes communes | `uid=eq.<app_user_id>` |

### Actions

```text
QR reçu           → verify_student_qr(mat,date,signature)
matricule résolu  → sid retourné par verify_student_qr ou get_scanner_students
contrôle portail  → check_gate_access_status(sid,source)
entrée autorisée  → record_entry_scan(...)
sortie autorisée  → record_exit_scan(...)
incident/refus    → record_scan_incident(...)
```

Le Gardien ne reçoit jamais montant, devise, trimestre, solde, obligation, reçu ou motif financier détaillé.

## 9. Cadence et cache

- `get_safe_settings` : au démarrage puis toutes les 15 minutes, avec désynchronisation aléatoire ±25 %.
- notifications : démarrage puis toutes les 60 secondes, pagination/incrémental.
- données pédagogiques : au changement d'écran et actualisation manuelle ; pas de rechargement intégral chaque minute.
- scanner : liste minimale au démarrage, actualisation toutes les 5 minutes ou après modification connue.
- décision financière du portail : cache **5 minutes maximum**.
- données financières détaillées : chargement à la sélection de l'élève, jamais pour toute l'école sur le téléphone du Gardien/Parent.

## 10. Garde-fou de développement

La table de configuration frontend doit avoir une forme unique et contrôlable :

```js
ROLE_LOAD = {
  direction:  { bootstrap: [...], modules: {...} },
  direction2: { bootstrap: [...], modules: {...} },
  direction3: { bootstrap: [...], modules: {...} },
  enseignant: { bootstrap: [...], modules: {...} },
  parent:     { bootstrap: [...], modules: {...} },
  gardien:    { bootstrap: [...], modules: {...} },
};
```

Toute source absente de `ROLE_LOAD[role]` est interdite par défaut. Une nouvelle table exige une mise à jour explicite de cette matrice et une vérification RLS avant intégration.
