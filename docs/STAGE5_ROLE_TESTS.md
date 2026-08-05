# Étape 5 — Tests de rôles

Date : 2026-08-03

## Répartition domaine et design

- Claude : design du site et de l’application, écrans, navigation, boutons et liens visibles.
- ChatGPT : configuration technique du domaine, DNS Cloudflare, HTTPS, sous-domaines, redirections et validation de disponibilité.

## Inventaire initial

Le projet contenait au début du contrôle :

- 1 compte Auth actif ;
- rôle Direction 1 ;
- 0 élève réel ;
- 0 compte Direction 2, Caisse, Enseignant, Parent ou Gardien disponible pour un test HTTP authentifié.

## Matrice RLS transactionnelle

Une matrice temporaire avec deux classes et deux élèves a été exécutée avec `ROLLBACK`.

Résultats attendus confirmés sur :

- Direction 1 : accès complet ;
- Direction 2 : pédagogique et administratif non financier ;
- Caisse : finances ;
- Enseignant : sa classe et ses préparations ;
- Parent : son enfant ;
- Gardien : données de scanner autorisées ;
- accès SQL direct à `school_files` : Direction 1 uniquement.

## Défaut découvert et corrigé

`private.owns_student(p_sid)` vérifiait le lien `students.pid`, mais ne vérifiait pas explicitement le rôle Parent.

Dans une affectation incorrecte, un autre rôle portant le même identifiant pouvait hériter d'une branche d'accès Parent sur plusieurs politiques.

Migration appliquée :

- `20260803110748_scope_student_ownership_to_parent_role`

La fonction exige maintenant :

- rôle courant `parent` ;
- élève appartenant au compte ;
- élève non archivé ;
- accès Parent actif.

Cette correction protège notamment paiements, allocations, obligations, exceptions, présences, notes, conduite et historiques utilisant `private.owns_student()`.

## Nettoyage

Après contrôle :

- 0 invitation temporaire Stage 5 ;
- 0 compte Auth temporaire ;
- 0 profil temporaire ;
- 0 utilisateur applicatif temporaire ;
- aucune donnée de test persistante.

## Restant dans l'étape 5

- créer des sessions Auth temporaires contrôlées pour chaque rôle ;
- tester réellement les Edge Functions par HTTP avec JWT ;
- cycle Direction 1 : upload, list, download, delete ;
- vérifier les refus Direction 2, Caisse, Enseignant, Parent et Gardien ;
- supprimer les comptes et objets après les tests.
