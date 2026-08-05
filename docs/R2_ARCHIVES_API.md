# SchoolSafe — Contrat des archives R2

Version serveur active : `r2-archives` v1.

## Accès

- Direction 1 uniquement.
- JWT de la session utilisateur obligatoire.
- Direction 2, Caisse, Enseignant, Parent et Gardien ne doivent pas afficher ni appeler cet écran.
- Les clés Cloudflare R2 et la clé Supabase secrète ne vont jamais dans le navigateur.

## Principe

L’archivage ne déplace pas et ne recopie pas l’objet dans R2. Le fichier reste à son chemin sécurisé et Supabase enregistre :

- `archived_at` ;
- `archived_by` ;
- `restored_at` ;
- `restored_by` ;
- l’année scolaire ;
- l’état dans `metadata`.

Cela évite des copies inutiles et permet une restauration auditée.

## Résumé par année

```json
{ "action": "summary" }
```

Retour Edge Function :

```json
{
  "ok": true,
  "years": [
    {
      "academic_year": "2025-2026",
      "file_count": 120,
      "total_bytes": 48234410,
      "archived_count": 80,
      "active_count": 40
    }
  ]
}
```

Les champs viennent de `get_archive_summary()` :

- `file_count` : tous les fichiers non supprimés de l’année ;
- `total_bytes` : taille totale correspondante ;
- `archived_count` : fichiers archivés ;
- `active_count` : fichiers encore actifs.

`years: []` est un état vide autorisé : aucune archive ou aucun fichier enregistré. Ce n’est pas une erreur de contrat.

## Liste paginée

```json
{
  "action": "list",
  "academic_year": "2025-2026",
  "owner_type": "administrative_document",
  "owner_id": "adm_...",
  "category": "administrative_document",
  "page": 1,
  "limit": 50
}
```

Tous les filtres sont facultatifs. `owner_id` exige `owner_type`. La limite maximale est 100.

## Ouvrir un fichier archivé

```json
{
  "action": "download",
  "file_id": "uuid"
}
```

Le serveur retourne une URL signée valable 300 secondes. Elle ne doit jamais être stockée comme URL permanente.

## Archiver un fichier individuel

```json
{
  "action": "archive",
  "file_id": "uuid"
}
```

Direction 1 uniquement. L’objet R2 reste intact.

## Restaurer un fichier individuel

```json
{
  "action": "restore",
  "file_id": "uuid"
}
```

Une pièce appartenant à un dossier administratif archivé ne peut pas être restaurée seule. Il faut restaurer le dossier complet avec :

```text
restore_administrative_document(p_document_id)
```

## Dossiers administratifs

Archiver un dossier :

```text
archive_administrative_document(p_document_id)
```

Cette opération archive en une seule transaction le dossier et toutes ses pièces non supprimées.

Restaurer un dossier :

```text
restore_administrative_document(p_document_id)
```

Cette opération restaure le dossier et toutes ses pièces non supprimées.

## Interface Claude attendue

- Rubrique « Archives » visible uniquement dans Direction 1.
- Cartes de résumé par année utilisant `file_count`, `total_bytes`, `archived_count` et `active_count`.
- Recherche et filtres par année, type de propriétaire, catégorie et nom.
- Pagination.
- Bouton « Ouvrir » utilisant l’URL temporaire.
- Bouton « Restaurer » avec confirmation.
- Pour un dossier administratif, restauration du dossier complet et non d’une page isolée.
- Affichage de la personne et de la date d’archivage/restauration depuis la liste détaillée.
- Aucun bouton de suppression physique depuis l’écran Archives.
