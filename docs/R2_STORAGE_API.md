# SchoolSafe — Contrat Cloudflare R2

Version serveur active : `r2-files` v4

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
- `owner_id=<identifiant>`
- `category=document|photo|identity|card|receipt|homework|report|archive|teacher_preparation|administrative_document`
- `academic_year=2026-2027`
- `display_name=<nom lisible du fichier>`
- `payment_transaction_id=<transaction>` uniquement pour un reçu
- en-tête `x-idempotency-key=<clé stable 8 à 128 caractères>`

## Reçu de paiement

Un reçu utilise obligatoirement :

```text
owner_type=student
owner_id=<student_id>
category=receipt
payment_transaction_id=<payment_transactions.id>
```

Le serveur refuse le reçu lorsque la transaction n’existe pas, appartient à un autre élève, est annulée ou lorsque le rôle n’est ni Direction 1 ni Caisse.

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

Maximum serveur : 100 fichiers.

## Archive

Direction 1 uniquement :

```json
{
  "action": "archive",
  "file_id": "uuid"
}
```

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
| Direction 1 | Tous les fichiers autorisés | Tous, avec contrôles spécialisés |
| Direction 2 | Pédagogique et administratif non financier | Hors finances |
| Caisse | Reçus et dossiers financiers | Reçus et dossiers financiers autorisés |
| Enseignant | Ses classes, élèves, devoirs et préparations | Ses éléments pédagogiques uniquement |
| Parent | Fichiers autorisés de ses propres enfants | Aucun upload administratif actuellement |
| Gardien | Aucun accès direct R2 | Aucun |

## Formats actuels

- `image/jpeg`
- `image/png`
- `image/webp`
- `application/pdf`
- maximum 5 Mo

La compression automatique d’image n’est pas encore active dans la version 4. Le frontend doit réduire raisonnablement les photos avant l’envoi jusqu’au déploiement de la transformation serveur.
