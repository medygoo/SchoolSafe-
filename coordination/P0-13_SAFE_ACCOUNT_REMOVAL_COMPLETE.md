# P0-13 — suppression sécurisée d’un compte : backend servi

Date : 6 août 2026  
Décision : Loms  
Backend : ChatGPT  
Intégration visible et recette navigateur : Claude

## État production

Migration active : `p0_13_safe_school_account_removal`.

Migration miroir :

`supabase/migrations/20260806104500_p0_13_safe_school_account_removal.sql`

Edge Function active, JWT obligatoire :

`remove-school-account`

Code miroir :

`supabase/functions/remove-school-account/index.ts`

## Décision technique

Supprimer un accès ne supprime plus la fiche historique `public.users`.

Le système :

1. rend immédiatement le profil `inactive` ;
2. désactive la connexion par e-mail et téléphone ;
3. annule les invitations et codes temporaires encore en attente ;
4. supprime l’identité Supabase Auth et ses sessions ;
5. conserve la fiche SchoolSafe, le nom, le rôle et les traces d’audit ;
6. conserve les auteurs des paiements et des fichiers.

La relation `users.auth_user_id → auth.users.id` est désormais `ON DELETE SET NULL`, pas `CASCADE`.

## Appel navigateur

Ne jamais supprimer directement une ligne de `users` ou de `profiles`.

Appeler l’Edge Function :

```text
remove-school-account
```

Corps :

```json
{
  "app_user_id": "identifiant SchoolSafe du compte",
  "reason": "Motif administratif précis"
}
```

La fonction exige :

- une session JWT valide ;
- le rôle `direction` ;
- un motif de 5 à 500 caractères ;
- une cible différente du compte actuellement connecté.

## Réponse de succès

```json
{
  "ok": true,
  "code": "ACCOUNT_ACCESS_REMOVED",
  "app_user_id": "...",
  "status": "inactive",
  "access_removed_at": "..."
}
```

## Codes à afficher

- `CANNOT_REMOVE_CURRENT_ACCOUNT` : « Vous ne pouvez pas supprimer votre propre accès. »
- `LAST_DIRECTION_ACCOUNT` : « Le dernier compte Direction 1 ne peut pas être supprimé. »
- `TARGET_NOT_FOUND` : « Le compte demandé est introuvable. »
- `INVALID_REASON` : « Indiquez un motif administratif d’au moins 5 caractères. »
- `AUTH_DELETE_FAILED` : « L’accès est désactivé, mais la suppression Auth doit être réessayée. »
- `ACCOUNT_ACCESS_REMOVED` : « L’accès a été supprimé. Les données historiques sont conservées. »

Quand `AUTH_DELETE_FAILED` apparaît, le compte est déjà inactif et ne peut plus ouvrir les données SchoolSafe. Réappeler la même fonction permet de retenter la suppression de l’identité Auth.

## Protection des fichiers

Les futurs fichiers enregistrent désormais un instantané immuable :

- `uploaded_by_app_user_id`
- `uploaded_by_name`
- `uploaded_by_role`

L’ancien UUID `uploaded_by` devient nullable lorsque l’identité Auth est supprimée, mais le nom et le rôle de l’auteur restent disponibles.

## Recette production

Transaction avec `ROLLBACK` :

- création d’un enseignant fictif sans Auth ;
- préparation de suppression acceptée ;
- profil passé à `inactive` ;
- e-mail et téléphone de connexion désactivés ;
- horodatage et auteur du retrait présents ;
- confirmation acceptée ;
- auto-suppression de Direction 1 refusée ;
- aucune donnée de test restante.

Les RPC internes `prepare_school_account_removal` et `confirm_school_account_removal` sont exécutables uniquement par `service_role`; le navigateur passe obligatoirement par l’Edge Function authentifiée.
