# SchoolSafe — Contrat Cloudflare R2

Version serveur active : `r2-files` v5

## Endpoint

La fonction Supabase Edge Function `r2-files` doit être appelée avec la session JWT de l’utilisateur connecté.

Ne jamais envoyer au navigateur :

- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
- clé Supabase secrète/service role

## Upload

Requête `multipart/form-data` :

- `action=upload`
- `file=<File>`
- `owner_type=student|user|authorized_person|class|school|devoir|cahier_prep|administrative_document`
- `owner_id=<identifiant réel existant>`
- `category=<catégorie autorisée pour ce propriétaire>`
- `academic_year=<facultatif>`
- `display_name=<nom lisible du fichier>`
- `payment_transaction_id=<transaction>` uniquement pour un reçu
- en-tête `x-idempotency-key=<clé stable 8 à 128 caractères>`

L’année scolaire n’est plus choisie par le navigateur. Le serveur utilise :

- `settings.year` pour les fichiers courants ;
- `payment_transactions.school_year` pour un reçu ;
- `administrative_documents.school_year` pour un dossier administratif.

Lorsque le frontend envoie `academic_year`, le serveur le compare à cette source de vérité et répond `409` en cas de différence. Claude doit donc éviter de coder une année en dur.

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

Le serveur et un déclencheur PostgreSQL vérifient tous deux que le propriétaire existe et que la combinaison propriétaire/catégorie est valide.

## Reçu de paiement

Un reçu utilise obligatoirement :

```text
owner_type=student
owner_id=<student_id>
category=receipt
payment_transaction_id=<payment_transactions.id>
```

La transaction doit :

- exister ;
- appartenir au même élève ;
- avoir le statut `confirmed` ;
- fournir l’année scolaire du fichier.

Seuls Direction 1 et la Caisse peuvent envoyer un reçu. L’enseignant ne peut jamais lire ou envoyer un reçu. Le Parent ne peut lire que le reçu confirmé de son propre enfant.

## Accès Parent

Le Parent ne reçoit pas un accès général aux fichiers de l’enfant. La liste blanche actuelle est :

- photo de l’élève ;
- carte de l’élève ;
- reçu confirmé ;
- fichier de devoir ;
- rapport autorisé ;
- photo d’une personne autorisée liée à son enfant.

Les catégories `identity`, les documents administratifs, les préparations et les fichiers internes ne sont pas accessibles au Parent.

## Accès Enseignant

L’Enseignant est limité à ses classes et à ses propres préparations.

Pour un élève de sa classe, il peut lire :

- `photo` ;
- `document` pédagogique ;
- `homework` ;
- `report`.

Il peut envoyer uniquement les éléments pédagogiques autorisés. Les catégories `receipt`, `card`, les documents administratifs et les personnes autorisées lui sont interdites.

## Cahier de préparation

```text
owner_type=cahier_prep
owner_id=<cahier_prep.id>
category=teacher_preparation
display_name=<Page 1, Schéma, Annexe...>
```

Accès : Direction 1, Direction 2 et enseignant propriétaire.

## Document administratif

Créer d’abord une fiche dans `administrative_documents`, puis envoyer :

```text
owner_type=administrative_document
owner_id=<administrative_documents.id>
category=administrative_document
display_name=<nom de la pièce>
```

Plusieurs photos ou PDF peuvent appartenir au même dossier administratif.

## Validation du contenu

Le serveur ne se fie plus uniquement au type MIME fourni par le navigateur. Il vérifie la signature binaire réelle des formats suivants :

- JPEG ;
- PNG ;
- WebP ;
- PDF.

Un fichier dont le contenu ne correspond pas au type annoncé reçoit une réponse `415`.

## Download

```json
{
  "action": "download",
  "file_id": "uuid"
}
```

La réponse contient une URL signée valable 300 secondes. L’application ne doit pas conserver cette URL comme chemin permanent.

## List

```json
{
  "action": "list",
  "owner_type": "administrative_document",
  "owner_id": "adm_...",
  "category": "administrative_document",
  "limit": 50
}
```

Maximum serveur : 100 fichiers. Chaque ligne est filtrée selon le rôle avant d’être renvoyée.

## Archive

Direction 1 uniquement :

```json
{
  "action": "archive",
  "file_id": "uuid"
}
```

La consultation et la restauration spéciales des archives seront finalisées dans une étape séparée.

## Delete

Direction 1 uniquement :

```json
{
  "action": "delete",
  "file_id": "uuid"
}
```

L’objet est supprimé de R2 et la métadonnée est conservée avec `deleted_at` et `deleted_by` pour l’audit.

## Matrice résumée

| Rôle | Lecture | Upload |
|---|---|---|
| Direction 1 | Tous les fichiers actifs autorisés | Tous, avec contrôles spécialisés |
| Direction 2 | Pédagogique et administratif non financier | Hors finances |
| Caisse | Reçus et dossiers financiers | Reçus et dossiers financiers autorisés |
| Enseignant | Liste pédagogique stricte de ses classes et ses préparations | Éléments pédagogiques autorisés uniquement |
| Parent | Liste blanche de ses propres enfants | Aucun upload actuellement |
| Gardien | Aucun accès direct R2 | Aucun |

## Formats actuels

- `image/jpeg`
- `image/png`
- `image/webp`
- `application/pdf`
- maximum 5 Mo

La compression automatique d’image n’est pas encore active dans la version 5. Le frontend doit réduire raisonnablement les photos avant l’envoi jusqu’au déploiement de la transformation serveur.
