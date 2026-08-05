# SchoolSafe — Matrice RLS du contrôle des frais

## Principes

- Toutes les nouvelles tables ont RLS activé.
- `anon` n'a aucun droit sur les données financières.
- Direction 2 est exclue de toutes les lectures et écritures financières.
- Le Gardien reçoit uniquement une réponse calculée et minimale via RPC.
- Le Parent lit uniquement les lignes liées à ses propres enfants.
- Les annulations et dérogations restent auditables ; aucune suppression comptable silencieuse.

## Matrice

| Ressource | Direction 1 | Direction 2 | Caisse | Enseignant | Gardien | Parent |
|---|---|---|---|---|---|---|
| Obligations | CRUD | Aucun | Lecture | Aucun | Aucun | Lecture enfants |
| Transactions | Lecture + insertion + annulation | Aucun | Lecture + insertion | Aucun | Aucun | Lecture enfants |
| Allocations | CRUD contrôlé | Aucun | Lecture + insertion | Aucun | Aucun | Lecture enfants |
| Dérogations | CRUD contrôlé | Aucun | Lecture | Aucun | Aucun | Lecture enfants |
| Journal scans financiers | Lecture | Aucun | Lecture | Aucun | Insertion via RPC | Aucun |
| Résumé Parent | Aucun besoin direct | Aucun | Aucun | Aucun | Aucun | Enfants uniquement |
| Détail Caisse | Oui | Non | Oui | Non | Non | Non |
| Résultat portail minimal | Oui | Fonction de scan général uniquement, sans données financières | Oui | Oui pour les scans autorisés, sans données financières | Oui | Non |

## Politiques principales

### `student_fee_obligations`

- SELECT : Direction 1, Caisse ou parent propriétaire de l'élève.
- INSERT/UPDATE/DELETE : Direction 1 uniquement.

### `payment_transactions`

- SELECT : Direction 1, Caisse ou parent propriétaire de l'élève.
- INSERT : Direction 1 ou Caisse, avec `recorded_by` égal à l'utilisateur connecté.
- UPDATE : Direction 1 uniquement.
- Aucune suppression directe.

### `payment_allocations`

- SELECT : selon l'accès à la transaction liée.
- INSERT : Direction 1 ou Caisse.
- UPDATE/DELETE : Direction 1 uniquement.
- Un trigger empêche l'allocation au-delà du paiement ou du montant exigible.

### `payment_access_exceptions`

- SELECT : Direction 1, Caisse ou parent propriétaire.
- Écriture : Direction 1 uniquement.

### `payment_scan_log`

- SELECT : Direction 1 et Caisse.
- INSERT : profils autorisés à scanner, avec auteur et rôle imposés par la session.
- Les détails du journal ne contiennent pas les montants.

## Points de sécurité restant ouverts

Les conseillers Supabase signalent encore plusieurs anciennes RPC `SECURITY DEFINER` exécutables par `authenticated`, notamment les fonctions historiques du scanner, du QR et du palmarès. Elles effectuent déjà des contrôles de rôle dans leur corps, mais doivent faire l'objet d'un durcissement séparé afin de réduire leur surface exposée.

La protection Supabase Auth contre les mots de passe compromis est également désactivée et doit être activée depuis la configuration Auth.
