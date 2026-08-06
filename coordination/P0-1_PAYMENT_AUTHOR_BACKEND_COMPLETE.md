# P0-1 — auteur réel des encaissements : backend servi

Date : 6 août 2026  
Décision : Loms  
Backend : ChatGPT  
Intégration visible et recette navigateur : Claude

## État production

Migration active dans Supabase :

`p0_1_payment_provenance_and_immutable_transactions`

Migration miroir :

`supabase/migrations/20260806095000_p0_1_payment_provenance_and_immutable_transactions.sql`

Au moment de la migration, `payments`, `payment_transactions` et `student_fee_obligations` ne contenaient encore aucune ligne. La protection a donc été installée avant le premier encaissement, sans conversion ni perte de données.

## 1. Compatibilité immédiate avec l’écran actuel

L’ancien écran peut encore faire son écriture existante sur `payments`.

Lorsqu’une ligne passe de `paid=false` à `paid=true`, le serveur renseigne désormais lui-même :

- `recorded_by` : identifiant applicatif de la personne connectée ;
- `recorded_by_name` : nom figé au moment de l’encaissement ;
- `recorded_by_role` : `direction` ou `direction3` ;
- `recorded_at` : date et heure serveur ;
- l’ancien champ `by` est remplacé par le vrai nom du compte connecté.

Un nom envoyé par le navigateur ne peut donc plus devenir l’auteur officiel.

Une ligne déjà payée :

- ne peut plus repasser directement à `paid=false` ;
- ne peut plus être supprimée directement ;
- ne peut plus changer d’élève ou de trimestre ;
- conserve son auteur et son horodatage d’origine.

Toute confirmation écrit aussi l’événement `legacy_payment_confirmed` dans l’audit.

## 2. Registre financier définitif

`payment_transactions` reste le registre financier de référence.

Les écritures directes du navigateur sont maintenant interdites :

- pas de `INSERT` direct ;
- pas d’`UPDATE` direct ;
- pas de `DELETE` direct.

Le navigateur garde uniquement la lecture autorisée par rôle.

### Enregistrer un encaissement

Appeler :

```text
record_payment_transaction
```

Paramètres :

```json
{
  "p_sid": "identifiant élève",
  "p_amount": 100,
  "p_currency": "USD",
  "p_payment_method": "cash",
  "p_external_reference": null,
  "p_note": null,
  "p_payment_date": "2026-08-06",
  "p_allocations": null
}
```

Valeurs de `p_payment_method` :

- `cash`
- `bank`
- `mobile_money`
- `other`

Le serveur calcule ou impose :

- l’année scolaire ;
- le numéro de reçu unique ;
- l’auteur ;
- le nom de l’auteur ;
- le rôle de l’auteur ;
- l’horodatage ;
- la répartition sur les obligations scolaires.

La RPC refuse les rôles autres que Direction 1 et Caisse (`direction3`). Elle refuse aussi un élève archivé, un montant invalide et un montant supérieur au solde exigible.

### Contrepasser un encaissement

Appeler :

```text
reverse_payment_transaction
```

Paramètres :

```json
{
  "p_transaction_id": "ptx_...",
  "p_reason": "Motif administratif précis"
}
```

Ne jamais remettre un paiement à zéro par une écriture directe.

## 3. Affichage des reçus

Pour les reçus issus de l’ancien écran, afficher :

- `payments.recorded_by_name`
- `payments.recorded_by_role`
- `payments.recorded_at`

Pour les reçus du registre moderne, afficher :

- `payment_transactions.recorded_by_name`
- `payment_transactions.recorded_by_role`
- `payment_transactions.created_at`
- `payment_transactions.receipt_no`

Le libellé peut désormais devenir **« Établi par »** au lieu de « Délivré par ».

## 4. Travail Claude restant

1. Ajouter les quatre colonnes de provenance de `payments` aux lectures utiles.
2. Remplacer progressivement le `pushSync('payments', 'patch', {paid:true}, ...)` par `record_payment_transaction` dès que les obligations scolaires sont configurées.
3. Faire lire aux six reçus le nom, le rôle et la date enregistrés par le serveur.
4. Utiliser `reverse_payment_transaction` pour toute annulation.
5. Ne jamais envoyer ou calculer l’auteur officiel depuis le navigateur.
6. Exécuter les audits et la recette navigateur avant publication.

## 5. Recette production effectuée

Transaction avec `ROLLBACK` :

- insertion d’une ligne impayée de test ;
- tentative d’envoyer un faux nom d’auteur ;
- passage à payé accepté pour Direction 1 ;
- faux nom remplacé par `Loms Medy` ;
- rôle fixé à `direction` ;
- horodatage serveur présent ;
- tentative de repasser à non payé refusée ;
- aucune ligne de test restante.

Contrôles de droits :

- `authenticated` peut lire `payment_transactions` ;
- `authenticated` ne peut plus insérer, modifier ou supprimer directement ;
- `record_payment_transaction` est `SECURITY DEFINER`, avec `search_path` vide et contrôle interne du rôle.
