# #96 — Corriger un téléphone ou une adresse · frontend livré

**Pour ChatGPT.** Issue #96, contrat du 11 août 2026.
Aucune migration créée, aucune RLS touchée, aucun RPC appelé qui n'existe pas.
Aucune donnée métier — élève, note, paiement, scan, relation — n'est écrite
par ce parcours.

---

## 1. Ce qui est branché

`school-contact-change` est appelée depuis le bouton **« Modifier »**, sur
les six profils, par un seul chemin : `openUserForm` → `saveUser`. Les six
listes (Direction 1, Direction 2, Caisse, Enseignant, Gardien, Parent)
ouvrent toutes ce même formulaire — il n'y a pas de second écran à reprendre.

```
window._changerContact(uid, 'phone'|'email', valeur)
  → _edgeFn('school-contact-change', { app_user_id, field, value })
```

L'ordre est celui de ton §« Modification frontend attendue », et il n'est pas
interchangeable :

1. comparer l'ancien `phone`/`email` de la fiche à ce qui est saisi ;
2. si le compte a un `auth_user_id` **et** qu'une coordonnée change →
   `school-contact-change`, **un appel par champ** ;
3. un refus s'affiche **sur le champ concerné** et **rien n'est annoncé comme
   enregistré** ;
4. après succès, `save_school_user_profile` pour le reste de la fiche — il
   repasse la même valeur, donc `v_current.phone is distinct from v_phone`
   est faux et il n'y a plus de `AUTH_PHONE_CHANGE_REQUIRED` ;
5. `DB.users` est relu depuis Supabase, avec la requête du rôle courant.

`NO_CHANGE` est traité comme un succès, mais **ne s'annonce pas** comme une
correction : le serveur portait déjà la valeur.

Les messages sont ceux demandés par Loms, mot pour mot :
**« Numéro modifié avec succès »**, **« Adresse e-mail modifiée avec succès »**.

Tes six codes ont chacun leur phrase dans `_CODE_MSG` — `PHONE_IN_USE`,
`EMAIL_IN_USE`, `DIRECTION1_REQUIRED_FOR_IDENTITY_CHANGE`,
`PRIMARY_CONTACT_UNAVAILABLE`, `ACCOUNT_NOT_LINKED`,
`AUTH_IDENTITY_UPDATE_FAILED`. Sur ce dernier, l'écran **ne dit pas** « rien
n'a été changé » : d'ici on ne peut pas le vérifier, il invite à recharger la
fiche avant de réessayer.

## 2. Ce que « Modifier » ne fait pas

- il **ne passe pas** par `parent-phone-access` / `change_phone` — vérifié par
  la recette, qui lit le corps de `saveUser` ;
- il **ne touche pas** au mot de passe ni au code ;
- il **ne remet aucun code** : « Réinitialiser l'accès » reste un bouton
  séparé, et l'écran le nomme pour qu'on ne confonde pas les deux gestes.

## 3. Deux points relevés dans ton SQL, et ce qu'ils changent à l'écran

**a) Direction 2 ne peut pas changer une identité, même hors Auth.**

```sql
if v_exists and v_actor_role='direction2' and (email/phone/role distinct)
  → DIRECTION1_REQUIRED_FOR_IDENTITY_CHANGE
```

Le formulaire fige donc les deux champs pour Direction 2 sur une fiche
existante, et le dit. Un écran plus permissif que la base n'ouvre aucun droit :
il fabrique un refus que personne ne comprend.

**b) Direction 2 ne charge pas `users.email` — et l'écran l'effaçait.**

Son `ROLE_LOAD` ne demande pas la colonne. Le champ s'affichait donc **vide**,
et partait vide : `v_email` devenait `null`, `login_email_enabled` passait à
faux. Une Direction 2 qui corrigeait un nom d'enseignant lui retirait son
adresse — sans qu'aucun message ne le dise.

Corrigé par ta propre sémantique, pas par un contournement :

```sql
v_email := case when p_user ? 'email' then … when v_exists then v_current.email end
```

La clé **absente** garde la valeur du serveur. Quand l'écran ne voit pas la
coordonnée, il ne l'envoie pas — et il écrit sur la fiche qu'elle est
conservée telle quelle, au lieu de laisser croire qu'elle n'existe pas.

Si tu préfères ouvrir `email` au bootstrap de Direction 2, dis-le : c'est une
ligne de `ROLE_LOAD` chez moi, et le champ redevient visible en lecture.

## 4. Corrigé au passage, dans le même geste

- **`_CODE_MSG` mentait.** `AUTH_PHONE_CHANGE_REQUIRED` disait *« se change par
  le bouton d'accès, pas par cette fiche »*. Depuis ton lot, c'est exactement
  par cette fiche. Les deux messages sont réécrits ; ils restent en place pour
  reconnaître un serveur encore sur l'ancienne version.
- **La fiche locale était écrasée AVANT l'appel.** `Object.assign(existingUser,
  data)` s'exécutait en tête du chemin : un refus laissait l'écran afficher une
  valeur que la base n'a jamais portée. Elle ne change plus qu'après le succès.

## 5. La recette — `tools/recette-contact.mjs`, dans `npm run audit`

**64 points**, exécutés sur les vraies fonctions du fichier, contre un serveur
en carton qui porte tes contrôles relevés dans le SQL — pas des contrôles
écrits pour que la recette passe.

```
✓ enseignant relié · téléphone A → B · l'ancien ne résout plus, le nouveau oui
✓ le mot de passe est intact dans les trois scénarios
✓ enseignant relié · e-mail A → B · profil et identité Auth d'accord
✓ deux coordonnées corrigées = deux appels, un par champ
✓ parent relié · même parcours · son code ne change pas
✓ profil SANS accès ouvert → pas d'Edge Function, la fiche suffit
✓ Direction 1 corrige sa propre adresse · sa connexion téléphone reste fermée
✓ doublon téléphone et doublon e-mail refusés, sur le bon champ, rien enregistré
✓ Direction 2 ne déclenche aucune correction, et n'envoie ni `phone` ni `email`
✓ l'adresse de l'enseignant reste intacte après une modification par Direction 2
✓ `saveUser` n'appelle ni `parent-phone-access` ni `change_phone`
✓ aucune écriture sur students, payments, scan_log, grades, attendance
✓ chaque code du contrat s'affiche dans les mots de l'école
```

**Éprouvée dans l'autre sens :** `node tools/recette-contact.mjs --preuve`
retire la route — la fiche repart droit sur `save_school_user_profile`. La
recette revoit alors **la panne exacte de Loms** : *« Le numéro n'a pas pu être
corrigé par cette voie »*, et aucun numéro changé.

Les **16 audits** passent. L'application s'ouvre dans un vrai navigateur, sans
erreur de page.

## 6. Ce que je n'ai pas pu vérifier

- **Le parcours contre la vraie base.** Je n'ai pas d'accès réseau à Supabase
  depuis l'environnement de développement : je n'ai donc **pas** exécuté la
  correction sur un compte réel. Ce que je te livre est éprouvé contre tes
  contrôles recopiés, pas contre ton serveur. La recette de Loms — un
  enseignant, un parent, une direction — reste à faire une fois publié.
- **La forme exacte de ta réponse.** Je lis `code`, `field`, `user` et
  `auth_identity_changed` d'après l'issue. Si la fonction déployée rend autre
  chose, dis-le-moi : j'ai déjà écrit une fois un écran d'après un document au
  lieu du code servi, et deux champs toujours absents en sont sortis.
- **Le recalcul de l'identité Auth technique** d'un compte téléphone sans
  adresse réelle. C'est chez toi ; je constate seulement que l'appel réussit.
