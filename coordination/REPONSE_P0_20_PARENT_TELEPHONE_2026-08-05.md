# P0-20 — Accès Parent par téléphone + code temporaire WhatsApp

Date : 5 août 2026  
Responsable backend : ChatGPT  
Responsable intégration visible : Claude

## Décision de Loms

Les parents peuvent utiliser SchoolSafe sans adresse e-mail. Leur identité de connexion est leur numéro de téléphone normalisé. WhatsApp sert uniquement à livrer manuellement le code temporaire ; SchoolSafe ne dépend ni de LWS, ni de Brevo, ni d'un SMTP pour ce parcours.

Le numéro communiqué par Loms dans la conversation n'est volontairement écrit ni dans GitHub, ni dans les migrations, ni dans les tests.

## État serveur livré

Le backend est déployé dans le projet Supabase de production :

- `users.email` et `profiles.email` sont facultatifs ;
- les comptes non-Parent continuent d'exiger une adresse e-mail ;
- un Parent choisit `email` ou `phone_whatsapp` ;
- le téléphone est normalisé au format E.164 ;
- un même numéro ne peut appartenir qu'à un seul profil SchoolSafe ;
- les formats locaux RDC sont convertis vers `+243...` ;
- `parent-phone-access` version 1 est ACTIVE et exige un JWT ;
- aucune clé `service_role` ou R2 ne descend dans le navigateur ;
- le code temporaire expire après 30 minutes ;
- nouvelle génération limitée à une fois par minute pour le même compte ;
- tant que le Parent n'a pas changé le code temporaire, `current_app_role()` et `current_app_user_id()` ne lui donnent aucun accès aux données métier ;
- la base vérifie que le mot de passe a réellement changé, par comparaison d'empreintes du hash Auth, sans conserver le code en clair ;
- les préinscriptions peuvent être déposées sans e-mail, avec téléphone obligatoire ;
- aucun e-mail technique temporaire n'est conservé après la transaction.

## Contrat de création ou modification du profil

Le formulaire peut continuer d'appeler :

```sql
save_school_user_profile(p_user jsonb)
```

Le serveur aiguillera automatiquement un Parent sans e-mail vers le contrat téléphone. Réponse utile :

```json
{
  "ok": true,
  "code": "USER_CREATED",
  "requires_phone_provisioning": true,
  "user": {
    "id": "...",
    "phone": "+243...",
    "access_channel": "phone_whatsapp"
  }
}
```

Codes à afficher clairement :

- `PHONE_IN_USE` : ce numéro appartient déjà à un compte ;
- `AUTH_PHONE_CHANGE_REQUIRED` : le numéro d'un compte déjà lié doit passer par le parcours sécurisé de changement ;
- `VALIDATION_ERROR`, `field=phone` : numéro absent ou invalide ;
- `FORBIDDEN` : rôle non autorisé.

Direction 1 et Direction 2 peuvent créer/modifier un Parent téléphone. Les autres rôles sont refusés.

## Contrat Edge Function

Fonction :

```text
parent-phone-access
```

Requête :

```json
{
  "app_user_id": "parent_...",
  "action": "provision"
}
```

Actions :

- `provision` : première création de l'identité Auth ;
- `reset` : nouveau code temporaire pour un compte déjà lié ;
- `change_phone` : nouveau numéro contrôlé + nouveau code temporaire, avec champ `phone`.

Réponse de succès :

```json
{
  "ok": true,
  "code": "PHONE_ACCESS_READY",
  "action": "provision",
  "phone": "+243...",
  "temporary_code": "Sa-0000-0000",
  "expires_at": "...",
  "next_allowed_at": "...",
  "must_change_password": true,
  "delivery_channel": "whatsapp_manual"
}
```

Le `temporary_code` n'est rendu qu'une seule fois dans cette réponse. Il n'est pas enregistré en clair dans PostgreSQL, dans les audits ou dans les journaux de la fonction.

## Message WhatsApp

Le navigateur doit préparer seulement :

```text
Bonjour, votre accès SchoolSafe est prêt.
Identifiant : +243...
Code temporaire : Sa-0000-0000
Ce code expire à ... et doit être remplacé à la première connexion.
Ne le transmettez à personne.
```

Ne jamais ajouter : nom d'enfant, classe, notes, dette, montant, reçu ou donnée médicale.

## Connexion Parent attendue côté Claude

Ajouter sur l'écran de connexion un choix clair :

```text
Adresse e-mail | Numéro de téléphone
```

Pour le téléphone :

```js
await supabase.auth.signInWithPassword({
  phone: telephoneNormalise,
  password: codeOuMotDePasse
});
```

Après connexion, appeler :

```sql
get_my_access_state()
```

Comportements :

- `ACCESS_READY` : ouvrir l'espace Parent ;
- `TEMPORARY_PASSWORD_MUST_CHANGE` : afficher uniquement l'écran « Créer mon code personnel » ;
- `TEMPORARY_PASSWORD_EXPIRED` : refuser l'accès et inviter à demander un nouveau code à la Direction.

Après `auth.updateUser({ password: nouveauMotDePasse })`, appeler :

```sql
confirm_parent_phone_password_change()
```

N'ouvrir l'espace Parent qu'après `ACCESS_READY`. Un simple succès de `updateUser` ne suffit pas.

## Messages Edge importants

- `TOO_SOON` : afficher le compte à rebours jusqu'à `next_allowed_at` ;
- `PHONE_IN_USE` : numéro déjà rattaché ;
- `ALREADY_LINKED` : utiliser `reset`, pas `provision` ;
- `ACCOUNT_NOT_LINKED` : utiliser `provision`, pas `reset` ;
- `TARGET_DISABLED` : compte Parent inactif ;
- `ACCOUNT_UPDATED_FINALIZE_FAILED` : ne jamais afficher ni envoyer un code ; attendre puis recommencer ;
- `AUTH_CREATE_FAILED` / `AUTH_UPDATE_FAILED` : aucun message de réussite.

## Réglage Supabase à vérifier avant recette navigateur

Dans `Authentication → Providers`, le fournisseur **Phone** doit être activé. Aucun fournisseur SMS n'est requis pour ce parcours : l'identité est créée par l'Edge Function avec téléphone confirmé et mot de passe temporaire, puis le code est livré manuellement par WhatsApp.

Ce réglage du tableau de bord n'est pas modifiable par le connecteur utilisé par ChatGPT. Claude doit le vérifier avec Loms avant de déclarer le parcours terminé.

## Recettes déjà exécutées côté serveur

Tests synthétiques, avec `ROLLBACK` :

- création Parent sans e-mail : acceptée ;
- normalisation locale RDC vers `+243...` : vérifiée ;
- même numéro sous une autre écriture : `PHONE_IN_USE` ;
- Enseignant sans e-mail : refusé ;
- ancien compte Direction par e-mail : contrat inchangé ;
- préinscription téléphone sans e-mail : acceptée ;
- délai anti-double-clic : `TOO_SOON` ;
- données synthétiques restantes : 0 ;
- e-mails `@phone.invalid` restants : 0 ;
- fonction `parent-phone-access` version 1 : ACTIVE, `verify_jwt=true`.

## Recettes à faire par Claude avant fusion/publication

1. Activer/vérifier le fournisseur Phone.
2. Créer un Parent synthétique depuis le navigateur.
3. Générer le code par `provision`.
4. Ouvrir WhatsApp sans donnée enfant.
5. Se connecter avec téléphone + code temporaire.
6. Vérifier que les pages Parent restent bloquées avant changement du code.
7. Changer le mot de passe, confirmer, puis ouvrir l'espace Parent.
8. Tester `reset`, expiration, double-clic, numéro dupliqué et changement de numéro.
9. Tester un Parent avec plusieurs enfants sans mélange de données.
10. Vérifier la publication GitHub Pages après fusion.

## Limites non traitées dans ce lot

- aucun vrai profil n'a été créé avec le numéro privé communiqué par Loms, faute de nom de Parent et d'enfant à rattacher ;
- aucun code réel n'a été envoyé ;
- la recette navigateur Auth complète dépend du réglage Phone et de l'intégration Claude ;
- R2, compression et stockage des fichiers restent inchangés ;
- la PR paie nº38 demeure ouverte. Ce lot téléphone a été commencé parce que Loms a explicitement ordonné « Go ».

## Fichiers à intégrer

- `supabase/migrations/20260805223000_parent_phone_auth_schema.sql`
- `supabase/migrations/20260805223500_parent_phone_auth_prepare.sql`
- `supabase/migrations/20260805224000_parent_phone_auth_finalize.sql`
- `supabase/migrations/20260805224200_parent_phone_auth_profile_compat.sql`
- `supabase/migrations/20260805224500_parent_phone_preinscription_compat.sql`
- `supabase/migrations/20260805224600_hide_preinscription_helpers.sql`
- `supabase/migrations/20260805224700_parent_phone_auth_index_cleanup.sql`
- `supabase/functions/parent-phone-access/index.ts`
- `supabase/functions/parent-phone-access/deno.json`

Claude intègre, teste, fusionne et publie. ChatGPT ne publie pas `main`.
