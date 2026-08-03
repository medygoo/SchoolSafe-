# Contrat de persistance SchoolSafe

Date : 3 août 2026  
Responsabilité backend : ChatGPT / Supabase  
Responsabilité intégration frontend : Claude Code

## État constaté

- La base Supabase fonctionne.
- Un seul compte applicatif est actuellement relié à Supabase Auth.
- Quatorze lignes de `public.users` n'ont pas encore de `auth_user_id`.
- Le frontend utilise `pushSync()` mais ignore son résultat dans de nombreuses fonctions.
- Une confirmation ne doit plus être affichée avant la réponse positive du serveur.

Aucune invitation massive n'a été envoyée pendant les tests.

## 1. Création d'un compte enseignant, parent, gardien ou direction

### Fonction Edge déployée

`invite-school-account`

- JWT obligatoire.
- Seule la Direction 1 (`role = direction`) peut l'appeler.
- La clé `service_role` reste uniquement côté serveur.
- Le compte cible doit déjà exister dans `public.users`.
- Le serveur crée une invitation courte, appelle Supabase Auth et laisse le trigger existant relier :
  - `auth.users` ;
  - `public.profiles` ;
  - `public.users.auth_user_id`.
- En cas d'échec de Supabase Auth, l'invitation préparée est annulée.

### Appel frontend

```js
const { data: sessionData } = await window._authClient.auth.getSession();
const token = sessionData?.session?.access_token;

const response = await fetch(
  `${OPS_SUPA_URL}/functions/v1/invite-school-account`,
  {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      app_user_id: user.id,
      email: user.email
    })
  }
);

const result = await response.json();
if (!response.ok || result.ok !== true) {
  throw new Error(result.code || 'INVITE_FAILED');
}
```

### Réponse positive

```json
{
  "ok": true,
  "code": "ACCOUNT_INVITED",
  "app_user_id": "...",
  "auth_user_id": "...",
  "email": "...",
  "role": "enseignant",
  "status": "active",
  "request_id": "..."
}
```

### Codes à traduire dans l'interface

| Code | Message utilisateur |
|---|---|
| `AUTH_REQUIRED` / `AUTH_INVALID` | Votre session a expiré. Reconnectez-vous. |
| `FORBIDDEN` | Seule la Direction générale peut créer ce compte. |
| `TARGET_NOT_FOUND` | Le profil SchoolSafe est introuvable. |
| `TARGET_DISABLED` | Ce profil est désactivé. |
| `ALREADY_LINKED` | Ce profil possède déjà un compte de connexion. |
| `EMAIL_IN_USE` | Cette adresse e-mail est déjà utilisée. |
| `VALIDATION_ERROR` | Vérifiez l'adresse e-mail et les informations obligatoires. |
| `INVITE_FAILED` | L'invitation n'a pas pu être envoyée. Rien n'a été validé. |
| `LINK_NOT_CONFIRMED` | Le compte Auth a été créé, mais sa liaison doit être contrôlée. |

## 2. Enregistrement confirmé d'un élève

### RPC déployée

`public.save_student_profile(p_student jsonb)`

- Fonction `SECURITY INVOKER` : elle conserve les règles RLS de la personne connectée.
- Autorisée à Direction 1 et Direction 2.
- Elle crée ou modifie selon l'existence de `p_student.id`.
- Elle vérifie avant écriture :
  - identifiant ;
  - nom ;
  - classe existante ;
  - matricule non utilisé ;
  - parent actif et de rôle `parent` lorsqu'un `pid` est fourni ;
  - types booléens ;
  - autorisation de sortie seule ;
  - photo sous forme de référence de fichier, jamais en base64 `data:`.
- Elle renvoie la ligne réellement enregistrée par PostgreSQL.

### Appel frontend avec Supabase JS

```js
const payload = {
  id: student.id,
  name: student.name,
  mat: student.mat || null,
  cid: student.cid,
  pid: student.pid || null,
  dob: student.dob || null,
  photo: student.photo || null,
  adresse: student.adresse || null,
  nom_papa: student.nom_papa || null,
  nom_maman: student.nom_maman || null,
  lieu_naissance: student.lieu_naissance || null,
  num_inscription: student.num_inscription || null,
  access_parent: student.access_parent !== false,
  may_leave_alone: student.may_leave_alone === true,
  leave_alone_until: student.leave_alone_until || null
};

const { data, error } = await window._authClient.rpc(
  'save_student_profile',
  { p_student: payload }
);

if (error) throw error;
if (!data?.ok) throw new Error(data?.code || 'STUDENT_SAVE_FAILED');

const savedStudent = data.student;
```

### Réponses positives

- `STUDENT_CREATED`
- `STUDENT_UPDATED`

### Codes à traduire

| Code | Message utilisateur |
|---|---|
| `FORBIDDEN` | Votre profil n'est pas autorisé à enregistrer un élève. |
| `ACTOR_NOT_FOUND` | Votre compte SchoolSafe n'est pas relié correctement. |
| `CLASS_NOT_FOUND` | La classe sélectionnée n'existe pas dans la base. |
| `PARENT_NOT_FOUND` | Le compte parent sélectionné est introuvable ou inactif. |
| `MATRICULE_IN_USE` | Ce matricule appartient déjà à un autre élève. |
| `PHOTO_MUST_BE_FILE_REFERENCE` | Téléversez la photo avant d'enregistrer l'élève. |
| `LEAVE_AUTHORIZATION_DATE_REQUIRED` | Indiquez la date de fin de l'autorisation de sortie seule. |
| `VALIDATION_ERROR` | Une information obligatoire est incorrecte. |
| `REFERENCE_NOT_FOUND` | Une classe ou un parent lié n'existe plus. |
| `DUPLICATE_STUDENT` | Cet élève existe déjà. |

## 3. Règle obligatoire pour tous les boutons Enregistrer

Le frontend doit appliquer cet ordre :

1. désactiver le bouton et afficher « Enregistrement… » ;
2. attendre la réponse Supabase avec `await` ;
3. vérifier `error`, `response.ok` et `data.ok` ;
4. remplacer l'objet local par la ligne retournée par le serveur ;
5. afficher la confirmation uniquement après succès ;
6. conserver le formulaire ouvert et afficher le vrai message en cas d'échec ;
7. ne jamais effacer une erreur dans un `catch` vide ;
8. ne jamais considérer une simple mise en file locale comme une sauvegarde terminée.

## 4. Modification attendue dans le monolithe

Claude doit rechercher :

- `pushSync()` ;
- la fonction de sauvegarde d'un élève ;
- la fonction de création/modification d'un utilisateur ;
- les confirmations affichées avant la réponse serveur.

Pour les élèves, remplacer l'écriture directe dans `students` par `save_student_profile`.

Pour les comptes nécessitant une connexion, l'ordre est :

1. créer ou modifier la ligne `public.users` ;
2. attendre sa confirmation ;
3. appeler `invite-school-account` avec `app_user_id` et `email` ;
4. afficher le succès uniquement lorsque `ACCOUNT_INVITED` est reçu.

La création d'un profil sans e-mail peut rester une fiche locale dans `public.users`, mais elle ne doit pas être présentée comme un compte capable de se connecter.

## 5. Tests déjà exécutés

- Appel de l'Edge Function sans JWT : refus HTTP `401`.
- Appel direct des fonctions d'invitation avec le rôle `authenticated` : permission refusée.
- Acteur inexistant : réponse structurée `ACTOR_NOT_FOUND`.
- Création d'un élève sous une session Direction : réussie.
- Modification et relecture de cet élève : réussies.
- Transaction de test annulée : aucune classe et aucun élève temporaire conservés.

## 6. Fichiers associés

- `supabase/functions/invite-school-account/index.ts`
- `supabase/migrations/20260803180800_add_secure_account_invitation_contract.sql`
- `supabase/migrations/20260803182000_add_confirmed_student_save_contract.sql`

Les migrations et la fonction Edge sont déjà appliquées sur le projet Supabase `lcnronymkccgyltttqry`. Les fichiers du dépôt servent de source versionnée et de contrat d'intégration.
