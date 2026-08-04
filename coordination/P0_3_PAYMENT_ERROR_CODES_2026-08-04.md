# P0-3 — codes réels des RPC de paiement

Date : 4 août 2026  
Projet : SchoolSafe, école unique

## Méthode

Les scénarios ont été exécutés contre les fonctions réellement déployées :

- `record_payment_transaction(...)` ;
- `reverse_payment_transaction(...)`.

Une identité Auth active a été utilisée, avec changement de rôle uniquement dans une transaction PostgreSQL terminée par `ROLLBACK`.

Toutes les classes, élèves, obligations et transactions de recette étaient fictifs. Contrôle après rollback :

```text
classes       0
students      0
fee_types     0
obligations   0
transactions  0
```

## Résultats exacts

| # | Scénario | Résultat serveur | `error.code` / SQLSTATE | Message serveur |
|---|---|---|---|---|
| 1 | Versement normal par la Caisse | succès, `contract_version: 2`, `status: confirmed`, `recorded_by_role: direction3` | — | — |
| 2 | Versement supérieur au solde exigible | erreur | `22023` | `Montant supérieur au solde exigible ou aucune obligation configurée` |
| 3 | Versement par un rôle non autorisé | erreur | `42501` | `Accès refusé` |
| 4 | Contrepassation d’un paiement déjà contrepassé | erreur | `23514` | `Transaction déjà annulée ou indisponible` |
| 5 | Contrepassation par un rôle non autorisé | erreur | `42501` | `Accès refusé` |
| 6 | Versement sur un élève archivé | erreur | `P0002` | `Élève introuvable ou archivé` |
| 7 | Versement sur un élève bloqué mais non archivé | succès | — | Le paiement est accepté pour permettre la régularisation. |

## Point métier à ne pas mélanger

`archived=true` et `blocked=true` ne signifient pas la même chose :

- un élève **archivé** n’est plus une cible de paiement active ;
- un élève **bloqué** doit encore pouvoir payer, sinon sa famille ne peut pas régulariser la situation qui a provoqué le blocage.

Le frontend ne doit donc pas afficher une erreur pour un paiement confirmé concernant un élève bloqué.

## Traduction recommandée dans `window._CODE_MSG`

```js
Object.assign(window._CODE_MSG, {
  '22023': 'Le montant dépasse le solde exigible ou aucun frais n’est configuré pour cet élève.',
  '42501': 'Votre profil n’est pas autorisé à effectuer cette opération.',
  '23514': 'Ce paiement a déjà été contrepassé ou n’est plus disponible.',
  'P0002': 'L’élève est introuvable ou son dossier est archivé.'
});
```

Le texte serveur reste disponible comme repli, mais l’interface de Caisse doit privilégier ces formulations orientées action.

## Rappels scanner — P0-4 et P0-5

Les deux contrats déjà déployés sont confirmés :

```text
record_entry_scan / record_exit_scan
→ réponse directe { recorded, allowed, reason, ... }
→ aucune enveloppe { ok, data }

access_status = orient
→ allowed = false
→ l’élève ne passe pas automatiquement
→ aucune présence et aucune entrée ne sont enregistrées
```

Ces deux points peuvent être fermés côté frontend.