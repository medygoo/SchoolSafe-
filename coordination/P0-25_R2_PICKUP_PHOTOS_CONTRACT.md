# P0-25 — Photos R2 du parent principal et des personnes autorisées

Statut : **DRAFT / NON DÉPLOYÉ**.

Ce lot résout le décalage trouvé après la PR frontend #81 : le formulaire veut envoyer les photos avant de créer une nouvelle personne autorisée, alors que R2 exige que `owner_type=authorized_person` pointe vers une ligne `aps` déjà existante.

Il résout aussi un deuxième problème : R2 est privé et `r2-files/download` renvoie une URL signée qui expire après 300 secondes. Une telle URL ne peut donc jamais être enregistrée durablement dans `aps.photo` ou `users.photo_url`.

## Décision commune proposée

### Référence permanente

Le nouveau parcours garde le `school_files.id` UUID comme référence permanente.

Colonnes dédiées proposées :

- `aps.photo_file_id`
- `aps.photo_full_body_file_id`
- `users.photo_file_id`
- `users.identity_full_body_photo_file_id`
- snapshots correspondants dans `student_exit_events` et `scan_log`.

Les anciens champs texte `photo`, `photo_full_body`, `photo_url`, `identity_full_body_photo_url` restent présents pour compatibilité historique. On ne met jamais une URL signée R2 dans ces champs.

## Nouvelle personne autorisée — séquence sûre

1. Direction 1 ou Direction 2 appelle `reserve_authorized_pickup_person(p_person)` avec identité, lien, téléphone, pièce et dates, mais sans photo.
2. Le serveur valide le rôle, l'élève, E.164, les dates et le plafond de trois, puis crée/réutilise une ligne `aps` **pending + inactive**.
3. La RPC retourne `person_id`.
4. Le navigateur envoie les deux images par `r2-upload` avec :
   - `owner_type=authorized_person`
   - `owner_id=<person_id>`
   - `category=photo`
   - `display_name=Portrait` puis `Photo en pied`
   - une clé d'idempotence stable par image.
5. `r2-upload` retourne `file.id` pour chaque image. Le navigateur conserve ces UUID, jamais une URL temporaire.
6. Le navigateur appelle `save_authorized_pickup_person` avec le même `id` et :
   - `photo_portrait_file_id`
   - `photo_full_body_file_id`
7. Le serveur vérifie que les deux UUID existent dans `school_files`, ne sont ni archivés ni supprimés, portent `owner_type=authorized_person`, le bon `owner_id` et `category=photo`.
8. Seulement après ces contrôles, la personne passe `approved + active`.

Un upload interrompu peut laisser une ligne `pending + inactive`, mais **jamais une personne autorisée active sans identité complète**. La prochaine tentative peut réutiliser la réservation.

## Personne autorisée déjà existante

La ligne `aps` existe déjà. Il n'est donc pas nécessaire de réserver :

1. envoyer la ou les nouvelles images avec son `owner_id` existant ;
2. appeler `save_authorized_pickup_person` avec les nouveaux `file_id` ;
3. le serveur valide l'appartenance des fichiers avant de remplacer les références.

Le remplacement ne supprime pas automatiquement l'ancien objet R2 ; la politique d'archivage/nettoyage reste séparée afin de ne pas perdre un historique par erreur.

## Parent principal

Le parent existe déjà dans `public.users`, donc aucune réservation n'est nécessaire.

Les deux images utilisent :

- `owner_type=user`
- `owner_id=<parent_id>`
- `category=photo`
- `display_name=Portrait parent principal` / `Photo en pied parent principal`.

`save_primary_parent_pickup_identity(...)` reste la RPC frontend, mais accepte les UUID `school_files.id` dans ses deux paramètres photo. Le backend reconnaît un UUID R2, vérifie le propriétaire et remplit les nouvelles colonnes `*_file_id`. Les anciennes URL HTTPS restent acceptées uniquement comme compatibilité historique.

## Affichage des photos

### Direction / Direction 2 / Parent

Le frontend peut utiliser le téléchargement R2 déjà autorisé selon le contrat existant et transformer le `file_id` en URL signée uniquement au moment d'afficher.

### Gardien au portail

Le Gardien conserve **zéro accès général à R2**.

Nouvelle Edge Function proposée : `r2-pickup-photo`.

Requête :

```json
{
  "file_id": "<uuid>",
  "student_id": "<student_id>"
}
```

La fonction authentifie le compte puis, pour le Gardien :

- accepte uniquement une image active/non archivée/non supprimée ;
- si `owner_type=authorized_person`, vérifie que `aps.owner_id` appartient exactement à `student_id`, est `approved`, active et non expirée ;
- si `owner_type=user`, vérifie que ce user est le parent principal actuel de `student_id` et que le compte parent est actif ;
- sinon refuse.

Réponse après succès : URL signée 300 secondes, `Cache-Control: no-store`.

Aucune clé R2 n'entre dans le navigateur.

## Contexte de sortie

`get_student_pickup_context(p_sid)` doit retourner, en plus des anciens champs texte :

- `photo_portrait_file_id`
- `photo_full_body_file_id`

pour le parent principal et chaque personne autorisée.

Le navigateur :

1. préfère le `file_id` lorsqu'il existe ;
2. résout ce `file_id` au moment de l'affichage ;
3. utilise l'ancienne URL HTTPS uniquement si aucun `file_id` n'existe ;
4. ne conserve jamais une URL signée comme référence permanente.

## Historique immuable de sortie

Les événements et le journal de scan reçoivent aussi :

- `escort_photo_portrait_file_id_snapshot`
- `escort_photo_full_body_file_id_snapshot`

Le snapshot garde l'identifiant permanent du fichier qui a servi à la vérification au moment de la sortie. Les anciens snapshots texte restent pour compatibilité.

## Codes frontend utiles

Réservation :

- `AUTHORIZED_PERSON_UPLOAD_RESERVED`
- `AUTHORIZED_PERSON_UPLOAD_RESERVATION_REUSED`
- `FORBIDDEN`
- `ACTOR_NOT_FOUND`
- `STUDENT_NOT_FOUND`
- `MAX_THREE_AUTHORIZED`
- `VALIDATION_ERROR`
- `INVALID_VALIDITY_PERIOD`

Finalisation :

- `AUTHORIZED_PERSON_CREATED`
- `AUTHORIZED_PERSON_UPDATED`
- `PHOTO_FILE_NOT_FOUND`
- `PHOTO_FILE_OWNER_MISMATCH`
- `PHOTO_FILE_UNAVAILABLE`
- codes existants de validation.

Lecture portail : HTTP 401 session absente, 403 relation/rôle refusé, 404 fichier ou relation introuvable, 409 fichier indisponible.

## Tests avant toute production

- nouvelle personne : réservation → 2 uploads → finalisation ;
- coupure après réservation : aucune personne active ;
- coupure après un seul upload : aucune personne active ;
- réessai avec mêmes clés d'idempotence ;
- 4e personne active refusée ;
- fichier d'un autre `owner_id` refusé à la finalisation ;
- fichier document/PDF refusé comme photo ;
- fichier archivé/supprimé refusé ;
- Gardien peut voir uniquement les photos liées au bon élève ;
- Gardien + mauvais `student_id` → 403 ;
- UUID aléatoire → 404 ;
- Parent principal et personne accréditée ;
- snapshot de sortie conserve les file_id ;
- URL signée expirée → le frontend en redemande une, sans modifier la fiche.

## Déploiement

Ce lot reste sur GitHub en brouillon. Aucun DDL, aucune Edge Function et aucune donnée ne sont appliqués au Supabase réel tant que le contrat frontend/backend n'est pas convergé et validé.