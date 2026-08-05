# AI HANDOFF — Paiements, scanner et Cloudflare R2

Date : 3 août 2026
Statut : backend paiements v1 appliqué ; `r2-files` version 3 active ; frontend non encore modifié.

## Répartition obligatoire

- ChatGPT : Supabase, base de données, migrations, RLS, RPC, sécurité, Cloudflare R2 côté serveur, contrats techniques et audit.
- Claude : application, interface, UX, écrans, navigation, appels frontend, PWA, affichage des erreurs et tests fonctionnels visibles.
- Claude ne modifie pas les tables, migrations, RLS, RPC, Edge Functions ou secrets sans validation de ChatGPT.

## Travail terminé par ChatGPT — Paiements

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
- Conservation de la table historique `payments`.

Migration : `20260802205234_add_payment_control_backend_v1`.

## Travail terminé par ChatGPT — R2

- Audit de la fonction existante `r2-files`.
- Ajout du lien `payment_transaction_id` entre reçu R2 et transaction.
- Ajout de `idempotency_key`, `deleted_at` et `deleted_by`.
- Ajout des index contre les doublons de reçus.
- Déploiement de `r2-files` version 3 avec JWT obligatoire.
- Autorisation Caisse limitée aux reçus liés à une transaction confirmée.
- Interdiction des finances pour Direction 2.
- Interdiction d’accès direct R2 pour le Gardien.
- Actions disponibles : `health`, `upload`, `download`, `list`, `archive`, `delete`.

Migration : `harden_r2_files_and_link_receipts`.

## Mission Claude — Lot A : Espace Parent

Branche recommandée : `feature/parent-fees-dashboard`

1. Présenter trois cartes au même niveau : Devoirs, Interrogations, Frais scolaires.
2. Séparer devoirs et interrogations avec le champ `category` de `devoirs`.
3. Ajouter la page `frais_parent`.
4. Utiliser uniquement `get_parent_fee_summary(p_sid)`.
5. Gérer plusieurs enfants sans mélanger les données.
6. Afficher statut, montants par devise, prochaine échéance, obligations et reçus.
7. Le Parent ne peut modifier, confirmer ou annuler aucun paiement.

## Mission Claude — Lot B : Caisse

Branche recommandée : `feature/payment-scanner-ui`

1. Ajouter « Contrôle des frais » dans le profil Caisse.
2. Réutiliser le QR actuel de l’élève ou permettre la saisie du matricule.
3. Utiliser `get_cashier_student_fee_detail(p_sid)`.
4. Utiliser `record_payment_transaction(...)`.
5. Afficher le numéro de reçu renvoyé par le serveur.
6. Connecter le reçu PDF ou image à `r2-files` avec :
   - `owner_type=student`
   - `owner_id=<sid>`
   - `category=receipt`
   - `payment_transaction_id=<transaction_id>`
7. Ne jamais considérer une opération locale comme validée avant réponse serveur.

## Mission Claude — Lot C : Gardien

1. Utiliser `check_gate_access_status(p_sid, source)`.
2. Afficher seulement photo, identité, classe, statut et instruction.
3. Ne jamais afficher montant, solde, reçu ou motif financier détaillé.
4. Ne jamais appeler directement `r2-files` depuis le profil Gardien.

## Mission Claude — Lot D : Intégration R2

Branche recommandée : `feature/r2-file-ui`

1. Créer un client frontend centralisé pour `r2-files`.
2. Envoyer les fichiers avec le JWT de la session utilisateur.
3. Utiliser une `x-idempotency-key` stable pour chaque tentative.
4. Connecter les photos des élèves.
5. Connecter les photos du personnel.
6. Connecter les photos des personnes autorisées.
7. Connecter les documents administratifs.
8. Connecter les fichiers de devoirs.
9. Connecter les reçus avec `payment_transaction_id` obligatoire.
10. Utiliser `download` pour obtenir une URL signée temporaire.
11. Ne jamais conserver une URL signée comme chemin permanent.
12. Utiliser `list` pour afficher les fichiers autorisés.
13. Gérer progression, erreurs réseau, reprise et réponse `reused=true`.
14. Empêcher les doubles clics.
15. Ajouter une invalidation visuelle lors du remplacement d’une photo.
16. Ne pas utiliser Supabase Storage sans validation écrite de ChatGPT.

## Restrictions obligatoires

- Ne modifier aucune table, migration, politique RLS, fonction SQL ou Edge Function.
- Ne pas utiliser `service_role` ou une clé secrète R2.
- Ne pas calculer le solde comme source de vérité côté navigateur.
- Ne pas ajouter le module financier à Direction 2 ou Enseignant.
- Ne pas fusionner directement dans `main`.
- Ouvrir une Pull Request en brouillon pour chaque lot.

## Contrats à lire

- `coordination/TASKS.md`
- `docs/PAYMENT_CONTROL_API.md`
- `docs/PAYMENT_CONTROL_RLS.md`
- `docs/R2_STORAGE_API.md`

## Tests attendus de Claude

- Parent avec un enfant.
- Parent avec plusieurs enfants.
- Parent tentant d’accéder à un autre élève.
- Direction 2 : absence totale des montants et menus financiers.
- Caisse : paiement total, partiel et reçu R2.
- Gardien : réponse minimale sans accès R2 direct.
- Enseignant : fichier de devoir seulement pour sa classe.
- Upload relancé après coupure avec la même clé d’idempotence.
- Affichage mobile Android.

## Points restant à ChatGPT

- Tester un cycle R2 réel avec un compte Direction 1.
- Tester les six rôles en conditions réelles.
- Ajouter la compression d’image serveur.
- Définir l’archivage annuel automatique.
- Ajouter la réconciliation des objets et métadonnées orphelins.
- Préparer la sauvegarde Backblaze B2.
- Durcir les anciennes RPC scanner/QR signalées par les conseillers Supabase.
- Activer la protection contre les mots de passe compromis.
- Revoir la Pull Request de Claude avant fusion.
