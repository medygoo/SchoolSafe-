# Messages frontend V2 — contrat validé

Date : 12 août 2026

## Décision fonctionnelle verrouillée

- Un parent n’écrit jamais directement à un enseignant.
- Circuit obligatoire : **Parent → Direction 1 / Direction 2 → un seul enseignant concerné → Direction → Parent**.
- Le parent écrit à la Direction ; D1 et D2 doivent être alertées.
- La Direction choisit un seul enseignant correspondant aux enfants/classes du parent et lui transmet le message.
- L’enseignant répond à la Direction, jamais directement au parent.
- La Direction transmet ensuite la réponse au parent.
- Le seul message enseignant directement destiné aux familles est un **message collectif à tous les parents de sa classe**, soumis à approbation D1/D2 avant envoi.
- Direction peut écrire à un parent, tous les parents, les parents d’une classe, un enseignant/tous les enseignants, D2, Caisse et Gardien.
- Ajouter en haut de la page une courte explication adaptée au rôle.
- Remplacer la suppression définitive par l’archivage.
- Préparer la lecture par destinataire au lieu du booléen global `messages.read`.
- Garder le chiffrement existant de `subject` et `body` avant synchronisation.

## Construction effectuée

Fichier principal : `dist/messages-frontend-v2.js`.

Le patch frontend :

- bloque l’ancien chemin `parent_direct` et force le routage parent vers la Direction ;
- notifie D1 + D2 pour un message parent ;
- ajoute le panneau **Routage Direction** ;
- ajoute `openForwardParentMessage` / `sendForwardParentMessage` ;
- ajoute `openRelayTeacherMessage` / `sendRelayTeacherMessage` ;
- étend le composer Direction aux parents par classe et aux personnels utiles ;
- remplace l’action de suppression par un archivage local non destructif ;
- introduit un état de lecture local par utilisateur pour éviter qu’un message collectif devienne « lu par tout le monde » après une seule lecture ;
- délègue les fonctions enseignant déjà existantes au code historique afin de conserver le message collectif soumis à approbation ;
- conserve le chiffrement existant avant synchronisation.

## Intégration sur la branche de recette

La branche `chatgpt/messages-frontend-lock` charge maintenant V2 une seule fois, à la vraie fin du document principal :

```html
<script src="messages-frontend-v2.js?v=20260812" defer></script>
</body>
</html>
```

Un premier automatisme avait ciblé par erreur un `</body>` contenu dans une chaîne d’impression. Cette insertion n’a pas été publiée : elle a été détectée dans la recette puis corrigée. Le branchement final utilise bien le dernier `</body>` réel de `dist/index.html`.

La recette GitHub du branchement final (run `31570171486`) a validé :

- syntaxe JavaScript ;
- présence unique du loader ;
- position du loader juste avant le `</body>` final ;
- présence des chemins Parent → Direction, Direction → enseignant et Direction → Parent ;
- délégation au comportement enseignant existant.

Le workflow temporaire utilisé pour modifier le grand fichier `dist/index.html` a ensuite été supprimé de la branche afin qu’il ne soit jamais fusionné dans `main`.

Une recette durable, sans réseau ni modification de données, est conservée dans `tools/recette-messages-v2.mjs`.

## Statut de publication

**`main` et la production ne sont pas modifiés par cette branche tant que la PR #111 n’est pas fusionnée.**

Le frontend V2 est donc construit, branché et contrôlé sur la branche de recette, mais il n’est pas encore déclaré comme garantie serveur complète.

## Backend restant avant garantie complète multi-appareil

Le frontend ne peut pas garantir seul :

1. l’interdiction Parent → Enseignant contre un client ancien ou modifié ;
2. l’archivage persistant et synchronisé entre appareils ;
3. la lecture individuelle durable de chaque destinataire d’un message collectif ;
4. le lien de fil de discussion parent ↔ transmission ↔ réponse enseignant sur plusieurs appareils.

Ces quatre points nécessitent ensuite une évolution serveur/RLS/RPC ou tables associées, avec analyse d’impact et validation explicite avant modification de la base.
