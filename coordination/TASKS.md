# SchoolSafe — Répartition permanente des tâches

Dernière mise à jour : 2026-08-03

Ce fichier est la référence permanente pour la répartition du travail entre ChatGPT et Claude. Il doit être consulté avant toute nouvelle modification.

## Règle générale

- ChatGPT : Supabase, base de données, migrations, RLS, sécurité, RPC, Cloudflare R2 côté serveur, contrats techniques, audit et validation.
- Claude : application, interface, UX, écrans, navigation, appels frontend, PWA, affichage des erreurs, intégration visible et tests fonctionnels de l’interface.
- Claude ne modifie pas les tables, migrations, RLS, RPC, Edge Functions ou secrets sans validation de ChatGPT.
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

## Travail Claude — Cloudflare R2 général

- [ ] Créer un client frontend centralisé pour appeler la fonction Supabase `r2-files`.
- [ ] Envoyer les fichiers avec session utilisateur JWT, jamais avec une clé R2.
- [ ] Utiliser une `x-idempotency-key` stable pour chaque tentative d’envoi.
- [ ] Connecter les photos des élèves à R2.
- [ ] Connecter les photos du personnel à R2.
- [ ] Connecter les photos des personnes autorisées à R2.
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

## Travail Claude — Cahier de préparation des enseignants

- [ ] Dans le profil Enseignant, ajouter une zone « Pièces jointes de la préparation » dans chaque fiche `cahier_prep`.
- [ ] Permettre plusieurs photos ou PDF pour une même préparation.
- [ ] Demander un nom lisible pour chaque fichier, par exemple « Page 1 », « Schéma du cours » ou « Fiche d’exercices ».
- [ ] Envoyer avec `owner_type=cahier_prep`, `owner_id=<cahier_prep.id>` et `category=teacher_preparation`.
- [ ] Envoyer `display_name` et une clé d’idempotence.
- [ ] Afficher la liste des pièces jointes sous la préparation.
- [ ] Ouvrir les fichiers avec l’action `download` et une URL signée temporaire.
- [ ] Permettre à l’enseignant de voir seulement les fichiers de ses propres préparations.
- [ ] Permettre à Direction 1 et Direction 2 de consulter les préparations et leurs pièces jointes.
- [ ] Ne pas donner cet accès à la Caisse, au Gardien ou au Parent.
- [ ] Afficher clairement le type de fichier, le nom, la date et la taille.
- [ ] Gérer l’ajout de plusieurs pages photographiées dans le bon ordre visuel.
- [ ] Ne pas enregistrer les images en base64 dans `cahier_prep`.

## Travail Claude — Registre des documents administratifs

- [ ] Ajouter une rubrique « Documents administratifs » dans Direction 1.
- [ ] Ajouter une rubrique financière correspondante dans la Caisse pour les documents financiers autorisés.
- [ ] Ajouter une vue non financière dans Direction 2, sans facture, montant, reçu, assurance payée, taxe ou autre information monétaire.
- [ ] Créer un formulaire d’enregistrement avant l’envoi du fichier.
- [ ] Champs du formulaire : type, nom du document, numéro ou référence, date, période, fournisseur ou organisme, montant, devise, année scolaire et notes.
- [ ] Utiliser les types fournis par `administrative_document_types`.
- [ ] Permettre le type « Autre document administratif » et « Autre document financier ».
- [ ] Créer la fiche avec `create_administrative_document(...)`.
- [ ] Après création, envoyer une ou plusieurs photos/PDF avec `owner_type=administrative_document`, `owner_id=<administrative_documents.id>` et `category=administrative_document`.
- [ ] Envoyer le nom lisible du fichier dans `display_name`.
- [ ] Permettre plusieurs fichiers pour un même dossier, par exemple recto, verso et plusieurs pages.
- [ ] Classer et filtrer par type, année scolaire, date, fournisseur, statut et caractère financier.
- [ ] Prévoir les types : eau, électricité, assurance, loyer, taxes, CNSS, fournisseur, achat, banque, entretien, contrat, agrément, personnel, inventaire, correspondance et procès-verbal.
- [ ] Afficher l’état vide lorsqu’aucun document réel n’est encore enregistré.
- [ ] Utiliser `archive_administrative_document(p_document_id)` pour archiver un dossier.
- [ ] Ne jamais supprimer directement une ligne ou un objet R2 depuis le navigateur.
- [ ] Direction 2 ne doit jamais recevoir les lignes marquées `is_financial=true`.
- [ ] La Caisse ne doit recevoir que les documents financiers.
- [ ] L’Enseignant, le Parent et le Gardien ne doivent avoir aucun accès au registre administratif.
- [ ] Ajouter recherche, filtres, tri et affichage mobile Android.

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
- [x] Création de `administrative_document_types` et `administrative_documents`.
- [x] Création de 18 types administratifs standards.
- [x] Ajout du nom lisible `display_name` pour les fichiers.
- [x] Liaison des fichiers R2 à `cahier_prep`.
- [x] Liaison des fichiers R2 au registre administratif.
- [x] RLS du cahier : Direction 1, Direction 2 et enseignant propriétaire.
- [x] RLS administratif : Direction 1 complète, Direction 2 non financière, Caisse financière.
- [x] Création de `create_administrative_document(...)`.
- [x] Création de `archive_administrative_document(...)`.
- [x] Déploiement de `r2-files` version 4 avec JWT obligatoire.
- [x] Tests transactionnels du dossier administratif et du cahier, suivis d’un rollback complet.
- [x] Vérification qu’aucune fausse donnée n’est restée.

## Travail ChatGPT — restant

- [ ] Effectuer un cycle réel avec compte Direction 1 : health → upload → list → download → delete.
- [ ] Effectuer les tests réels Direction 2, Caisse, Enseignant, Parent et Gardien.
- [ ] Ajouter la compression d’image serveur avant généralisation des photos.
- [ ] Finaliser la consultation spéciale des archives par Direction 1.
- [ ] Définir l’archivage annuel automatique.
- [ ] Créer la réconciliation des objets R2 orphelins et des métadonnées orphelines.
- [ ] Préparer la sauvegarde secondaire Backblaze B2.
- [ ] Corriger les alertes historiques SECURITY DEFINER du scanner sans casser l’application.
- [ ] Activer la protection Supabase contre les mots de passe compromis.
- [ ] Valider le code frontend de Claude avant fusion.

## Actions disponibles dans `r2-files` version 4

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

- Supabase : données structurées, Auth, rôles, permissions, registres, relations et chemins des fichiers.
- Cloudflare R2 : photos, reçus, cahiers de préparation, documents administratifs, fichiers de devoirs et archives.
- Backblaze B2 : future seconde copie de sécurité.
