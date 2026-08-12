# P0-1b — Intégrité des allocations de paiement

> Branche ChatGPT : `chatgpt/p0-1b-payment-allocation-hardening`
> Statut : **DRAFT — aucune production modifiée**.
> Suivi : issue #92.

## Pourquoi ce lot existe

Le ledger P0-1 est déjà la bonne architecture :

`student_fee_obligations -> payment_allocations -> payment_transactions`

Mais l'audit du Supabase réel a trouvé deux ouvertures :

1. `record_payment_transaction(...)` vérifie que la somme des allocations explicites égale le montant du reçu, mais il ne vérifie pas que chaque allocation reste sous le **solde réel de l'obligation** ;
2. `payment_allocations` est encore directement INSERT/UPDATE/DELETE pour `authenticated` (Direction/Caisse selon RLS), alors qu'une allocation confirmée doit être un fait comptable immuable.

`private.build_fee_summary()` plafonne ensuite `amount_paid` à `amount_due`. Une sur-allocation peut donc être masquée dans le solde affiché tandis que le reçu conserve le montant réellement encaissé. Ce lot ferme cette divergence.

## Règle comptable proposée

Une allocation est **append-only**.

- INSERT : seulement par le chemin serveur autorisé ;
- UPDATE : interdit ;
- DELETE : interdit ;
- une erreur d'encaissement se corrige avec `reverse_payment_transaction(...)`, jamais en réécrivant l'allocation.

## Trigger d'intégrité

Avant chaque nouvelle allocation, le serveur verrouille la transaction et l'obligation puis vérifie :

- transaction existante et `status='confirmed'` ;
- obligation existante et active ;
- même élève ;
- même année scolaire ;
- même devise ;
- total des allocations de cette transaction + nouvelle allocation <= montant du reçu ;
- total des allocations **confirmées** de cette obligation + nouvelle allocation <= montant dû.

Codes SQLSTATE proposés : `23514` avec des messages explicites (`ALLOCATION_EXCEEDS_TRANSACTION_AMOUNT`, `ALLOCATION_EXCEEDS_OBLIGATION_BALANCE`, etc.).

## Pourquoi un trigger en plus de la RPC

La RPC `record_payment_transaction` reste l'interface officielle et n'a pas besoin d'être réécrite pour ce correctif : son INSERT dans `payment_allocations` passe automatiquement par le trigger.

Le trigger protège aussi :

- une future Edge Function ;
- un script d'administration ;
- un service role mal utilisé ;
- une régression frontend si un ancien chemin direct revient.

## Verrouillage direct séparé

Le fichier `payment_allocation_direct_write_lockdown_AFTER_FRONTEND_DRAFT.sql` retire les droits d'écriture directs à `authenticated` et supprime les anciennes policies `pal_insert/pal_update/pal_delete`.

**Il ne doit pas être appliqué avant le retour Claude dans #92** confirmant qu'aucun bouton frontend ne dépend encore d'une écriture directe de `payment_allocations`.

## Ce que ce lot ne change pas encore

- `student_fee_obligations` : Direction 1 a encore des écritures directes ; il faut d'abord inventorier les écrans de configuration ;
- ancienne table `payments` : elle garde son trigger de provenance et ses protections historiques ; on l'éteindra seulement après inventaire des derniers écrans ;
- `payment_transactions` : déjà non modifiable directement par `authenticated` ;
- reçus / numérotation / contrepassation : contrats P0-1 inchangés.

## Claude — vérification demandée

Sur le `main` actuel :

```bash
node tools/audit-schema.mjs --table payment_allocations --verbose
node tools/audit-schema.mjs --table payments --verbose
```

Pour chaque écriture trouvée : fonction, écran, bouton et intention métier. On ne retire rien au hasard.

## Déploiement

Tous les SQL restent sous `supabase/drafts/` avec `ROLLBACK` final. Aucune production, Auth, R2 ou VPS n'est modifiée par cette branche.
