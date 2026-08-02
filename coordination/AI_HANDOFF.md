# AI HANDOFF — Module de contrôle des frais

Date : 2 août 2026
Statut : backend v1 appliqué dans Supabase ; frontend non encore modifié.

## Travail terminé par ChatGPT

- Audit du schéma et des politiques RLS.
- Confirmation que Direction 2 est exclue des données de paiement.
- Création des tables :
  - `student_fee_obligations`
  - `payment_transactions`
  - `payment_allocations`
  - `payment_access_exceptions`
  - `payment_scan_log`
- Création des contraintes, index, triggers et politiques RLS.
- Création des RPC Parent, Caisse et Gardien.
- Mise à jour compatible de `evaluate_student_access`.
- Conservation de la table historique `payments` pour ne pas casser l'application actuelle.

Migration Supabase appliquée : `20260802205234_add_payment_control_backend_v1`.

## Mission de Claude

### Lot A — Espace Parent

Branche recommandée : `feature/parent-fees-dashboard`

1. Dans le tableau de bord Parent, présenter trois cartes au même niveau :
   - Devoirs
   - Interrogations
   - Frais scolaires
2. Séparer les devoirs des interrogations en utilisant le champ `category` de `devoirs`.
3. Ajouter la page `frais_parent`.
4. Utiliser uniquement `get_parent_fee_summary(p_sid)`.
5. Gérer la sélection de plusieurs enfants sans mélanger les données.
6. Afficher : statut, montants par devise, prochaine échéance, obligations et reçus.
7. Le Parent ne peut modifier, confirmer ou annuler aucun paiement.

### Lot B — Caisse

Branche recommandée : `feature/payment-scanner-ui`

1. Ajouter « Contrôle des frais » dans le profil Caisse.
2. Réutiliser le QR actuel de l'élève ou permettre la saisie du matricule.
3. Utiliser `get_cashier_student_fee_detail(p_sid)` pour le détail.
4. Utiliser `record_payment_transaction(...)` pour enregistrer un versement.
5. Afficher le numéro de reçu renvoyé par le serveur.
6. Ne jamais considérer une opération locale comme définitivement validée avant réponse serveur.

### Lot C — Gardien

1. Utiliser `check_gate_access_status(p_sid, source)`.
2. Afficher seulement : photo, identité, classe, statut et instruction.
3. Ne jamais afficher de montant, solde, reçu ou motif financier détaillé.

## Restrictions obligatoires

- Ne modifier aucune table, migration, politique RLS ou fonction SQL.
- Ne pas utiliser `service_role`.
- Ne pas calculer le solde comme source de vérité côté navigateur.
- Ne pas ajouter le module financier à Direction 2 ou Enseignant.
- Ne pas fusionner directement dans `main`.
- Ouvrir une Pull Request en brouillon pour chaque lot.

## Contrats à lire

- `docs/PAYMENT_CONTROL_API.md`
- `docs/PAYMENT_CONTROL_RLS.md`

## Tests attendus de Claude

- Parent avec un enfant.
- Parent avec plusieurs enfants.
- Parent tentant d'accéder à un autre élève.
- Direction 2 : absence totale des montants et menus financiers.
- Caisse : paiement total et partiel.
- Gardien : réponse minimale.
- Réseau indisponible et reprise de connexion.
- Affichage mobile Android.

## Points restant à ChatGPT

- Ajouter les obligations réelles après validation des montants et échéances de l'école.
- Durcir les anciennes RPC scanner/QR signalées par les conseillers Supabase.
- Activer la protection contre les mots de passe compromis dans Supabase Auth.
- Revoir la Pull Request de Claude avant fusion.
