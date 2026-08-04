# SchoolSafe — contrat backend des préinscriptions (P0-6)

## État

Déployé dans le projet Supabase `SchoolSafe` le 4 août 2026.

La couche serveur fournit :

- `public.preinscriptions` ;
- `submit_preinscription(p_request jsonb)` ;
- `validate_preinscription(p_id text)` ;
- `refuse_preinscription(p_id text, p_motif text)`.

## Sécurité

La table n'est ni lisible ni directement insérable par `anon`.

- le site public écrit uniquement avec `submit_preinscription` ;
- le site public ne peut jamais relire une demande ;
- `authenticated` peut interroger la table, mais la RLS ne renvoie des lignes qu'à `direction` ;
- Direction 2, Caisse, Gardien, Enseignant et Parent ne voient aucune préinscription ;
- la validation et le refus vérifient à nouveau que l'appelant est Direction 1 ;
- aucune personne autorisée venue du site ne peut être créée en `approved`.

## 1. Soumission depuis le site

```js
const { data, error } = await supabase.rpc('submit_preinscription', {
  p_request: {
    nom,
    sexe,
    dob,
    lieu_naissance,
    classe,
    ecole_provenance,
    nom_papa,
    nom_maman,
    telephone,
    telephone2,
    adresse,
    email,
    blood_group,
    urgence,
    medical_notes,
    tutelle,
    autorisees: [
      { nom, relation, telephone }
    ]
  }
});
```

Le RPC accepte aussi les champs plats déjà présents sur le site :

```text
a1_nom · a1_relation · a1_telephone
a2_nom · a2_relation · a2_telephone
a3_nom · a3_relation · a3_telephone
```

Réponse normale :

```json
{
  "ok": true,
  "code": "PREINSCRIPTION_CREATED",
  "request_id": "pre_...",
  "created_at": "2026-08-04T15:31:58Z",
  "expire_le": "2026-09-03"
}
```

Une demande identique dans les 24 heures renvoie `ALREADY_SUBMITTED`. Le même téléphone est limité à trois demandes par période de 24 heures. Les champs invisibles `website`, `company` ou `url`, lorsqu'ils sont remplis, déclenchent `INVALID_SUBMISSION` : ils servent de piège anti-robot.

## 2. Lecture Direction 1

La sélection frontend de Claude reste valable :

```text
id,statut,created_at,expire_le,nom,sexe,dob,lieu_naissance,classe,
ecole_provenance,nom_papa,nom_maman,telephone,telephone2,adresse,email,
blood_group,urgence,medical_notes,tutelle,autorisees,motif_refus,
traite_par,traite_par_nom,traite_le
```

L'expiration est fixée à 30 jours à la création. Le frontend continue à calculer l'état visuel `expiree` depuis `expire_le`.

## 3. Validation atomique

```js
const { data, error } = await supabase.rpc('validate_preinscription', {
  p_id: requestId
});
```

La fonction verrouille la demande puis crée dans une seule transaction :

1. le compte Parent/Tuteur ou réutilise le parent existant pour une fratrie ;
2. l'élève et son lien `students.pid` vers le tuteur principal ;
3. le matricule et le numéro d'inscription, sans trou causé par une demande refusée ;
4. le dossier médical lorsque des informations de santé existent ;
5. jusqu'à trois lignes `aps` avec `approval_status='pending'`, `active=false` et sans photo ;
6. les obligations financières dont les types et montants sont déjà configurés dans `fee_types` ;
7. le statut, l'auteur et la date de traitement de la préinscription ;
8. un événement d'audit.

Réponse :

```json
{
  "ok": true,
  "code": "PREINSCRIPTION_VALIDATED",
  "student_id": "student_...",
  "parent_id": "parent_...",
  "parent_reused": false,
  "matricule": "LS-2025-2026-000001",
  "num_inscription": "INS-2025-2026-000001",
  "authorized_pending": 2,
  "obligations_created": 0,
  "warning": "FEES_NOT_CONFIGURED"
}
```

`warning` vaut `FEES_NOT_CONFIGURED` tant que Direction 1 n'a pas configuré de types de frais actifs avec un montant supérieur à zéro. La validation reste réussie ; aucune somme n'est inventée.

Codes importants :

```text
FORBIDDEN
PREINSCRIPTION_NOT_FOUND
PREINSCRIPTION_EXPIRED
CLASS_NOT_FOUND
CLASS_AMBIGUOUS
STUDENT_ALREADY_EXISTS
PARENT_PHONE_AMBIGUOUS
PARENT_EMAIL_IN_USE
```

Un second appel sur une demande validée renvoie `ALREADY_VALIDATED` sans créer de doublon.

## 4. Refus

```js
const { data, error } = await supabase.rpc('refuse_preinscription', {
  p_id: requestId,
  p_motif: motif
});
```

Le refus conserve la demande, le motif, l'auteur et la date. Réponse :

```json
{
  "ok": true,
  "code": "PREINSCRIPTION_REFUSED",
  "request_id": "pre_..."
}
```

## 5. Règle des photographies

Les lignes `aps` en attente peuvent exister sans photographie. Une personne ne peut devenir active que si elle est `approved` et possède une photo. La prise de photo et l'approbation restent donc une action séparée réalisée à l'école.

## 6. Recette exécutée

Toutes les données de test ont été annulées par transaction.

```text
soumission publique                 réussie
validation Direction 1             réussie
élève ↔ parent                     correctement reliés
matricule transactionnel           réussi
2 personnes autorisées             pending / inactive / sans photo
personnes approved                 0
fratrie                            même parent réutilisé
élève en double                    STUDENT_ALREADY_EXISTS
préinscription expirée             PREINSCRIPTION_EXPIRED
refus et motif conservés           réussi
second clic de validation          ALREADY_VALIDATED
anon SELECT table                  interdit
anon INSERT table                  interdit
anon submit_preinscription         autorisé
```
