# SchoolSafe — Contrat Cloudflare R2

Date : 2026-08-03

## Fonctions actives

| Fonction | Version | Usage frontend |
|---|---:|---|
| `r2-upload` | 1 | Tous les nouveaux envois de photos, images et PDF |
| `r2-files` | 5 | `list`, `download`, `delete` et contrôle interne du stockage actif |
| `r2-archives` | 1 | Archives de Direction 1 uniquement |

Toutes les fonctions exigent la session JWT de l’utilisateur connecté.

Ne jamais envoyer au navigateur :

- `R2_ACCESS_KEY_ID` ;
- `R2_SECRET_ACCESS_KEY` ;
- clé Supabase secrète ou service role.

## Envoi de fichiers

Le frontend doit appeler `r2-upload`, et non envoyer directement un nouveau fichier à `r2-files`.

Requête `multipart/form-data` :

- `file=<File>` ;
- `owner_type=student|user|authorized_person|class|school|devoir|cahier_prep|administrative_document` ;
- `owner_id=<identifiant réel existant>` ;
- `category=<catégorie autorisée>` ;
- `academic_year=<facultatif>` ;
- `display_name=<nom lisible>` ;
- `payment_transaction_id=<transaction>` uniquement pour un reçu ;
- en-tête `x-idempotency-key=<clé stable 8 à 128 caractères>`.

Limites d’entrée :

- JPEG, PNG, WebP ou PDF ;
- source : 8 Mo maximum ;
- image : 12 000 pixels maximum par côté et 40 mégapixels maximum ;
- fichier final R2 : 5 Mo maximum.

Les images sont automatiquement contrôlées, orientées, redimensionnées et converties en WebP lorsqu’une économie utile est obtenue. Les PDF restent inchangés. Le contrat détaillé se trouve dans `docs/R2_IMAGE_OPTIMIZATION_API.md`.

## Année scolaire

L’année n’est jamais décidée par le navigateur. Le serveur utilise :

- `settings.year` pour les fichiers courants ;
- `payment_transactions.school_year` pour un reçu ;
- `administrative_documents.school_year` pour un dossier administratif.

Lorsque le frontend envoie `academic_year`, le serveur répond `409` si elle ne correspond pas à la source officielle.

## Propriétaires et catégories

| Propriétaire | Catégories autorisées |
|---|---|
| `student` | `document`, `photo`, `identity`, `card`, `receipt`, `homework`, `report` |
| `user` | `document`, `photo`, `identity` |
| `authorized_person` | `document`, `photo`, `identity` |
| `class` | `document`, `homework`, `report` |
| `school` | `document`, `report`, `archive` |
| `devoir` | `document`, `homework` |
| `cahier_prep` | `teacher_preparation` |
| `administrative_document` | `administrative_document` |

`r2-files` et PostgreSQL vérifient tous deux que le propriétaire existe et que la combinaison propriétaire/catégorie est autorisée.

## Reçu de paiement

```text
owner_type=student
owner_id=<student_id>
category=receipt
payment_transaction_id=<payment_transactions.id>
```

La transaction doit exister, appartenir au même élève et avoir le statut `confirmed`. Seuls Direction 1 et la Caisse peuvent envoyer un reçu. L’Enseignant ne peut jamais le lire ou l’envoyer. Le Parent ne lit que les reçus confirmés de ses propres enfants.

## Cahier de préparation

```text
owner_type=cahier_prep
owner_id=<cahier_prep.id>
category=teacher_preparation
display_name=<Page 1, Schéma, Annexe...>
```

Accès : Direction 1, Direction 2 et enseignant propriétaire.

## Document administratif

Créer d’abord la fiche dans `administrative_documents`, puis envoyer une ou plusieurs pièces :

```text
owner_type=administrative_document
owner_id=<administrative_documents.id>
category=administrative_document
display_name=<nom de la pièce>
```

## Validation du contenu

Le serveur vérifie la signature binaire réelle des fichiers JPEG, PNG, WebP et PDF. Un contenu qui ne correspond pas au type déclaré reçoit `415`.

## Liste

Appeler `r2-files` :

```json
{
  "action": "list",
  "owner_type": "administrative_document",
  "owner_id": "adm_...",
  "category": "administrative_document",
  "limit": 50
}
```

Maximum : 100 fichiers. Chaque ligne est filtrée selon le rôle.

## Ouverture

Appeler `r2-files` :

```json
{
  "action": "download",
  "file_id": "uuid"
}
```

La réponse contient une URL signée valable 300 secondes. Elle ne doit jamais être conservée comme chemin permanent.

## Suppression

Direction 1 uniquement, via `r2-files` :

```json
{
  "action": "delete",
  "file_id": "uuid"
}
```

L’objet est retiré de R2 et la métadonnée conserve `deleted_at` et `deleted_by` pour l’audit.

## Archives

Les archives passent uniquement par `r2-archives`. Direction 1 peut les lister, les ouvrir et les restaurer. Les objets ne sont pas copiés ni déplacés dans R2 lors de l’archivage.

## Matrice résumée

| Rôle | Lecture | Envoi |
|---|---|---|
| Direction 1 | Tous les fichiers actifs autorisés et archives | Tous avec contrôles spécialisés |
| Direction 2 | Pédagogique et administratif non financier | Hors finances |
| Caisse | Reçus et dossiers financiers | Finances autorisées |
| Enseignant | Liste pédagogique stricte de ses classes et préparations | Éléments pédagogiques autorisés |
| Parent | Liste blanche de ses enfants | Aucun actuellement |
| Gardien | Aucun accès direct R2 | Aucun |

## Endpoints interdits au frontend

Ne jamais appeler :

- `r2-upload-test` ;
- `r2-compression-self-test` ;
- `r2-self-test`.

Ils sont retirés ou réservés aux diagnostics internes.
