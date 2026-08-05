# SchoolSafe — audit et corrections des RPC scanner historiques

Date : 3 août 2026  
Responsable backend : ChatGPT  
Responsable intégration finale et publication : Claude

## Migration appliquée

- Supabase : `20260803160839_fix_scanner_rpc_edge_cases`
- GitHub : `supabase/migrations/20260803160839_fix_scanner_rpc_edge_cases.sql`

## Fonctions auditées

- `evaluate_student_access`
- `get_scanner_aps`
- `get_scanner_students`
- `issue_student_qr`
- `record_entry_scan`
- `record_exit_scan`
- `record_scan_incident`
- `verify_student_qr`
- `check_gate_access_status`

## Défauts corrigés

### 1. QR ou identifiant élève inconnu

`check_gate_access_status` appelait correctement la décision serveur, mais tentait
ensuite d'écrire l'identifiant inconnu dans `payment_scan_log.sid`, colonne non
nulle liée par clé étrangère à `students.id`.

Conséquence avant correction : la réponse « élève introuvable » pouvait être
remplacée par une erreur SQL de clé étrangère.

Correction : le journal financier minimal n'est écrit que lorsque la RPC a
réellement identifié un élève. Un QR inconnu retourne maintenant :

```text
access_status = unavailable
instruction = Élève introuvable — contrôle manuel requis
```

sans insertion invalide.

### 2. Mauvaise vérification dans `record_scan_incident`

La fonction chargeait d'abord l'élève, puis l'utilisateur, et testait `FOUND`
seulement après la deuxième requête. Elle pouvait donc croire qu'un élève
existait alors que seul le profil scanner avait été trouvé.

Correction :

- l'élève est contrôlé immédiatement après sa lecture ;
- les élèves archivés sont refusés ;
- le profil scanner actif est contrôlé séparément ;
- un identifiant élève inconnu retourne `recorded=false` et
  `reason=unknown_student`.

### 3. Fuite possible par une note d'incident

Le paramètre libre `p_note` pouvait contenir un motif financier saisi par le
Gardien, Direction 2 ou un Enseignant, puis être stocké dans `scan_log` et relu
par d'autres profils.

Correction :

- Direction 1 et Caisse/Direction 3 peuvent conserver une note détaillée ;
- Gardien, Direction 2 et Enseignant ne peuvent stocker que des libellés
  administratifs génériques issus d'une liste contrôlée ;
- aucune note financière libre n'est conservée pour ces rôles.

### 4. Message de blocage harmonisé

`evaluate_student_access` utilise désormais le même message générique que le
contrat portail :

```text
Accès non autorisé — orienter vers la Caisse
```

Le détail `financial_reason` reste produit uniquement pour Direction 1 et
Caisse/Direction 3.

## Permissions vérifiées

Pour les trois fonctions modifiées :

- `PUBLIC` : aucun droit ;
- `anon` : aucun droit ;
- `authenticated` : `EXECUTE` avec contrôle du rôle SchoolSafe ;
- `service_role` : `EXECUTE` ;
- `search_path=''`.

`check_gate_access_status` reste `SECURITY INVOKER`.
`evaluate_student_access` et `record_scan_incident` restent volontairement
`SECURITY DEFINER`, car elles doivent accéder à des données protégées sans ouvrir
les tables sous-jacentes aux profils de scan. Elles contrôlent le rôle dans leur
corps et leurs droits d'exécution sont explicites.

Le conseiller Supabase continue donc à produire un avertissement générique
`authenticated_security_definer_function_executable`. Cet avertissement est
attendu pour les RPC exposées intentionnellement, mais les autres fonctions
historiques doivent encore être examinées une par une.

Remédiation Supabase :
https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable

## Tests exécutés

- QR/identifiant inconnu via `check_gate_access_status` : réponse
  `unavailable`, aucune erreur SQL ;
- variation du journal `payment_scan_log` : `0` ligne ajoutée pour un identifiant
  inconnu ;
- incident sur élève inconnu : `recorded=false`, `reason=unknown_student` ;
- ACL, `search_path` et mode invoker/definer vérifiés ;
- tests réalisés dans des transactions terminées par `ROLLBACK` ;
- aucune donnée de test conservée.

## Points restant ouverts — aucune modification automatique

### `get_scanner_students()`

Retourne actuellement tous les élèves actifs ainsi que l'identifiant, le nom et
le téléphone du tuteur principal à tout rôle autorisé à scanner. La prochaine
étape doit remplacer ce chargement global par des données minimales et filtrées
selon le rôle.

### `get_scanner_aps()`

Retourne actuellement toutes les personnes accréditées actives. La prochaine
étape doit privilégier une recherche liée à l'élève scanné plutôt qu'un
chargement général sur chaque téléphone.

### `issue_student_qr(p_sid)`

Tout rôle autorisé à scanner peut actuellement produire un QR valide pour tout
élève actif. La lecture/scannage et l'émission d'un QR sont deux permissions
différentes. Le rôle exact autorisé à émettre ou réémettre un QR doit être fixé
avant modification afin de ne pas casser le parcours existant.

## Handoff Claude

Claude doit :

- utiliser les réponses serveur corrigées ;
- ne pas recréer une entrée lorsqu'un accès est refusé ;
- traiter `unknown_student` comme contrôle manuel ;
- ne jamais envoyer une note financière libre depuis Gardien, Direction 2 ou
  Enseignant ;
- exécuter les tests complets avec comptes temporaires lors de l'intégration ;
- demander l'autorisation de Loms avant de fusionner et publier `main`.
