# Création des profils, personnes autorisées et sortie des élèves — backend servi

Date : 6 août 2026  
Décisions : Loms  
Backend : ChatGPT  
Front-end et recette navigateur : Claude

## État production

Les migrations suivantes sont actives dans Supabase :

- `p0_25_authorized_pickup_identity_contract`
- `p0_26_student_exit_preparation_and_confirmation`
- `p0_27_parent_link_access_and_account_lifecycle`
- `p0_28_profile_creation_role_matrix_and_parent_gate`
- `p0_29_account_invitation_role_matrix_alignment`

Toutes les recettes serveur ont utilisé des transactions avec `ROLLBACK`. Aucune donnée fictive n’est restée.

---

# 1. Matrice définitive de création des profils

## Direction 1

Peut créer et gérer :

- Direction 1 ;
- Direction 2 ;
- Caisse ;
- enseignant ;
- gardien ;
- parent.

## Direction 2

Peut créer et gérer :

- Direction 2 ;
- enseignant ;
- gardien ;
- parent.

Direction 2 ne peut jamais créer ou gérer :

- Direction 1, car ce profil possède une accréditation supérieure ;
- Caisse, car Direction 2 ne gère pas l’argent.

La création et la modification principales passent toujours par :

```text
save_school_user_profile
```

Lorsqu’un parent est créé sans élève lié, la réponse est :

```text
PARENT_PROFILE_CREATED_LINK_REQUIRED
```

Le profil existe, mais :

- `access_ready = false` ;
- `access_block_reason = NO_LINKED_STUDENT` ;
- aucune invitation ne doit partir ;
- aucun code WhatsApp ne doit être préparé ;
- aucune connexion ni session ne fonctionne.

Après le rattachement d’au moins un élève actif, `access_ready` devient automatiquement `true`.

## Modification des informations sensibles

Seule Direction 1 peut modifier :

- l’adresse e-mail ;
- le numéro de téléphone ;
- le rôle.

Direction 2 peut modifier les informations ordinaires autorisées, notamment le nom, les initiales et les photos. Une tentative de modification sensible par Direction 2 renvoie :

```text
DIRECTION1_REQUIRED_FOR_IDENTITY_CHANGE
```

Pour un compte déjà relié à Auth, les changements sensibles utilisent les codes :

- `AUTH_EMAIL_CHANGE_REQUIRED`
- `AUTH_PHONE_CHANGE_REQUIRED`
- `AUTH_ROLE_CHANGE_REQUIRED`

Claude ne doit pas contourner ces refus par une écriture directe.

---

# 2. Parent principal

Chaque élève possède au maximum un seul parent principal dans `students.pid`.

Le rattachement doit désormais passer par :

```text
set_student_primary_parent(p_sid, p_parent_id)
```

Pour retirer le parent principal, envoyer `p_parent_id = null`.

Le changement ne demande ni confirmation particulière ni motif, conformément à la décision de Loms. Le serveur conserve toutefois automatiquement un historique immuable :

- ancien parent ;
- nouveau parent ;
- nom de l’élève ;
- auteur du changement ;
- rôle de l’auteur ;
- date et heure.

Table de lecture :

```text
student_primary_parent_history
```

Ne plus utiliser les `pushSync('students','patch',{pid:...})` groupés du formulaire parent : ils ne sont pas atomiques et peuvent afficher un succès local alors que le serveur a échoué.

## Identité visuelle du parent principal

Avant qu’un parent principal puisse être sélectionné comme personne récupératrice au portail, Direction 1 ou Direction 2 enregistre :

```text
save_primary_parent_pickup_identity
```

Paramètres :

```json
{
  "p_parent_id": "parent_...",
  "p_photo_portrait": "référence R2",
  "p_photo_full_body": "référence R2",
  "p_id_doc_type": "Carte électeur",
  "p_id_doc_last4": "1234"
}
```

Les images doivent être des références de fichiers R2, jamais des données base64.

---

# 3. Trois personnes autorisées sans compte SchoolSafe

Chaque élève peut avoir au maximum trois personnes actives autorisées à le récupérer.

Elles ne possèdent :

- aucun compte SchoolSafe ;
- aucun mot de passe ;
- aucune identité Supabase Auth ;
- aucun accès à l’application.

## Formulaire Claude à créer

Champs obligatoires :

- nom complet ;
- lien avec l’enfant ;
- téléphone ;
- photo portrait ;
- photo verticale en pied ;
- type de pièce d’identité ;
- référence courte de la pièce ;
- date de début ;
- date de fin facultative.

La photo verticale doit montrer la personne debout, de la tête aux pieds, avec les bras et les jambes visibles, sans filtre ni transformation.

Il s’agit d’un contrôle visuel humain, pas d’une reconnaissance faciale automatique.

## RPC

Créer ou modifier :

```text
save_authorized_pickup_person(p_person)
```

Exemple :

```json
{
  "p_person": {
    "id": null,
    "sid": "student_...",
    "name": "Jeanne Exemple",
    "relation": "Tante",
    "phone": "+243810000000",
    "photo_portrait": "référence R2",
    "photo_full_body": "référence R2",
    "id_doc_type": "Carte électeur",
    "id_doc_last4": "1234",
    "valid_from": "2026-08-06",
    "valid_until": null
  }
}
```

Codes principaux :

- `AUTHORIZED_PERSON_CREATED`
- `AUTHORIZED_PERSON_UPDATED`
- `MAX_THREE_AUTHORIZED`
- `VALIDATION_ERROR`
- `STUDENT_NOT_FOUND`

Suspendre ou réactiver :

```text
set_authorized_pickup_person_status
```

Paramètres :

```json
{
  "p_person_id": "aps_...",
  "p_action": "suspend",
  "p_reason": "Motif administratif"
}
```

ou :

```json
{
  "p_person_id": "aps_...",
  "p_action": "reactivate",
  "p_reason": null
}
```

Ne jamais supprimer définitivement une personne déjà utilisée dans un historique de sortie.

## Lecture au portail

Utiliser :

```text
get_student_pickup_context(p_sid)
```

La réponse contient :

- l’élève ;
- le parent principal ;
- jusqu’à trois personnes autorisées actives ;
- les deux photos ;
- la relation ;
- le téléphone selon le rôle ;
- la pièce d’identité ;
- les dates de validité.

---

# 4. Deux systèmes de scan dans le profil enseignant

Claude doit séparer visuellement deux parcours.

## A. Préparer la sortie

Bouton :

```text
Préparer la sortie
```

Appel :

```text
prepare_student_exit
```

Exemple :

```json
{
  "p_sid": "student_...",
  "p_gate_label": "Portail principal",
  "p_manual": false
}
```

Effets serveur :

- vérifie que l’élève est entré ce jour ;
- vérifie qu’un parent principal actif est lié ;
- crée une préparation valable 30 minutes ;
- empêche une deuxième préparation active ;
- avertit immédiatement le parent dans SchoolSafe ;
- place l’e-mail et WhatsApp dans la file d’envoi externe ;
- écrit l’auteur, son nom, son rôle et l’heure.

Message parent :

> Votre enfant est prêt pour la sortie. Vous pouvez venir le récupérer au portail.

Codes principaux :

- `EXIT_PREPARED`
- `EXIT_ALREADY_PREPARED`
- `MISSING_ENTRY`
- `PRIMARY_PARENT_REQUIRED`
- `PRIMARY_PARENT_INACTIVE`
- `ALREADY_EXITED`

L’écran doit afficher :

- statut « En attente de récupération » ;
- compte à rebours de 30 minutes ;
- nom de la personne ayant préparé ;
- état des notifications.

### Important sur les notifications

La notification dans l’application est créée immédiatement.

Les lignes e-mail et WhatsApp sont actuellement placées dans :

```text
private.student_exit_notification_outbox
```

avec le statut `queued`. Le futur dispatcher devra réellement livrer ces messages. Claude ne doit pas afficher « e-mail envoyé » ou « WhatsApp envoyé » tant que le statut n’est pas `sent`.

## B. Confirmer la sortie au portail

Bouton :

```text
Confirmer la sortie
```

Cette fonction est disponible :

- au gardien ;
- à n’importe quel enseignant placé devant le portail ;
- à Direction 1 ;
- à Direction 2.

Elle n’est pas disponible à la Caisse.

### Étape 1 — choix et scan au portail

Après le scan de l’élève, appeler d’abord `get_student_pickup_context`, puis afficher le parent principal et les personnes autorisées avec :

- photo portrait ;
- photo en pied ;
- nom ;
- relation ;
- référence de pièce ;
- validité.

Après sélection de la personne présente, appeler :

```text
scan_student_exit_at_gate
```

Exemple gardien :

```json
{
  "p_sid": "student_...",
  "p_exit_event_id": "exit_...",
  "p_escort_kind": "accredited",
  "p_escort_id": "aps_...",
  "p_gate_label": "Portail principal",
  "p_teacher_gate_reason": null,
  "p_manual": false
}
```

Exemple enseignant remplaçant le gardien :

```json
{
  "p_sid": "student_...",
  "p_exit_event_id": "exit_...",
  "p_escort_kind": "primary",
  "p_escort_id": "parent_...",
  "p_gate_label": "Portail principal",
  "p_teacher_gate_reason": "Gardien absent",
  "p_manual": false
}
```

Lorsque le scanner est enseignant, le motif du poste de sortie est obligatoire. Codes :

- `EXIT_GATE_SCANNED`
- `TEACHER_GATE_REASON_REQUIRED`
- `INVALID_ESCORT`
- `PRIMARY_PARENT_IDENTITY_INCOMPLETE`
- `SELF_EXIT_NOT_ALLOWED`
- `ESCORT_REQUIRED`
- `GATE_REQUIRED`

### Étape 2 — validation finale

Après la comparaison visuelle, afficher deux boutons :

```text
Autoriser la sortie
Refuser la sortie
```

Appeler :

```text
validate_student_exit
```

Autorisation :

```json
{
  "p_exit_event_id": "exit_...",
  "p_decision": "authorized",
  "p_note": null
}
```

Refus :

```json
{
  "p_exit_event_id": "exit_...",
  "p_decision": "refused",
  "p_note": "La personne ne correspond pas aux photos"
}
```

Un motif est obligatoire pour un refus.

Le parent reçoit après validation réelle :

> La sortie de votre enfant a été confirmée à 14 h 05. Il a été récupéré par sa tante autorisée.

Codes :

- `EXIT_CONFIRMED`
- `EXIT_REFUSED`
- `REFUSAL_REASON_REQUIRED`
- `EXIT_NOT_READY_FOR_VALIDATION`
- `ALREADY_EXITED`

## Parcours rapide

Lorsque l’élève n’a pas été préparé en classe, le scan au portail crée automatiquement une préparation puis poursuit la confirmation. Le backend marque alors `quick_flow = true`.

L’ancien appel `record_exit_scan(...)` reste disponible temporairement comme compatibilité, mais Claude doit migrer vers les trois RPC séparées pour afficher correctement les étapes.

---

# 5. Historique complet et immuable

Table principale :

```text
student_exit_events
```

Chaque sortie conserve :

- élève et classe au moment de l’événement ;
- qui a préparé ;
- nom et rôle du préparateur ;
- date et heure ;
- qui a scanné au portail ;
- nom et rôle du scanneur ;
- motif si un enseignant remplace le gardien ;
- qui a validé ;
- nom et rôle du validateur ;
- portail ;
- personne ayant récupéré l’enfant ;
- relation ;
- téléphone ;
- portrait ;
- photo en pied ;
- pièce d’identité ;
- résultat autorisé, refusé, annulé ou expiré ;
- motif et observations.

Les événements finalisés ne peuvent être ni modifiés ni supprimés.

`scan_log` reçoit aussi un instantané complet pour les écrans historiques existants.

Même lorsque l’enseignant prépare, scanne et valide lui-même, les trois actions restent enregistrées séparément.

---

# 6. Annulation et expiration

Annuler une préparation :

```text
cancel_student_exit_preparation
```

Un motif est obligatoire. Un enseignant ne peut annuler que sa propre préparation ; Direction et gardien disposent du contrôle opérationnel selon leurs droits serveur.

Une préparation expire après 30 minutes. Après le scan au portail, une courte fenêtre supplémentaire de validation est accordée.

L’expiration :

- ne marque jamais l’enfant comme sorti ;
- finalise l’événement avec `expired` ;
- informe le parent ;
- permet ensuite une nouvelle préparation.

---

# 7. Gestion du compte dans la liste des profils

Claude doit remplacer l’ancien bouton unique « Suppr. » par :

## Suspendre

Appel :

```text
suspend_school_account(p_app_user_id, p_reason)
```

Le motif est obligatoire.

## Réactiver

Appel :

```text
reactivate_school_account(p_app_user_id)
```

Pour un parent sans enfant lié, la réactivation du profil ne contourne pas la règle : `access_ready` reste faux.

## Retirer l’accès

Appeler l’Edge Function existante :

```text
remove-school-account
```

Elle supprime l’identité Auth et les sessions, mais conserve les historiques scolaires, financiers, fichiers et audits.

---

# 8. Recettes serveur effectuées

## Personnes autorisées

- trois créations acceptées ;
- quatrième refusée ;
- deux photos obligatoires ;
- suspension acceptée ;
- remplacement après suspension accepté ;
- aucune donnée fictive restante.

## Sortie

- préparation enregistrée ;
- notification application immédiate ;
- e-mail et WhatsApp mis en file ;
- enseignant sans motif au portail refusé ;
- enseignant avec motif « Gardien absent » accepté ;
- deux photos de la personne récupératrice présentes ;
- validation finale acceptée ;
- deuxième validation refusée ;
- historique impossible à supprimer ;
- aucune donnée fictive restante.

## Profils et parent

- Direction 2 fictive reliée à une identité Auth fictive ;
- création d’un autre Direction 2 acceptée ;
- création Direction 1 refusée ;
- création Caisse refusée ;
- parent sans enfant créé mais accès fermé ;
- invitation sans enfant refusée ;
- rattachement enfant effectué ;
- invitation et téléphone ensuite acceptés ;
- changement d’e-mail par Direction 2 refusé ;
- changement ordinaire du nom accepté ;
- identité Auth fictive, profils, élèves, invitations et demandes téléphone annulés par `ROLLBACK` ;
- compte Loms Medy resté `direction` et `access_ready = true`.

La recette a découvert une ancienne contrainte qui refusait encore le rôle `direction2` dans les invitations. Elle a été corrigée par `p0_29_account_invitation_role_matrix_alignment` avant de refaire la recette complète.