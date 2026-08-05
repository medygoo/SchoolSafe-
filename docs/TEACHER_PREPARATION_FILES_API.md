# SchoolSafe — Fichiers du cahier de préparation

Backend appliqué le 3 août 2026.

## Objectif

Permettre à un enseignant de joindre plusieurs photos ou PDF à une préparation de cours existante dans `cahier_prep`.

La préparation reste une donnée structurée dans Supabase. Les images et PDF sont stockés dans Cloudflare R2.

## Accès

| Profil | Accès aux préparations et fichiers |
|---|---|
| Direction 1 | Toutes les préparations |
| Direction 2 | Toutes les préparations pédagogiques |
| Enseignant | Ses propres préparations uniquement |
| Caisse | Aucun |
| Parent | Aucun |
| Gardien | Aucun |

## Création de la préparation

Le frontend crée ou met à jour une ligne dans `cahier_prep` avec le compte de l’enseignant connecté.

Le champ `teacher_id` doit correspondre à l’identifiant SchoolSafe de cet enseignant. La RLS refuse l’accès à une préparation appartenant à un autre enseignant.

## Envoi d’une pièce jointe

Edge Function : `r2-files` version 4.

Requête `multipart/form-data` :

```text
action=upload
owner_type=cahier_prep
owner_id=<cahier_prep.id>
category=teacher_preparation
academic_year=2026-2027
display_name=<nom lisible>
file=<JPEG, PNG, WebP ou PDF>
```

En-tête recommandé et obligatoire pour une reprise fiable :

```text
x-idempotency-key=<clé stable de 8 à 128 caractères>
```

Exemples de `display_name` :

- Page 1 du cahier
- Page 2 du cahier
- Schéma de la leçon
- Fiche d’exercices
- Support de lecture
- Annexe d’évaluation

## Plusieurs fichiers

Une préparation peut contenir plusieurs pièces. Toutes utilisent le même :

```text
owner_type=cahier_prep
owner_id=<même préparation>
category=teacher_preparation
```

Chaque fichier utilise une clé d’idempotence distincte.

## Liste des pièces

```json
{
  "action": "list",
  "owner_type": "cahier_prep",
  "owner_id": "<cahier_prep.id>",
  "category": "teacher_preparation",
  "limit": 50
}
```

Le frontend affiche :

- `display_name`
- type MIME
- taille
- date d’enregistrement
- bouton d’ouverture

## Ouverture

```json
{
  "action": "download",
  "file_id": "uuid"
}
```

L’URL reçue expire après 300 secondes. Elle ne doit pas être stockée comme URL permanente.

## Règles frontend

- Ne pas mettre les fichiers en base64 dans `cahier_prep`.
- Ne pas utiliser Supabase Storage pour ces pièces.
- Ne jamais envoyer une clé R2 au navigateur.
- Vérifier que la préparation a été créée avant l’envoi.
- Afficher l’état de progression et les erreurs réseau.
- Gérer `reused=true` après une reprise avec la même clé d’idempotence.
- Empêcher un enseignant d’indiquer manuellement l’identifiant d’une préparation appartenant à un autre enseignant.
- Direction 2 peut consulter, mais ne doit recevoir aucune information financière par cette interface.
