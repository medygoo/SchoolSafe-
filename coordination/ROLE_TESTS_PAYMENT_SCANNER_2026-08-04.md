# SchoolSafe — recette authentifiée Paiements et Scanner

**Date :** 4 août 2026  
**Projet Supabase :** SchoolSafe  
**Méthode :** données entièrement fictives, transaction PostgreSQL terminée par `ROLLBACK`.

## Résultat général

Les contrats Paiement v2 et Scanner v2 ont été joués avec les six profils de
l'application : Direction 1, Direction 2, Caisse, Gardien, Enseignant et Parent.

Aucun élève, parent, paiement, présence, scan, dérogation, personne autorisée ou
compteur de reçu créé pour la recette n'a été conservé.

## Données fictives utilisées

La transaction a créé temporairement :

- une classe de recette ;
- un élève fictif relié à un tuteur fictif ;
- une obligation de minerval de **100 USD**, échue la veille ;
- une personne autorisée fictive, approuvée et munie d'une photo fictive ;
- un paiement de **40 USD** ;
- une dérogation temporaire d'accès.

Ces montants ne sont pas des données ni des tarifs de l'école. Ils servent
uniquement à vérifier les calculs du contrat.

## 1. Parent

| Contrôle | Résultat |
|---|---|
| résumé de son propre enfant | réussi |
| obligation non vide | réussi |
| champs `amount_due`, `amount_paid`, `balance`, `status` | présents |
| reçu confirmé visible | réussi |
| reçu contrepassé conservé | réussi |
| accès au dossier financier d'un autre enfant | refusé |

Après le paiement fictif de 40 USD :

```json
{
  "amount_due": 100,
  "amount_paid": 40,
  "balance": 60,
  "receipt_status": "confirmed"
}
```

Après contrepassation :

```json
{
  "amount_paid": 0,
  "balance": 100,
  "receipt_status": "reversed"
}
```

Le reçu n'est donc jamais supprimé.

## 2. Caisse — Direction 3

| Contrôle | Résultat |
|---|---|
| lecture du détail financier | réussi |
| paiement avec allocation explicite | réussi |
| contrat retourné | version 2 |
| numéro de reçu | `REC-2025-2026-000001` dans la transaction |
| auteur figé | rôle `direction3` |
| contrepassation avec motif | réussie |
| auteur de contrepassation figé | rôle `direction3` |

La Caisse voit la raison financière détaillée : `Frais en retard`.

## 3. Gardien

### Orientation et blocage

Pour une obligation échue :

```json
{
  "access_status": "orient",
  "allowed": false,
  "financial_reason": null
}
```

Quand le blocage strict est activé :

```json
{
  "access_status": "blocked",
  "allowed": false,
  "financial_reason": null
}
```

Le Gardien reçoit uniquement l'instruction publique : orienter vers la Caisse.
Le contrat minimal ne contient aucun montant, aucune devise, aucun trimestre,
aucun solde et aucune raison financière.

### Un refus n'est pas une entrée

L'appel `record_entry_scan` pendant l'orientation a renvoyé :

```json
{
  "recorded": false,
  "allowed": false,
  "reason": "orientation_required"
}
```

Après cet appel :

```text
présences créées     0
scans d'entrée créés 0
```

### Téléphones

Le Gardien voit :

- le téléphone du tuteur principal ;
- le téléphone d'une personne autorisée active et approuvée.

### Incidents

Une note volontairement financière envoyée par le Gardien a été remplacée par :

```text
Décision administrative — contrôle manuel requis
```

Aucun montant, devise ou trimestre n'a été conservé dans `scan_log.note`.

### Dérogation et sorties

| Contrôle | Résultat |
|---|---|
| entrée avec dérogation active | enregistrée |
| deuxième entrée du même jour | refusée comme doublon |
| sortie avec accompagnateur inexistant | `invalid_escort`, non enregistrée |
| sortie avec tuteur principal | enregistrée |

## 4. Enseignant

L'Enseignant peut utiliser le contrat de scan, mais reçoit :

```json
{
  "primary_guardian_phone": null,
  "authorized_person_phone": null
}
```

Les coordonnées privées ne lui sont pas transmises.

## 5. Direction 2

Direction 2 peut utiliser le contrôle de présence et reçoit le contrat public
minimal :

```json
{
  "access_status": "allowed",
  "financial_reason": null
}
```

Elle ne reçoit ni le téléphone du tuteur principal ni celui de la personne
autorisée. L'appel au détail financier de la Caisse est refusé.

## 6. Direction 1

Direction 1 a pu créer la dérogation temporaire utilisée par la recette. Elle
reste le rôle de contrôle complet, conformément au contrat.

## 7. Contrôles d'autorisation négatifs

| Tentative | Résultat |
|---|---|
| Gardien enregistre un paiement | refus SQLSTATE `42501` |
| Direction 2 ouvre le détail Caisse | refusée |
| Parent ouvre les frais d'un autre élève | refusée |
| accompagnateur non accrédité valide une sortie | refusé |

## 8. Conclusion

Les points suivants sont confirmés sur la base réellement déployée :

1. le solde et l'état financier sont calculés par le serveur ;
2. la Caisse et Direction 1 sont les seuls profils financiers ;
3. Direction 2, Gardien et Enseignant ne reçoivent aucune donnée monétaire ;
4. `orient` signifie toujours `allowed=false` ;
5. une orientation ou un refus ne crée jamais une présence ;
6. une contrepassation conserve le reçu et ses auteurs ;
7. les coordonnées des accompagnateurs sont limitées selon le rôle ;
8. les doublons d'entrée et de sortie sont bloqués.

**Données fictives conservées après recette : 0.**
