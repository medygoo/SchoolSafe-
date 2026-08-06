# P0-22 — E-mail ET téléphone, un seul compte

Date : 6 août 2026  
Décision : Loms  
Backend : ChatGPT  
Intégration visible, recette navigateur, fusion et publication : Claude

## Décision remplacée

Le modèle « Direction 1 par e-mail, tous les autres par téléphone » est remplacé.

Chaque profil de Direction 1, Direction 2, Caisse, Enseignant, Gardien et Parent porte désormais :

- une adresse e-mail métier unique ;
- un téléphone unique normalisé E.164 ;
- un seul `auth_user_id` ;
- les deux voies de connexion actives vers ce même compte.

L’élève reste un dossier sans identité Auth personnelle.

## État production

Déjà déployés dans Supabase :

- migration `dual_contact_profiles_all_roles` ;
- migration `dual_contact_auth_contract_and_login_relay` ;
- `parent-phone-access` version 3, JWT obligatoire ;
- `school-login` version 1, relais public protégé par clé cliente, origine autorisée et anti-bruteforce.

Recette SQL avec `ROLLBACK` : profil Enseignant double contact, invitation e-mail et préparation téléphone acceptés ; zéro donnée de test restante.

## Enregistrement des profils

Le navigateur garde le contrat :

```sql
save_school_user_profile(p_user jsonb)
```

Mais doit maintenant transmettre obligatoirement :

```json
{
  "id": "...",
  "name": "...",
  "role": "enseignant",
  "email": "personne@example.com",
  "phone": "+243...",
  "access_channel": "email ou phone_whatsapp",
  "status": "active"
}
```

`access_channel` est uniquement le canal principal de livraison/récupération. Il ne désactive pas l’autre moyen de connexion.

Codes utiles :

- `VALIDATION_ERROR`, `field=email` ;
- `VALIDATION_ERROR`, `field=phone` ;
- `EMAIL_IN_USE` ;
- `PHONE_IN_USE` ;
- `FORBIDDEN_TARGET_ROLE` ;
- `AUTH_EMAIL_CHANGE_REQUIRED` pour une identité déjà liée.

Matrice inchangée : Direction 1 gère tous les comptes ; Direction 2 seulement Enseignant, Gardien et Parent.

## Connexion navigateur obligatoire

Ne plus appeler directement `signInWithPassword` à partir de l’e-mail ou de l’identité technique téléphone.

Appeler l’Edge Function :

```text
school-login
```

Corps e-mail :

```json
{
  "channel": "email",
  "identifier": "personne@example.com",
  "password": "..."
}
```

Corps téléphone :

```json
{
  "channel": "phone",
  "identifier": "+243...",
  "password": "..."
}
```

Réponse :

```json
{
  "ok": true,
  "code": "LOGIN_OK",
  "session": {
    "access_token": "...",
    "refresh_token": "..."
  }
}
```

Puis :

```js
await supabase.auth.setSession({
  access_token: data.session.access_token,
  refresh_token: data.session.refresh_token,
});
```

Ensuite appeler `get_my_access_state()` avant toute lecture métier.

Messages :

- `INVALID_CREDENTIALS` : identifiant ou mot de passe incorrect, sans révéler si le compte existe ;
- `TOO_MANY_ATTEMPTS` : respecter `retry_after_seconds` ;
- `LOGIN_TEMPORARILY_UNAVAILABLE` : panne serveur, ne pas accuser le mot de passe.

## Activation initiale

Deux possibilités vers le même compte :

- invitation e-mail via `invite-school-account` ;
- code temporaire livré manuellement par WhatsApp via `parent-phone-access`.

Ne pas lancer les deux créations en parallèle. Dès que `auth_user_id` existe, l’autre bouton devient une récupération/réinitialisation, jamais une deuxième identité.

## Direction 1 existante

Le compte `lomsmedy@gmail.com` reste valide et n’est pas recréé. Son téléphone est actuellement absent : l’interface doit demander à Loms de l’ajouter pour rendre son profil double contact complet.

## Sécurité

- aucun mot de passe ou code dans GitHub, les audits ou les journaux ;
- l’identité Auth résolue côté serveur ne revient jamais au navigateur ;
- huit essais sur quinze minutes avant blocage temporaire ;
- `must_change_password` bloque tous les rôles jusqu’au changement réel ;
- le fournisseur Supabase Phone reste désactivé : aucun Twilio ou SMS n’est requis.
