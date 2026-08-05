# SchoolSafe — validation backend des lots J2 et J3

**Date : 3 août 2026**  
**Branche backend :** `agent/payment-control-backend-v1`  
**Branche frontend contrôlée :** `claude/new-session-guwhgl` au commit `182750b`

## 1. Contrôle du chargement Parent livré au J2

Le découpage par rôle est une amélioration importante : le Parent ne doit plus recevoir les données financières, médicales, salariales ou les notes de toute l'école.

### Sources confirmées

- `matieres` : la lecture est autorisée par la politique `matieres_read` au moyen de `private.can_view_class(cid)`.
- `classes` et `students` : les politiques RLS limitent les lignes aux classes et enfants visibles par la session.
- `users` : un Parent ne peut lire que sa propre fiche. Il ne peut pas utiliser l'annuaire global pour obtenir le nom de l'enseignant.

### Sources non encore autorisées au Parent

Les tables suivantes ont actuellement uniquement une politique `ALL` réservée à Direction 1 :

- `timetables` — politique `timetables_direction_all` ;
- `cahier_texte` — politique `cahier_texte_direction_all`.

Conséquence : un appel Parent reçoit un refus RLS. Ces deux tables ne doivent pas être ajoutées au `ROLE_LOAD.parent` tant qu'un contrat de lecture pédagogique n'a pas été défini et testé.

Décision temporaire sûre pour le frontend :

1. retirer `timetables` et `cahier_texte` du chargement Parent ;
2. utiliser l'état `not_applicable`, pas un faux tableau vide ;
3. ne jamais contourner le refus avec une clé serveur dans le navigateur ;
4. masquer temporairement l'écran concerné ou afficher clairement que le module n'est pas encore raccordé.

### Nom de l'enseignant dans l'espace Parent

La table `classes` contient `teacher_id`, `teacher_id_en` et `titulaire_id`, mais pas le nom dénormalisé. La politique `users_read` interdit au Parent de lire les autres utilisateurs.

Il n'existe actuellement aucune RPC publique dédiée qui retourne le titulaire de la classe au Parent. Jusqu'à création d'un contrat explicite :

- ne pas interroger `users` ;
- ne pas afficher un nom déduit localement ;
- afficher seulement le nom de la classe, ou masquer la ligne du titulaire.

## 2. Origines CORS R2

Contrôle du code actif des trois Edge Functions :

- `r2-upload` version 4 ;
- `r2-files` version 5 ;
- `r2-archives` version 1.

Leurs origines par défaut contiennent déjà :

```text
https://cslesage.com
https://www.cslesage.com
```

Aucune nouvelle version Edge n'est nécessaire pour ce point. Les fonctions gardent `verify_jwt=true`.

## 3. Test transactionnel du parcours financier J3

Test exécuté sous une session authentifiée, avec données synthétiques et `ROLLBACK` final.

### Données temporaires

- obligation : `100 USD` ;
- échéance dépassée ;
- paiement confirmé : `40 USD` ;
- allocation explicite sur l'obligation : `40 USD`.

### Résultat de `record_payment_transaction`

- transaction créée ;
- reçu généré au format `SS-YYYYMMDD-XXXXXXXX` ;
- montant confirmé : `40 USD` ;
- statut : `confirmed`.

### Résultat Caisse — `get_cashier_student_fee_detail`

```text
amount_due    100 USD
amount_paid    40 USD
balance        60 USD
status         overdue
access_status  orient
```

### Résultat Parent — `get_parent_fee_summary`

Le Parent lié reçoit exactement le même état financier autorisé :

```text
amount_due    100 USD
amount_paid    40 USD
balance        60 USD
status         overdue
access_status  orient
```

Le reçu confirmé est présent dans `receipts[]`. Le paiement partiel n'est donc plus confondu avec une absence totale de paiement.

### Règle frontend obligatoire

- Ne pas recalculer le solde ou la décision d'accès dans JavaScript.
- Afficher `status`, `balance`, `totals_by_currency`, `obligations[]` et `receipts[]` retournés par le serveur.
- Respecter `access_status=orient` même si l'obligation est `overdue` : dans ce test, `control_enabled=false`, donc le serveur autorise l'accès avec suivi administratif.
- Ne jamais remplacer cette décision par l'ancien booléen trimestriel.

## 4. Nettoyage vérifié

Après `ROLLBACK` :

```text
classes       0
students      0
fee_types     0
obligations   0
transactions  0
```

Aucune donnée réelle de l'école n'a été utilisée ou modifiée.

## 5. Suite attendue de Claude

1. Corriger le `ROLE_LOAD.parent` pour ne pas appeler `timetables` et `cahier_texte` avant contrat RLS.
2. Ne pas charger l'annuaire `users` pour afficher le titulaire.
3. Brancher J3 uniquement sur les RPC financières du registre.
4. Tester au minimum : paiement total, paiement partiel, aucune obligation, devise différente, allocation invalide et session non autorisée.
5. Conserver la publication sur `main` pour la recette finale et l'autorisation explicite de Loms.
