# SchoolSafe — Registre des documents administratifs

Backend appliqué le 3 août 2026.

## Objectif

Enregistrer, classer et conserver les documents de l’école photographiés ou reçus en PDF. Un dossier administratif contient une fiche descriptive dans Supabase et une ou plusieurs pièces dans Cloudflare R2.

Exemples :

- facture ou reçu d’eau ;
- facture ou reçu d’électricité ;
- assurance de l’école ;
- loyer ;
- taxes et impôts ;
- CNSS ;
- facture fournisseur ;
- reçu d’achat ;
- document bancaire ;
- entretien et réparation ;
- contrat ou convention ;
- agrément ou licence ;
- document administratif du personnel ;
- inventaire ;
- correspondance officielle ;
- procès-verbal ;
- autre document financier ou administratif.

## Tables

### `administrative_document_types`

Catalogue des types. Champs principaux :

- `id`
- `code`
- `label`
- `group_code`
- `is_financial`
- `active`
- `sort_order`

18 types standards sont déjà actifs. Direction 1 peut ajouter ultérieurement d’autres types sans modifier R2.

### `administrative_documents`

Fiche d’enregistrement d’un dossier :

- `id`
- `document_type_id`
- `title`
- `document_number`
- `document_date`
- `period_start`
- `period_end`
- `provider`
- `amount`
- `currency`
- `notes`
- `school_year`
- `confidentiality`
- `is_financial`
- `status`
- `created_by`
- `created_at`
- `updated_at`
- `archived_at`

Le serveur détermine automatiquement `is_financial` à partir du type. Le navigateur ne doit pas décider lui-même qu’une facture est non financière.

## Création de la fiche

RPC : `create_administrative_document(...)`

Paramètres :

```text
p_document_type_id
p_title
p_document_number
p_document_date
p_period_start
p_period_end
p_provider
p_amount
p_currency
p_notes
p_school_year
p_confidentiality
```

Exemple logique :

```json
{
  "p_document_type_id": "<type water_bill>",
  "p_title": "Facture REGIDESO — août 2026",
  "p_document_number": "REG-2026-08-001",
  "p_document_date": "2026-08-03",
  "p_period_start": "2026-08-01",
  "p_period_end": "2026-08-31",
  "p_provider": "REGIDESO",
  "p_amount": 150000,
  "p_currency": "CDF",
  "p_notes": "Facture du site scolaire",
  "p_school_year": "2026-2027",
  "p_confidentiality": "financial"
}
```

La réponse contient notamment `administrative_documents.id`. Cet identifiant est obligatoire pour envoyer les fichiers.

## Envoi des photos ou PDF dans R2

Edge Function : `r2-files`

Requête `multipart/form-data` :

```text
action=upload
owner_type=administrative_document
owner_id=<administrative_documents.id>
category=administrative_document
academic_year=2026-2027
display_name=<nom lisible de la pièce>
file=<image ou PDF>
```

En-tête obligatoire recommandé :

```text
x-idempotency-key=<clé stable de 8 à 128 caractères>
```

Plusieurs pièces peuvent utiliser le même `owner_id` :

- page 1 ;
- page 2 ;
- recto ;
- verso ;
- preuve de paiement ;
- annexe.

Chaque pièce doit avoir une clé d’idempotence différente.

## Liste des pièces

```json
{
  "action": "list",
  "owner_type": "administrative_document",
  "owner_id": "adm_...",
  "category": "administrative_document",
  "limit": 50
}
```

## Consultation d’une pièce

```json
{
  "action": "download",
  "file_id": "uuid"
}
```

La réponse fournit une URL signée temporaire valable 300 secondes. Ne jamais enregistrer cette URL comme adresse permanente.

## Archivage d’un dossier

RPC :

```text
archive_administrative_document(p_document_id)
```

Direction 1 uniquement.

## Matrice d’accès

| Profil | Documents financiers | Documents administratifs non financiers |
|---|---:|---:|
| Direction 1 | Oui | Oui |
| Direction 2 | Non | Oui, sauf document restreint |
| Caisse / Direction 3 | Oui | Non |
| Enseignant | Non | Non |
| Parent | Non | Non |
| Gardien | Non | Non |

## Règles frontend obligatoires

- Créer la fiche avant d’envoyer les pièces.
- Demander un nom clair pour chaque document et chaque pièce.
- Ne jamais enregistrer un PDF ou une photo en base64 dans Supabase.
- Ne jamais exposer une clé R2 ou une clé Supabase secrète.
- Ne jamais montrer les montants et factures à Direction 2.
- Ne pas supprimer directement une ligne ou un objet R2 depuis le navigateur.
- Conserver le dossier même s’il contient plusieurs fichiers.
