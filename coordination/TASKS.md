# SchoolSafe — Répartition permanente des tâches

Dernière mise à jour : 2026-08-03

Ce fichier est la référence permanente pour la répartition du travail entre ChatGPT et Claude. Il doit être consulté avant toute nouvelle modification.

## Règle générale

- ChatGPT : Supabase, base de données, migrations, RLS, sécurité, RPC, Cloudflare R2 côté serveur, compression, archives, contrats techniques, audit et validation.
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

## Travail Claude — Cloudflare R2 et compression

- [ ] Créer un client frontend centralisé pour les fonctions R2.
- [ ] Utiliser **`r2-upload` pour tous les nouveaux envois** de photos, images et PDF.
- [ ] Utiliser `r2-files` uniquement pour `list`, `download` et `delete`.
- [ ] Utiliser `r2-archives` uniquement dans l’écran Archives de Direction 1.
- [ ] Envoyer les fichiers avec la session JWT, jamais avec une clé R2.
- [ ] Envoyer une `x-idempotency-key` stable de 8 à 128 caractères pour chaque tentative logique.
- [ ] Réutiliser la même clé après une coupure réseau ou lorsque `retry_same_idempotency_key=true`.
- [ ] Ne jamais appeler `r2-upload-test`, `r2-compression-self-test` ou `r2-self-test`.
- [ ] Ne jamais coder une année scolaire en dur.
- [ ] Omettre `academic_year` ou utiliser la valeur fournie par le serveur.
- [ ] En cas de réponse `409` sur l’année, afficher `current_academic_year` et recharger les paramètres.
- [ ] Accepter côté sélection JPEG, PNG, WebP et PDF, avec source de 8 Mo maximum.
- [ ] Afficher une erreur claire pour `413` : fichier trop lourd, dimensions trop grandes ou résultat final supérieur à 5 Mo.
- [ ] Afficher une erreur claire pour `415` : contenu corrompu ou type déclaré incorrect.
- [ ] Gérer `401`, `403`, `409`, `413`, `415` et `500` sans perdre la clé d’idempotence.
- [ ] Lorsque `upload_committed=true`, ne pas envoyer une deuxième copie ; reprendre avec la même clé.
- [ ] Afficher après réussite la taille source, la taille finale et le pourcentage économisé lorsque disponibles.
- [ ] Connecter les photos des élèves à `r2-upload`.
- [ ] Connecter les photos du personnel à `r2-upload`.
- [ ] Connecter les photos des personnes autorisées à `r2-upload`.
- [ ] Connecter les fichiers de devoirs à `r2-upload`.
- [ ] Connecter les reçus de paiement à `r2-upload` avec `payment_transaction_id` obligatoire.
- [ ] Pour un reçu, envoyer `owner_type=student`, `owner_id=<sid>`, `category=receipt` et `payment_transaction_id=<transaction_id>`.
- [ ] Ouvrir les fichiers via `r2-files` action `download`, avec URL signée temporaire.
- [ ] Ne jamais conserver durablement une URL signée.
- [ ] Lister les fichiers via `r2-files` action `list`.
- [ ] Afficher la progression d’envoi et empêcher les doubles clics.
- [ ] Gérer la réponse `reused=true` comme une réussite existante.
- [ ] Ajouter une invalidation visuelle lors du remplacement d’une photo.
- [ ] Ne pas utiliser le bucket Supabase Storage `school-files` sans validation écrite de ChatGPT.
- [ ] Ne pas donner au Gardien un accès direct aux fonctions R2.

## Travail Claude — Cahier de préparation des enseignants

- [ ] Dans le profil Enseignant, ajouter « Pièces jointes de la préparation » dans chaque fiche `cahier_prep`.
- [ ] Permettre plusieurs photos ou PDF pour une même préparation.
- [ ] Demander un nom lisible : « Page 1 », « Schéma du cours », « Fiche d’exercices », etc.
- [ ] Envoyer par `r2-upload` avec `owner_type=cahier_prep`, `owner_id=<cahier_prep.id>` et `category=teacher_preparation`.
- [ ] Envoyer `display_name` et une clé d’idempotence.
- [ ] Afficher la liste des pièces sous la préparation.
- [ ] Ouvrir via `r2-files` action `download`.
- [ ] Limiter l’enseignant à ses propres préparations.
- [ ] Permettre à Direction 1 et Direction 2 de consulter les préparations et leurs pièces.
- [ ] Interdire cet accès à la Caisse, au Gardien et au Parent.
- [ ] Afficher type, nom, date, taille et économie de stockage lorsque disponibles.
- [ ] Gérer plusieurs pages dans le bon ordre visuel.
- [ ] Ne pas enregistrer d’image en base64 dans `cahier_prep`.

## Travail Claude — Registre des documents administratifs

- [ ] Ajouter « Documents administratifs » dans Direction 1.
- [ ] Ajouter la rubrique financière correspondante dans la Caisse.
- [ ] Ajouter dans Direction 2 une vue non financière, sans facture, montant, reçu, assurance payée, taxe ou donnée monétaire.
- [ ] Créer le formulaire avant l’envoi du fichier.
- [ ] Champs : type, nom, référence, date, période, fournisseur, montant, devise, année scolaire et notes.
- [ ] Utiliser les types fournis par `administrative_document_types`.
- [ ] Permettre « Autre document administratif » et « Autre document financier ».
- [ ] Créer la fiche avec `create_administrative_document(...)`.
- [ ] Envoyer les pièces par `r2-upload` avec `owner_type=administrative_document`, `owner_id=<id>` et `category=administrative_document`.
- [ ] Envoyer `display_name` et une clé d’idempotence.
- [ ] Permettre plusieurs fichiers par dossier : recto, verso et plusieurs pages.
- [ ] Classer et filtrer par type, année, date, fournisseur, statut et caractère financier.
- [ ] Prévoir eau, électricité, assurance, loyer, taxes, CNSS, fournisseur, achat, banque, entretien, contrat, agrément, personnel, inventaire, correspondance et procès-verbal.
- [ ] Afficher un état vide lorsqu’aucun document réel n’existe.
- [ ] Utiliser `archive_administrative_document(p_document_id)` pour archiver tout le dossier et ses pièces.
- [ ] Utiliser `restore_administrative_document(p_document_id)` pour restaurer tout le dossier.
- [ ] Ne jamais supprimer directement une ligne ou un objet R2 depuis le navigateur.
- [ ] Direction 2 ne reçoit jamais `is_financial=true`.
- [ ] La Caisse ne reçoit que les documents financiers.
- [ ] Enseignant, Parent et Gardien n’accèdent pas au registre.
- [ ] Ajouter recherche, filtres, tri et affichage mobile Android.

## Travail Claude — Archives Direction 1

- [ ] Créer une rubrique « Archives » visible uniquement par Direction 1.
- [ ] Appeler `r2-archives` avec la session JWT.
- [ ] Afficher le résumé par année : nombre de fichiers et taille totale.
- [ ] Ajouter filtres par année, propriétaire et catégorie.
- [ ] Ajouter pagination et état vide.
- [ ] Ouvrir les archives avec une URL temporaire de 300 secondes.
- [ ] Afficher date et auteur de l’archivage.
- [ ] Demander confirmation avant une restauration.
- [ ] Pour un dossier administratif, restaurer le dossier complet par RPC et non une page isolée.
- [ ] Ne jamais afficher cette rubrique à Direction 2, Caisse, Enseignant, Parent ou Gardien.

## Travail ChatGPT — terminé

- [x] Audit profond de Supabase, R2, rôles, données existantes et GitHub.
- [x] Preuve réelle R2 : PUT, GET, contenu, liste et suppression.
- [x] Liaison reçu–transaction et idempotence.
- [x] Suppression auditée `deleted_at` / `deleted_by`.
- [x] Séparation stricte Direction 1 / Direction 2 / Caisse / Enseignant / Parent / Gardien.
- [x] Liste blanche Parent et interdiction des finances pour l’Enseignant.
- [x] Validation de l’existence du propriétaire et du couple propriétaire/catégorie.
- [x] Année scolaire résolue côté serveur.
- [x] Contrôle binaire réel JPEG, PNG, WebP et PDF.
- [x] RLS des devoirs et du cahier de préparation.
- [x] Registre administratif et 18 types standards.
- [x] Plusieurs pièces R2 par préparation et par dossier administratif.
- [x] Archivage et restauration audités.
- [x] Archivage transactionnel d’un dossier administratif et de toutes ses pièces.
- [x] Service `r2-archives` Direction 1.
- [x] Déploiement de `r2-files` version 5.
- [x] Déploiement de `r2-upload` version 1 avec JWT obligatoire.
- [x] Compression automatique JPEG/PNG/WebP avant R2.
- [x] PDF transmis sans conversion.
- [x] Profils de compression photo, identité, carte et document.
- [x] Limites 8 Mo source, 5 Mo final, 12 000 px et 40 mégapixels.
- [x] Enregistrement des tailles, dimensions, profil, qualité et économie.
- [x] Test réel PNG → WebP → R2 → relecture → suppression réussi.
- [x] Réduction de test mesurée à 79,58 % sur une image synthétique.
- [x] Endpoints expérimentaux de compression remplacés par des réponses `410` protégées par JWT.
- [x] Code de production et migration de compression enregistrés dans GitHub.
- [x] Aucun faux fichier, aucune fausse donnée et aucun objet de test conservé.

## Travail ChatGPT — restant

- [ ] Effectuer le cycle complet authentifié de production avec une vraie session Direction 1 : `r2-upload` → `list` → `download` → `delete`.
- [ ] Effectuer les tests réels Direction 2, Caisse, Enseignant, Parent et Gardien.
- [ ] Après intégration Claude, interdire techniquement les uploads directs d’images vers l’action `upload` de `r2-files`.
- [ ] Définir la clôture et l’archivage annuel automatique.
- [ ] Créer l’inventaire annuel exportable.
- [ ] Créer la réconciliation des objets R2 orphelins et métadonnées orphelines.
- [ ] Préparer la sauvegarde secondaire Backblaze B2.
- [ ] Corriger les alertes historiques `SECURITY DEFINER` du scanner sans casser l’application.
- [ ] Activer la protection Supabase contre les mots de passe compromis.
- [ ] Auditer et valider les Pull Requests frontend de Claude avant fusion.

## Fonctions et actions disponibles

### `r2-upload` version 1

- envoi obligatoire des nouveaux fichiers ;
- compression d’images ;
- transmission des PDF ;
- métriques de stockage ;
- reprise avec idempotence.

### `r2-files` version 5

- `health` : Direction 1 ;
- `list` : fichiers actifs autorisés ;
- `download` : URL signée 300 secondes ;
- `delete` : Direction 1, suppression R2 puis audit.

### `r2-archives` version 1

- résumé ;
- liste paginée ;
- téléchargement temporaire ;
- archivage ;
- restauration ;
- Direction 1 uniquement.

## Décision de stockage

- Supabase : données structurées, Auth, rôles, permissions, registres, relations, métriques et chemins.
- Cloudflare R2 : photos, reçus, cahiers, devoirs, documents administratifs et archives.
- Backblaze B2 : future seconde copie de sécurité.
