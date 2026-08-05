# SchoolSafe — validation backend Archives et contrepassation des paiements

**Date : 4 août 2026**  
**Branche backend :** `agent/payment-control-backend-v1`  
**Branche frontend contrôlée :** `claude/new-session-guwhgl`

## 1. Résumé des archives

La fonction `public.get_archive_summary()` est active, versionnée et limitée à Direction 1.

### Signature

```sql
get_archive_summary()
```

### Retour

Une ligne par année scolaire :

```text
academic_year   text
file_count      bigint
 total_bytes     bigint
archived_count  bigint
active_count    bigint
```

`file_count` et `total_bytes` couvrent tous les fichiers non supprimés de l'année. `archived_count` et `active_count` donnent la ventilation.

### Accès

- Direction 1 authentifiée : autorisée.
- Autres rôles : refus interne `42501`.
- `anon` : aucun droit `EXECUTE`.
- Edge Function `r2-archives` : peut continuer à appeler cette RPC avec le JWT utilisateur.

Une réponse HTTP 200 avec `years: []` signifie simplement qu'aucun fichier n'est encore enregistré/archivé. Ce n'est pas un contrat manquant.

Migration :

```text
20260804031656_align_and_secure_archive_summary_contract.sql
```

## 2. Défaut Caisse corrigé dans `record_payment_transaction`

### Cause

La RPC lisait directement `public.settings`. La politique RLS cache cette table à Direction 3. Le rôle Caisse obtenait donc une année scolaire `NULL`, puis PostgreSQL refusait l'insertion dans `payment_transactions.school_year`.

### Correction

La RPC utilise maintenant :

```sql
private.current_school_year()
```

Cette fonction serveur lit l'année active sans exposer les autres paramètres sensibles de `settings`.

### Contrat inchangé côté frontend

```sql
record_payment_transaction(
  p_sid,
  p_amount,
  p_currency,
  p_payment_method,
  p_external_reference,
  p_note,
  p_payment_date,
  p_allocations
)
```

Le retour contient désormais explicitement `school_year` en plus de `transaction_id`, `receipt_no`, `amount`, `currency`, `payment_date` et `status`.

Migration :

```text
20260804032053_fix_cashier_payment_school_year_source.sql
```

## 3. Nouvelle RPC de contrepassation

Ne plus modifier directement `payment_transactions` depuis le navigateur.

### Signature

```sql
reverse_payment_transaction(
  p_transaction_id text,
  p_reason text
)
```

### Règles

- rôles autorisés : Direction 1 et Caisse/Direction 3 ;
- transaction obligatoirement `confirmed` ;
- motif obligatoire de 5 à 500 caractères ;
- verrou PostgreSQL `FOR UPDATE` pour éviter deux annulations concurrentes ;
- aucune suppression de transaction ni d'allocation ;
- mise à jour auditée de `status`, `reversed_at`, `reversed_by` et `reversal_reason` ;
- une deuxième contrepassation est refusée.

### Retour de succès

```json
{
  "ok": true,
  "code": "PAYMENT_REVERSED",
  "transaction_id": "ptx_...",
  "student_id": "...",
  "receipt_no": "SS-YYYYMMDD-XXXXXXXX",
  "amount": 40,
  "currency": "USD",
  "status": "reversed",
  "reversed_by": "...",
  "reversed_at": "...",
  "reason": "Erreur de saisie contrôlée"
}
```

Migration :

```text
20260804031728_add_secure_payment_reversal_rpc.sql
```

## 4. Test réel Direction 3 avec nettoyage final

Test effectué avec un compte Caisse, un élève, une obligation de 100 USD et un paiement de 40 USD, tous temporaires.

### Avant contrepassation

```text
amount_due   100 USD
amount_paid   40 USD
balance       60 USD
receipt       confirmed
```

### Après contrepassation

```text
amount_due   100 USD
amount_paid    0 USD
balance      100 USD
receipt       reversed
```

La deuxième tentative a été rejetée avec :

```text
SQLSTATE 23514
Transaction déjà annulée ou indisponible
```

Le test a utilisé `ROLLBACK`. Contrôle final :

```text
auth_users   0
app_users    0
invitations  0
students     0
transactions 0
```

## 5. Raccordement attendu de Claude

1. Pour l'écran Archives, traiter `years: []` comme un état vide autorisé et non comme une panne.
2. Utiliser les champs `file_count`, `total_bytes`, `archived_count`, `active_count`.
3. Remplacer toute mise à jour directe d'annulation par `reverse_payment_transaction`.
4. Demander un motif avant l'appel et garder le reçu visible avec le statut `reversed`.
5. Après succès, recharger `get_cashier_student_fee_detail(p_sid)` ; ne pas recalculer le solde en JavaScript.
6. Sur `23514`, afficher que la transaction est déjà annulée ou indisponible.
7. Aucun merge ou publication `main` par ChatGPT ; Claude conserve la recette et la publication finale après autorisation de Loms.
