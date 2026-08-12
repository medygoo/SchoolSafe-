# Messages frontend V2 — contrat validé

Date : 12 août 2026

## Décision fonctionnelle verrouillée

- Un parent n’écrit jamais directement à un enseignant.
- Circuit obligatoire : **Parent → Direction 1 / Direction 2 → un seul enseignant concerné → Direction → Parent**.
- Le parent écrit à la Direction ; D1 et D2 doivent être alertées.
- La Direction choisit un seul enseignant correspondant aux enfants/classes du parent et lui transmet le message.
- L’enseignant répond à la Direction, jamais directement au parent.
- La Direction transmet ensuite la réponse au parent.
- Le seul message enseignant directement destiné aux familles est un **message collectif à tous les parents de sa classe**, déjà soumis à approbation D1/D2 avant envoi.
- Direction peut écrire à un parent, tous les parents, les parents d’une classe, un enseignant/tous les enseignants, D2, Caisse et Gardien.
- Ajouter en haut de la page une courte explication adaptée au rôle.
- Remplacer la suppression définitive par l’archivage.
- Préparer la lecture par destinataire au lieu du booléen global `messages.read`.
- Garder le chiffrement existant de `subject` et `body` avant synchronisation.

## Construction effectuée

Fichier : `dist/messages-frontend-v2.js`

Le patch surcharge uniquement la couche frontend existante :

- bloque `parent_direct` et force le routage parent vers la Direction ;
- notifie D1 + D2 pour un message parent ;
- ajoute le panneau **Routage Direction** ;
- ajoute `openForwardParentMessage` / `sendForwardParentMessage` ;
- ajoute `openRelayTeacherMessage` / `sendRelayTeacherMessage` ;
- étend le composer Direction aux parents par classe et aux personnels utiles ;
- remplace l’action de suppression par un archivage local non destructif ;
- introduit un état de lecture local par utilisateur pour ne plus considérer un message collectif comme « lu par tout le monde » dès qu’une seule personne le lit.

## Important — non activé dans `main`

Ce fichier est volontairement isolé sur la branche `chatgpt/messages-frontend-lock`. Il ne modifie ni Supabase, ni RLS, ni RPC, ni migration.

Pour l’activer dans l’application, le chargement suivant devra être ajouté **après le code principal de `dist/index.html`** :

```html
<script src="./messages-frontend-v2.js"></script>
```

Ne pas activer en production tant que les contrôles mobile ne sont pas terminés.

## Backend restant avant garantie complète multi-appareil

Le frontend ne peut pas garantir seul :

1. l’interdiction Parent → Enseignant contre un client ancien ou modifié ;
2. l’archivage persistant et synchronisé entre appareils ;
3. la lecture individuelle durable de chaque destinataire d’un message collectif ;
4. le lien de fil de discussion parent ↔ transmission ↔ réponse enseignant sur plusieurs appareils.

Ces quatre points nécessitent ensuite une évolution serveur/RLS/RPC ou tables associées, avec analyse d’impact et validation explicite avant modification de la base.
