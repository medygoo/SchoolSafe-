# SchoolSafe — Répartition permanente des tâches

Dernière mise à jour : 2026-08-03

Ce fichier est la référence permanente pour la répartition du travail entre ChatGPT et Claude. Il doit être consulté avant toute nouvelle modification.

## Règle générale

- ChatGPT : Supabase, base de données, migrations, RLS, sécurité, RPC, Cloudflare R2 côté serveur, contrats techniques, audit et validation.
- Claude : application, interface, UX, écrans, navigation, appels frontend, PWA, affichage des erreurs, intégration visible et tests fonctionnels de l’interface.
- Claude ne modifie pas les tables, migrations, RLS, RPC ou secrets sans validation de ChatGPT.
- Aucun secret R2, Supabase secret/service role ou clé privée ne doit être ajouté dans le frontend ou dans GitHub public.

## Travail Claude — Paiements et scanner

- [ ] Séparer clairement les rubriques Parent « Devoirs » et « Interrogations ».
- [ ] Ajouter la rubrique « Frais scolaires » à côté de Devoirs et Interrogations.
- [ ] Créer la page Parent de suivi des frais par enfant.
- [ ] Afficher statut, montant exigible, montant payé, solde, échéances et reçus.
- [ ] Utiliser uniquement `get_parent_fee_summary(p_sid)` pour le résumé Parent.
- [ ] Créer l’écran Caisse de consultation détaillée via `get_cashier_student_fee_detail(p_sid)`.
- [ ] Créer l’enregistrement d’un paiement via `record_payment_transaction(...)`.
- [ ] Créer l’affichage du numéro de reçu retourné par le backend.
- [ ] Créer le scanner Caisse par QR ou matricule.
- [ ] Créer l’affichage minimal Gardien via `check_gate_access_status(...)`.
- [ ] Ne jamais afficher au Gardien les montants, soldes, échéances ou reçus.
- [ ] Masquer complètement les finances pour Direction 2 et Enseignant.
- [ ] Ne pas ajouter un deuxième QR financier : réutiliser le QR existant de l’élève.
- [ ] Gérer les états réseau : chargement, hors ligne, erreur, reprise et opération déjà envoyée.

## Travail Claude — Cloudflare R2

- [ ] Créer un client frontend centralisé pour appeler la fonction Supabase `r2-files`.
- [ ] Envoyer les fichiers avec session utilisateur JWT, jamais avec une clé R2.
- [ ] Utiliser une `x-idempotency-key` stable pour chaque tentative d’envoi.
- [ ] Connecter les photos des élèves à R2.
- [ ] Connecter les photos du personnel à R2.
- [ ] Connecter les photos des personnes autorisées à R2.
- [ ] Connecter les documents administratifs à R2.
- [ ] Connecter les fichiers de devoirs à R2.
- [ ] Connecter les reçus de paiement à R2 avec `payment_transaction_id` obligatoire.
- [ ] Pour un reçu, envoyer `owner_type=student`, `owner_id=<sid>`, `category=receipt` et `payment_transaction_id=<transaction_id>`.
- [ ] Afficher les fichiers via l’action `download`, qui retourne une URL signée temporaire.
- [ ] Ne jamais conserver durablement une URL signée de téléchargement.
- [ ] Utiliser l’action `list` pour lister les fichiers autorisés.
- [ ] Afficher la progression d’envoi et les erreurs compréhensibles.
- [ ] Empêcher les doubles clics et gérer la réponse `reused=true`.
- [ ] Ajouter une invalidation visuelle lors du remplacement d’une photo.
- [ ] Ne pas utiliser le bucket Supabase Storage `school-files` sans validation écrite de ChatGPT.
- [ ] Ne pas donner au Gardien un accès direct à `r2-files`; les images nécessaires doivent passer par le contrat scanner validé.

## Travail ChatGPT — terminé

- [x] Audit de la structure R2 existante.
- [x] Confirmation de la fonction Supabase `r2-files` active.
- [x] Ajout du lien `payment_transaction_id` entre reçu R2 et transaction.
- [x] Ajout de l’idempotence des téléversements.
- [x] Ajout de la suppression auditée `deleted_at` / `deleted_by`.
- [x] Ajout des index contre les doublons de reçus.
- [x] Autorisation Caisse limitée aux reçus liés à une transaction confirmée.
- [x] Interdiction des finances pour Direction 2.
- [x] Interdiction d’accès direct R2 pour le Gardien.
- [x] Déploiement de `r2-files` version 3 avec JWT obligatoire.
- [x] Ajout des actions upload, download, list, archive et delete.

## Travail ChatGPT — restant

- [ ] Effectuer un cycle réel avec compte Direction 1 : health → upload → list → download → delete.
- [ ] Effectuer les tests réels Direction 2, Caisse, Enseignant, Parent et Gardien.
- [ ] Ajouter la compression d’image serveur avant généralisation des photos.
- [ ] Définir l’archivage annuel automatique.
- [ ] Créer la réconciliation des objets R2 orphelins et des métadonnées orphelines.
- [ ] Préparer la sauvegarde secondaire Backblaze B2.
- [ ] Corriger les alertes historiques SECURITY DEFINER du scanner sans casser l’application.
- [ ] Valider le code frontend de Claude avant fusion.

## Actions disponibles dans `r2-files` version 3

- `health` : Direction 1 uniquement.
- `upload` : selon rôle, propriétaire et catégorie.
- `download` : retourne une URL signée valable 300 secondes.
- `list` : retourne au maximum 100 fichiers autorisés.
- `archive` : Direction 1 uniquement.
- `delete` : Direction 1 uniquement, suppression R2 puis audit en base.

## Formats actuellement acceptés

- JPEG
- PNG
- WebP
- PDF
- Taille maximale : 5 Mo

## Décision actuelle de stockage

- Supabase : données structurées, Auth, rôles, permissions, relations et chemins des fichiers.
- Cloudflare R2 : photos, reçus, documents, fichiers de devoirs et archives.
- Backblaze B2 : future seconde copie de sécurité.
