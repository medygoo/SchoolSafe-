# SchoolSafe — Compression automatique des images R2

Date : 2026-08-03

## Endpoint d’envoi obligatoire

Tous les nouveaux envois du frontend doivent appeler la Supabase Edge Function :

```text
r2-upload
```

Version de production validée : **4**.

La fonction exige :

- une session JWT valide ;
- une requête `multipart/form-data` ;
- un en-tête `x-idempotency-key` stable de 8 à 128 caractères ;
- les mêmes champs `owner_type`, `owner_id`, `category`, `display_name` et, lorsque nécessaire, `payment_transaction_id` que le contrat R2 principal.

Le frontend ne doit plus envoyer directement un nouveau fichier à l’action `upload` de `r2-files`. `r2-files` reste utilisé pour `list`, `download`, `delete` et les contrôles internes du stockage.

Ne jamais appeler :

- `r2-upload-test` ;
- `r2-compression-self-test` ;
- `r2-self-test` ;
- `r2-role-self-test` ;
- `r2-role-self-test-a` ;
- `r2-role-self-test-b` ;
- `image-magick-diagnostic` ;
- `r2-upload-v4-self-test`.

Ces endpoints ont été retirés du circuit et répondent `410` avec JWT obligatoire.

## Formats

Formats sources acceptés :

- JPEG ;
- PNG ;
- WebP ;
- PDF.

Limites :

- fichier source : 8 Mo maximum ;
- fichier final enregistré dans R2 : 5 Mo maximum ;
- image : 12 000 pixels maximum par côté ;
- image : 40 mégapixels maximum.

Le serveur vérifie la signature binaire réelle du fichier, puis décode réellement les images. Une extension ou un type MIME falsifié, une image tronquée ou un contenu indécodable reçoit `415` et aucun objet R2 n’est créé.

## Profils de traitement

| Profil | Catégories principales | Dimension maximale | Qualité initiale |
|---|---|---:|---:|
| `photo` | photos élèves, personnel et personnes autorisées | 1280 px | 76 |
| `identity` | documents ou portraits d’identité | 1600 px | 80 |
| `card` | cartes et badges | 1800 px | 84 |
| `document` | reçus, factures, devoirs, rapports, cahiers et documents administratifs | 2400 px | 84 |
| `passthrough` | PDF ou image déjà plus petite que la version WebP proposée | inchangé | sans objet |

Le serveur :

1. valide la session avant le décodage de l’image ;
2. vérifie la signature binaire, les dimensions et le décodage réel ;
3. corrige l’orientation lorsque les métadonnées le permettent ;
4. retire les profils EXIF, XMP et IPTC lorsqu’ils existent ;
5. redimensionne selon la catégorie ;
6. produit une version WebP ;
7. réduit progressivement la qualité et les dimensions si le résultat dépasse 5 Mo ;
8. conserve l’image originale lorsque la version WebP n’économise pas au moins 2 %, sauf si la source dépasse déjà 5 Mo ;
9. transmet ensuite le fichier final à `r2-files`, qui applique toutes les permissions SchoolSafe et écrit dans Cloudflare R2 ;
10. enregistre les métriques d’optimisation dans `school_files`.

Les PDF ne sont ni convertis ni recompressés.

## Réponse

Exemple simplifié :

```json
{
  "ok": true,
  "reused": false,
  "file": {
    "id": "uuid",
    "mime_type": "image/webp",
    "size_bytes": 184532
  },
  "optimization": {
    "id": "uuid",
    "source_size_bytes": 1320000,
    "size_bytes": 184532,
    "compression_saved_bytes": 1135468,
    "compression_ratio_pct": 86.02,
    "optimized": true,
    "compression_profile": "document",
    "source_width": 3024,
    "source_height": 4032,
    "processed_width": 1800,
    "processed_height": 2400
  }
}
```

Les métriques suivantes sont enregistrées dans `school_files` :

- nom du fichier source ;
- type MIME source ;
- taille source ;
- dimensions source ;
- dimensions finales ;
- profil de compression ;
- qualité finale ;
- version du traitement ;
- économie en octets ;
- économie en pourcentage.

## Reprise et idempotence

Claude doit générer une clé stable par tentative logique et la réutiliser après une coupure réseau.

Lorsque la réponse contient :

```json
{
  "upload_committed": true,
  "retry_same_idempotency_key": true
}
```

le fichier est déjà dans R2, mais l’écriture des métriques doit être reprise. Le frontend ne doit pas générer une nouvelle clé et ne doit pas envoyer une deuxième copie.

## Codes à gérer

- `400` : formulaire ou clé d’idempotence invalide ;
- `401` : session absente ou invalide ;
- `403` : rôle ou propriétaire interdit ;
- `409` : année, propriétaire, archive ou clé déjà utilisée de façon incompatible ;
- `413` : source trop grande, dimensions excessives ou fichier final supérieur à 5 Mo ;
- `415` : format non pris en charge, type déclaré incorrect, contenu tronqué ou image indécodable ;
- `500` : erreur temporaire ; réutiliser la même clé lorsque `retry_same_idempotency_key=true`.

Exemple de rejet d’une image indécodable :

```json
{
  "error": "Image is corrupt or cannot be decoded"
}
```

## Preuves techniques réalisées

### Circuit initial

Une image PNG synthétique de 256 × 256 pixels et 568 octets a été convertie en WebP 128 × 128 de 116 octets :

- économie : 452 octets ;
- réduction mesurée : 79,58 % ;
- écriture R2 : réussie ;
- relecture R2 : réussie ;
- contenu relu identique : réussi ;
- suppression après test : réussie.

### Tests authentifiés des rôles

- lot A : 22/22 contrôles réussis ;
- lot B : 20/20 contrôles réussis ;
- total : 42/42 contrôles réussis.

Le lot A a mesuré :

- photo : 568 → 194 octets, réduction 65,85 % ;
- reçu : 568 → 198 octets, réduction 65,14 %.

### Validation ciblée version 4

- PNG valide 64 × 64 : 133 → 100 octets ;
- réduction : 24,81 % ;
- métriques enregistrées ;
- PNG volontairement corrompu : HTTP `415` ;
- aucun objet créé pour le fichier corrompu ;
- suppression du fichier valide : réussie ;
- résultat : 4/4 contrôles réussis.

Ces mesures prouvent le fonctionnement du circuit, mais ne constituent pas un taux garanti. Les économies réelles varieront selon les photos et documents.
