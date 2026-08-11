# P0-8 — Cartes/Badges · backend propre pour Claude

Cette version remplace la partie **Cartes** de l'ancienne PR #75. Elle est basée sur le `main` actuel et ne contient **aucun ancien correctif Sortie**.

## Ce que l'audit réel a corrigé

1. **QR permanent** : le frontend Claude signe sur 8 hex (`sig8`). Le backend fait maintenant exactement pareil : `schoolsafe://card/{numero}/{sig8}`.
2. **Bug FK de #75** : l'ancien SQL posait `ancienne.replaced_by = nouvelle_id` avant que la nouvelle ligne existe. Avec la FK immédiate, un duplicata pouvait échouer. Le nouvel ordre est : invalider ancienne → insérer nouvelle → poser `replaced_by`.
3. **Confidentialité** : Parent/Enseignant ne lisent plus directement `student_cards`. Une RPC filtre les colonnes selon le rôle, donc ils ne peuvent pas demander `qr_payload`, note administrative ou auteur d'invalidation par une requête libre.
4. **Historique** : trigger anti-delete + trigger d'immutabilité. Une carte invalidée ne peut jamais redevenir active.
5. **Multi-école futur** : le préfixe du numéro est `settings.student_card_prefix`, pas `LS` codé dans la fonction. Pour Le Sage, valeur initiale `LS`.
6. **Photo** : P0-8 n'accepte pas `data:`/`blob:` comme photo permanente de carte. Le frontend doit fournir une référence/URL durable de stockage, pas l'image elle-même dans PostgreSQL.

## RPC à raccorder

### 1. Émettre / renouveler / duplicata

`issue_student_card(p_sid, p_year, p_emission, p_motif, p_note, p_photo, p_class_id, p_replaces)`

Rôles : Direction 1 + Direction 2.

Retour succès :

```json
{
  "ok": true,
  "code": "CARD_ISSUED",
  "data": {
    "id": "card_...",
    "card_no": "LS-2026-2027-0001",
    "qr_payload": "schoolsafe://card/LS-2026-2027-0001/1a2b3c4d",
    "issued_at": "..."
  }
}
```

Le navigateur ne calcule plus `card_no`, ne signe plus le QR et n'invalide plus l'ancienne carte lui-même.

### 2. Perte

`declare_student_card_lost(p_card_id, p_motif)`

La carte cesse immédiatement d'être valide. Le duplicata peut être émis plus tard.

### 3. Révocation

`revoke_student_card(p_card_id, p_motif)`

### 4. Réimpression

`count_student_card_print(p_card_id)`

À appeler seulement pour une réimpression. La première impression est déjà comptée par l'émission.

### 5. Lecture registre / fiche

`get_student_card_center(p_sid = null, p_year = null)`

**Ne pas ajouter les anciens `_T('student_cards', ...)` directs.**

- Direction 1/2 : registre complet ;
- Enseignant : ses classes, colonnes pédagogiques minimales ;
- Parent : ses enfants, numéro/état/date ;
- Gardien : refus ;
- Caisse : refus.

### 6. Scanner une carte permanente

`verify_student_card_qr(p_payload)`

Rôles autorisés : Direction 1, Direction 2, Enseignant, Gardien.

Le serveur vérifie, dans cet ordre :

- format QR ;
- signature HMAC ;
- numéro présent au registre ;
- statut actif ;
- année scolaire courante ;
- élève non archivé.

Retour valide :

```json
{
  "ok": true,
  "valid": true,
  "refusal_code": null,
  "card": {"id":"...","card_no":"...","year":"...","status":"active"},
  "student": {"id":"...","name":"...","mat":"...","photo":"...","class_name":"..."}
}
```

Le Gardien ne reçoit aucune donnée familiale ou financière.

## Codes utiles à l'interface

`CARD_ROLE_DENIED`, `CARD_STUDENT_NOT_FOUND`, `CARD_INCOMPLETE_FILE`, `CARD_MOTIF_REQUIRED`, `CARD_ALREADY_ACTIVE`, `CARD_YEAR_MISMATCH`, `CARD_CLASS_MISMATCH`, `CARD_QR_SECRET_MISSING`, `CARD_NOT_FOUND`, `CARD_NOT_ACTIVE`, `CARD_QR_FORMAT_INVALID`, `CARD_QR_SIGNATURE_INVALID`, `CARD_LOST`, `CARD_REPLACED`, `CARD_DAMAGED`, `CARD_REVOKED`, `CARD_WRONG_YEAR`, `CARD_STUDENT_ARCHIVED`.

## Secret QR permanent et futur VPS

La clé `private.qr_keys.student_card_v1` **n'est pas dans GitHub et n'est jamais retournée au navigateur**.

Règle de migration : si des cartes physiques ont déjà été émises avant le passage Hosted Supabase → VPS, **la même clé doit être transférée par canal secret**. Générer une nouvelle clé invaliderait toutes les cartes déjà imprimées.

Le fichier `p0_8_student_card_key_bootstrap_DRAFT.sql` ne génère une clé que si aucune carte n'existe.

## Ce que Claude doit changer dans le frontend après validation backend

- `confirmerEmissionCarte` → RPC `issue_student_card` ; seulement après succès, mettre à jour `DB.student_cards`, imprimer le `qr_payload` serveur et afficher le succès ;
- `confirmerPerteCarte` → `declare_student_card_lost` ;
- `confirmerRevocation` → `revoke_student_card` ;
- `imprimerCarte` en réimpression → `count_student_card_print` ;
- chargement des cartes → `get_student_card_center`, pas table directe ;
- `_resoudreCarteQR` → `verify_student_card_qr` ; le navigateur ne doit plus lire `DB.settings.qr_secret` pour les cartes permanentes ;
- conserver les messages détaillés par code de refus ;
- si `s.photo` est encore une image `data:` ou `blob:`, la mettre d'abord dans le stockage durable avant l'émission.

## État

Tout est encore **DRAFT**. Aucun SQL P0-8 n'a été appliqué au Supabase réel, aucune clé n'a été créée en production, aucun VPS n'a été modifié.
