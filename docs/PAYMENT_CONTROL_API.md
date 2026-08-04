# SchoolSafe — Contrat API du contrôle des frais

Date : 4 août 2026
Responsable backend : ChatGPT
Responsable intégration UI : Claude

## État

Le backend de contrôle des frais est appliqué au projet SchoolSafe.
Il utilise un modèle additif et conserve la table historique `payments` uniquement pour la compatibilité avec l'application existante.

Migrations de base et correctifs principaux :

```text
20260802205234_add_payment_control_backend_v1
20260804031728_add_secure_payment_reversal_rpc
20260804032053_fix_cashier_payment_school_year_source
```

## Tables

- `student_fee_obligations` : montants exigibles par élève, type de frais, année, tranche et échéance.
- `payment_transactions` : versements confirmés ou contrepassés, avec reçu et agent de caisse.
- `payment_allocations` : ventilation d'un versement sur une ou plusieurs obligations.
- `payment_access_exceptions` : dérogations temporaires accordées exclusivement par Direction 1.
- `payment_scan_log` : journal minimal du contrôle ; aucun montant n'y est stocké.

## RPC publiques à utiliser

### Parent

`get_parent_fee_summary(p_sid text) -> jsonb`

Autorisation : rôle `parent` et relation parent-enfant obligatoire.

Réponse :

```json
{
  "student_found": true,
  "student_id": "STU-001",
  "student_name": "Nom élève",
  "matricule": "MAT-001",
  "class_id": "CLS-01",
  "school_year": "2026-2027",
  "status": "partial",
  "access_status": "allowed",
  "allowed": true,
  "next_due_date": "2026-09-30",
  "totals_by_currency": [
    {
      "currency": "USD",
      "amount_due": 400,
      "amount_paid": 250,
      "balance": 150
    }
  ],
  "obligations": [],
  "receipts": []
}
```

États possibles : `up_to_date`, `due_soon`, `partial`, `pending`, `overdue`, `exception`, `blocked`, `unavailable`.

### Direction 1 et Caisse

`get_cashier_student_fee_detail(p_sid text) -> jsonb`

Autorisation : `direction` ou `direction3`.
La réponse contient le même résumé complet que la réponse Parent, mais peut être utilisée dans l'écran de Caisse.

### Gardien / scanner minimal

`get_gate_access_status(p_sid text) -> jsonb`

`check_gate_access_status(p_sid text, p_source text default 'qr') -> jsonb`

La deuxième fonction journalise le contrôle. `p_source` vaut `qr` ou `manual`.

Réponse minimale :

```json
{
  "student_id": "STU-001",
  "student_name": "Nom élève",
  "matricule": "MAT-001",
  "class_id": "CLS-01",
  "class_name": "3e Primaire",
  "photo_url": "...",
  "access_status": "allowed",
  "instruction": "Accès autorisé",
  "checked_at": "2026-08-02T20:52:34Z"
}
```

Le résultat Gardien ne contient jamais : montant dû, montant payé, solde, reçu, moyen de paiement ou historique financier.

### Enregistrement d'un paiement

`record_payment_transaction(...) -> jsonb`

Paramètres :

- `p_sid text`
- `p_amount numeric`
- `p_currency text default 'USD'`
- `p_payment_method text default 'cash'`
- `p_external_reference text default null`
- `p_note text default null`
- `p_payment_date date default null`
- `p_allocations jsonb default null`

Autorisation : `direction` ou `direction3`.

L'année scolaire vient exclusivement de `private.current_school_year()` ; le navigateur ne l'envoie pas et la Caisse n'a pas besoin d'accéder directement à la table sensible `settings`.

Sans allocations explicites, le serveur répartit automatiquement le montant sur les obligations ouvertes les plus anciennes. Le paiement est refusé si le montant dépasse le solde exigible ou si aucune obligation compatible n'existe.

Retour confirmé :

```json
{
  "transaction_id": "ptx_...",
  "receipt_no": "SS-YYYYMMDD-XXXXXXXX",
  "student_id": "STU-001",
  "amount": 40,
  "currency": "USD",
  "payment_date": "2026-08-04",
  "school_year": "2025-2026",
  "status": "confirmed"
}
```

### Contrepassation d'un paiement

`reverse_payment_transaction(p_transaction_id text, p_reason text) -> jsonb`

Autorisation : `direction` ou `direction3`.

Règles :

- le paiement doit être `confirmed` ;
- le motif contient 5 à 500 caractères ;
- le paiement et ses allocations ne sont jamais supprimés ;
- le statut devient `reversed` ;
- `reversed_at`, `reversed_by` et `reversal_reason` sont enregistrés ;
- une deuxième contrepassation est refusée ;
- après succès, l'interface recharge le résumé serveur de l'élève.

Retour :

```json
{
  "ok": true,
  "code": "PAYMENT_REVERSED",
  "transaction_id": "ptx_...",
  "student_id": "STU-001",
  "receipt_no": "SS-YYYYMMDD-XXXXXXXX",
  "amount": 40,
  "currency": "USD",
  "status": "reversed",
  "reversed_by": "USER-ID",
  "reversed_at": "2026-08-04T03:21:16Z",
  "reason": "Erreur de saisie contrôlée"
}
```

### Dérogation temporaire

- `grant_payment_access_exception(p_sid, p_ends_at, p_reason, p_starts_at)`
- `revoke_payment_access_exception(p_exception_id, p_reason)`

Autorisation : Direction 1 uniquement.

## Règles pour Claude

1. Ne jamais lire directement toutes les tables financières pour construire l'écran Parent.
2. Utiliser `get_parent_fee_summary` pour le Parent.
3. Utiliser `get_cashier_student_fee_detail` pour Direction 1 et Caisse.
4. Utiliser `record_payment_transaction` pour toute nouvelle recette.
5. Utiliser `reverse_payment_transaction` pour toute annulation ; ne jamais modifier directement `payment_transactions`.
6. Utiliser `check_gate_access_status` pour le contrôle du portail.
7. Ne jamais calculer le solde comme source de vérité dans JavaScript.
8. Masquer totalement le module financier pour Direction 2 et Enseignant.
9. Ne jamais afficher de montant au Gardien.
10. Ne créer aucune table, politique RLS ou fonction SQL depuis le frontend.
11. Ne jamais exposer `service_role` ou une clé secrète dans le navigateur.
12. Toute modification du contrat doit être validée par ChatGPT avant intégration.
