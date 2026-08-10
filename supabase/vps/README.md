# SchoolSafe - Migration vers Supabase auto-heberge sur VPS

## Decision verrouillee

Le backend cible de SchoolSafe est le Supabase auto-heberge deja installe sur le VPS SchoolSafe.
L'ancien Supabase Cloud reste temporairement une reference et un retour arriere jusqu'a validation complete du VPS.

Aucun basculement frontend ne doit etre effectue avant validation du backend VPS.

## Source de verite actuelle

La base Cloud actuelle contient :

- 66 tables dans `public` ;
- 8 tables dans `private` ;
- 74 tables applicatives au total ;
- environ 130 fonctions `public` + `private` ;
- 28 triggers applicatifs ;
- 112 migrations historiques enregistrees ;
- RLS active sur les 66 tables `public`.

Important : la premiere migration historique enregistree ne correspond pas a la creation initiale complete de SchoolSafe. Plusieurs tables existaient deja avant le debut de cet historique. Il est donc interdit de supposer qu'un VPS vide peut etre reconstruit uniquement en rejouant les 112 migrations historiques.

## Strategie retenue : CURRENT-STATE BASELINE

Nous construisons un baseline SQL correspondant a l'etat final actuel de la base Cloud, puis le VPS commence son nouvel historique de migrations a partir de ce baseline.

Ordre du baseline :

1. precheck VPS en lecture seule ;
2. schemas applicatifs et extensions indispensables ;
3. tables `public` et `private` sans toucher aux schemas internes Supabase ;
4. fonctions/RPC `public` et `private` ;
5. defaults ;
6. contraintes PK/UNIQUE/CHECK ;
7. foreign keys, y compris les liens autorises vers `auth.users` ;
8. indexes ;
9. triggers ;
10. RLS et policies ;
11. grants/revokes et commentaires de securite ;
12. seed/configuration SchoolSafe non sensible ;
13. creation/reliaison controlee de Direction 1 dans Auth VPS ;
14. Edge Functions ;
15. secrets serveur ;
16. tests ;
17. basculement du frontend.

## Ce qui NE DOIT PAS etre copie depuis Supabase Cloud

Ne jamais restaurer aveuglement les schemas internes `auth`, `storage`, `realtime` ou les migrations internes de ces services par-dessus l'installation auto-hebergee.

Le VPS garde ses propres schemas internes Supabase correspondant a ses versions Docker.

Ne jamais copier manuellement `auth.users.encrypted_password`.

Ne jamais mettre dans GitHub :

- service_role ;
- JWT secret ;
- mot de passe PostgreSQL ;
- cles R2 ;
- mot de passe SMTP/Brevo ;
- cles Firebase/FCM ;
- bearer token du Control API.

## Authentification cible

SchoolSafe conserve le meme principe fonctionnel :

- connexion par e-mail + mot de passe ;
- connexion par telephone + code/mot de passe SchoolSafe via le relais serveur ;
- un profil = un compte Auth ;
- le telephone n'exige pas Twilio/SMS pour le login SchoolSafe ;
- Brevo SMTP sera reconnecte au VPS pour les e-mails Auth.

Direction 1 doit etre preservee comme compte metier unique. Sa reliaison Auth VPS sera traitee separement apres installation du schema. Aucun hash de mot de passe ne sera ecrit manuellement.

## Routage Brevo valide

La decision fonctionnelle est verrouillee :

- compte Brevo 1 : Authentification uniquement ;
- compte Brevo 2 : notifications Arrivees ;
- compte Brevo 3 : notifications Sorties ;
- urgences : notification permanente dans SchoolSafe + utilisation controlee du canal e-mail externe disponible ;
- autres informations ordinaires : principalement dans le centre de notifications SchoolSafe.

Les notifications in-app restent la source principale et permanente. Un e-mail externe ne doit jamais bloquer un scan, une entree, une sortie ou une notification interne.

## R2 / fichiers

Cloudflare R2 reste le stockage des fichiers lourds. Le VPS stocke les metadonnees et les references R2, pas les images/PDF en base PostgreSQL.

Les fonctions R2 devront etre redeployees sur le runtime Edge Functions du VPS avec leurs secrets dans l'environnement serveur.

## Edge Functions indispensables a redeployer

Au minimum :

- `school-login` ;
- `invite-school-account` ;
- `parent-phone-access` ;
- `remove-school-account` ;
- `r2-files` ;
- `dispatch-school-push`.

Les fonctions de diagnostic/test historiques ne sont pas automatiquement considerees comme necessaires en production.

## Regle de securite

Avant toute ecriture sur le VPS :

1. executer `00_PRECHECK_READONLY.sql` ;
2. creer une sauvegarde PostgreSQL VPS fraiche ;
3. verifier l'integrite gzip ;
4. verifier la copie B2 ;
5. confirmer les versions et extensions ;
6. obtenir validation explicite avant l'import du baseline.

## Rollback

Tant que le basculement frontend n'est pas valide, l'application reste sur l'ancien backend Cloud et il n'y a pas d'interruption utilisateur.

Apres basculement, le retour arriere consiste a restaurer la configuration frontend Cloud tant que l'ancien projet est conserve intact.
