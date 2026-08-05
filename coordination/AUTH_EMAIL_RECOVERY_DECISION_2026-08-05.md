# Comptes SchoolSafe — e-mail obligatoire et récupération d’accès

Décision de Loms, 5 août 2026.

## Règle métier

1. Tout profil pouvant se connecter à SchoolSafe possède obligatoirement une adresse e-mail.
2. L’adresse est enregistrée dans `public.users.email`, normalisée en minuscules et unique.
3. La première connexion passe par l’invitation Supabase Auth envoyée à cette adresse.
4. Une personne qui perd son ancien code ou son mot de passe utilise **Mot de passe oublié**. Elle reçoit un lien de récupération et choisit un nouveau mot de passe dans `auth.html`.
5. Aucun mot de passe et aucun PIN ne sont stockés dans `public.users`.
6. L’ancien chemin `pin`, `pin_hashed`, `pin_hashed_v2` et la connexion PIN hors ligne doivent être retirés du frontend.
7. Le message de récupération doit rester neutre : ne pas révéler si une adresse existe ou non.

## Backend déployé

Migrations Supabase actives :

- `20260804233228_require_email_for_school_accounts.sql`
- `20260804233449_require_email_in_preinscription_rpc.sql`

Garanties :

- `public.users.email` est `NOT NULL` ;
- adresse normalisée, validée et unique ;
- `save_school_user_profile(p_user)` refuse une adresse absente avec `VALIDATION_ERROR`, champ `email` ;
- une adresse déjà utilisée renvoie `EMAIL_IN_USE` ;
- un profil lié à Auth ne peut pas changer son adresse seulement dans la table applicative : `AUTH_EMAIL_CHANGE_REQUIRED` ;
- une création valide renvoie `requires_invitation: true` tant que l’identité Auth n’est pas liée ;
- la préinscription publique exige également l’e-mail destiné au futur compte Parent ;
- `invite-school-account` est actif avec JWT obligatoire et crée l’invitation Supabase Auth ;
- `dist/auth.html` traite déjà les liens d’invitation et de récupération.

## Recette transactionnelle

Toutes les données de test ont été annulées par `ROLLBACK`.

```text
profil sans e-mail                 VALIDATION_ERROR · field=email
profil avec adresse en majuscules  USER_CREATED · adresse normalisée
second profil avec même adresse    EMAIL_IN_USE
préinscription sans e-mail         VALIDATION_ERROR · field=email
```

## Raccordement attendu de Claude

### Création/modification d’un profil

- rendre le champ e-mail obligatoire dans l’écran ;
- appeler `save_school_user_profile` sans aucun champ PIN ;
- si `requires_invitation=true`, appeler ensuite `invite-school-account` avec `app_user_id` et l’e-mail enregistré ;
- attendre les deux réponses avant d’annoncer que le compte est prêt ;
- afficher clairement `EMAIL_IN_USE`, `AUTH_EMAIL_CHANGE_REQUIRED` et les validations de champ.

### Mot de passe oublié

- lire l’adresse saisie sur l’écran de connexion ;
- appeler `supabase.auth.resetPasswordForEmail(email, { redirectTo: <URL autorisée vers auth.html> })` ;
- afficher dans tous les cas un message neutre du type : « Si cette adresse correspond à un compte, un lien vient d’être envoyé. » ;
- ne jamais rechercher publiquement un utilisateur par e-mail ;
- ne jamais recréer un profil pour récupérer un accès.

### Retrait de l’ancien code

- retirer de `saveUser` les champs `pin`, `pin_hashed`, `pin_hashed_v2` ;
- retirer l’authentification PIN et son repli hors ligne ;
- conserver le fonctionnement hors ligne après connexion uniquement pour les données autorisées, jamais pour ouvrir une nouvelle session.

## Profil supprimé constaté

L’audit conserve seulement la création de `Lolo — enseignant`, identifiant applicatif `u_2cc5539a-14a0-475e-a0a5-98c6d2ecfad1`. Le profil, l’identité Auth et l’invitation ont été supprimés, et l’audit ne conserve pas son ancienne adresse e-mail. Cette adresse ne doit pas être inventée. Le profil pourra être recréé proprement après le raccordement ci-dessus, avec son adresse réelle.