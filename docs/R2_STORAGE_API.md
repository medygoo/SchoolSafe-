# SchoolSafe — Contrat Cloudflare R2

Version serveur active : `r2-files` v3

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
- `owner_type=student|user|authorized_person|class|school|devoir`
- `owner_id=<identifiant>`
- `category=document|photo|identity|card|receipt|homework|report|archive`
- `academic_year=2026-2027`
- `payment_transaction_id=<transaction>` uniquement pour un reçu
- en-tête `x-idempotency-key=<clé stable 8 à 128 caractères>`

### Reçu de paiement

Un reçu doit toujours utiliser :

```text
owner_type=student
owner_id=<student_id>
category=receipt
payment_transaction_id=<payment_transactions.id>
```

Le serveur refuse le reçu lorsque :

- la transaction n’existe pas ;
- la transaction appartient à un autre élève ;
- la transaction est annulée ;
- le rôle n’est ni Direction 1 ni Caisse.

## Download

Corps JSON :

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
  "owner_type": "student",
  "owner_id": "student-id",
  "category": "receipt",
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
| Direction 1 | Tous les fichiers autorisés | Tous, avec transaction obligatoire pour reçu |
| Direction 2 | Hors finances | Hors finances |
| Caisse | Reçus d’élèves | Reçus liés aux transactions confirmées |
| Enseignant | Classes, élèves et devoirs affectés, hors finances | Classes, élèves et devoirs affectés |
| Parent | Fichiers de ses propres enfants | Aucun upload administratif actuellement |
| Gardien | Aucun accès direct R2 | Aucun |

## Formats actuels

- `image/jpeg`
- `image/png`
- `image/webp`
- `application/pdf`
- maximum 5 Mo

La compression automatique d’image n’est pas encore active dans la version 3. Le frontend doit donc réduire raisonnablement les photos avant envoi jusqu’au déploiement de la transformation serveur.
