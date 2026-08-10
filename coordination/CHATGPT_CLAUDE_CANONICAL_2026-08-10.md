# Coordination canonique ChatGPT ↔ Claude — 10 août 2026

Ce document remplace, pour le travail courant, les anciennes consignes devenues contradictoires ou dépassées. Les anciens échanges restent comme historique, mais **Claude et ChatGPT doivent suivre ce document en priorité**.

## 1. Loi de travail

1. Loms décide les règles fonctionnelles.
2. ChatGPT analyse les fonctionnalités, définit le contrat backend/RLS/RPC/sécurité lorsqu'il est nécessaire et audite le résultat.
3. Claude construit le frontend, les boutons, les parcours, les tests navigateur et publie.
4. Pas de double développement de la même fonctionnalité.
5. Une seule tâche active à la fois sur `dist/index.html` pour éviter les conflits.
6. Claude ne contourne jamais un refus serveur par une écriture directe. Toute incompatibilité backend est signalée à ChatGPT.

## 2. Corrections des anciennes consignes

### Authentification

La règle actuelle est : **une adresse e-mail OU un numéro de téléphone suffit** pour un compte SchoolSafe. Les deux peuvent coexister et ouvrent le même compte lorsqu'ils sont présents. Aucun compte parallèle ne doit être créé pour la seconde coordonnée.

Les anciennes consignes imposant `email ET téléphone` sont caduques.

Le compte Direction 1 existant reste valide par e-mail. Ne pas le recréer et ne jamais manipuler manuellement `auth.users.encrypted_password`.

### Brevo

La précédente idée de créer trois comptes Brevo séparés Auth/Arrivées/Sorties est **annulée**.

Architecture retenue :

- **Brevo gratuit : Auth uniquement** — invitation, activation, récupération/changement de mot de passe, changement d'e-mail ;
- aucune notification quotidienne d'arrivée/sortie ne doit consommer le quota Brevo ;
- les secrets SMTP/API restent uniquement côté serveur, jamais dans GitHub ni dans le navigateur.

### Notifications externes

La cible finale n'est plus FCM comme dépendance principale.

Architecture retenue :

- notification **in-app SchoolSafe** : permanente et source de vérité utilisateur ;
- **Web Push standard** (Push API + Service Worker + VAPID) envoyé depuis le VPS : canal externe instantané pour arrivée, retard, préparation de sortie, sortie confirmée/refusée et urgence école ;
- FCM reste seulement un **plan de compatibilité éventuel** si les tests réels prouvent qu'il est nécessaire. Claude ne doit pas construire maintenant un frontend dépendant de Firebase.

Le push n'est jamais la preuve de l'événement. L'événement officiel reste enregistré dans PostgreSQL/SchoolSafe.

### Hébergement frontend

SchoolSafe reste développé et testé sur GitHub pendant toute la construction.

**Ne pas déplacer maintenant le frontend vers le VPS.**

Ordre verrouillé :

1. terminer les fonctionnalités sur GitHub ;
2. tests complets ;
3. validation de Loms ;
4. copie de déploiement du frontend vers le VPS de l'école ;
5. tests VPS ;
6. bascule officielle.

GitHub reste ensuite le dépôt source, l'historique et le point de retour arrière.

Architecture cible : **un VPS SchoolSafe isolé par école**, contenant frontend + Supabase auto-hébergé/PostgreSQL/Auth/RPC/services, mais avec séparation logique des services. Les fichiers lourds restent externalisés selon l'architecture prévue.

## 3. Services externes

Ne pas recréer inutilement les comptes existants :

- Cloudflare R2 : compte/bucket existants à reconnecter au VPS ;
- Backblaze B2 : sauvegardes externes existantes à conserver ;
- Brevo : compte existant à conserver pour Auth ;
- GitHub : dépôt source et développement ;
- aucun nouveau compte externe payant n'est autorisé sans validation explicite de Loms.

## 4. Points backend déjà servis — ne pas les redemander

Les anciennes demandes suivantes sont considérées servies et ne doivent plus être présentées comme blocages :

- P0-1 : auteur réel/horodatage des encaissements ;
- P0-14 : `get_safe_settings()` sécurisé et versionné ;
- P0-11 : conduite séparée par année et trimestre ;
- P0-13 : retrait réel de l'accès Auth sans perte d'historique ;
- P0-24 : une seule coordonnée suffit (`email OU phone`) ;
- backend profils/parent principal/personnes autorisées/sortie en deux étapes ;
- centre de notifications in-app, lecture, accusé, archivage et file privée déjà définis côté backend. Le transport FCM historique sera remplacé/adapté au Web Push lors du lot transport.

## 5. Travail actif — ordre actuel

### Lot A — P0-8 Cartes élèves / duplicatas — CLAUDE ACTIF EN PREMIER

Issue : #63.

Claude doit construire le parcours frontend complet **avant** que ChatGPT crée le backend définitif :

- carte initiale ;
- renouvellement annuel ;
- duplicata perte/détérioration/correction ;
- déclaration de perte ;
- historique annuel ;
- aperçu avant impression ;
- confirmation d'impression ;
- états active/remplacée/perdue/détériorée/révoquée ;
- QR permanent distinct du QR quotidien ;
- écrans selon les rôles.

Claude doit rendre à ChatGPT les appels exacts qu'il propose et la recette navigateur. **Aucune migration P0-8 à inventer côté frontend.**

### Lot B — P0-9 Rattrapages mensuels — CHATGPT ACTIF EN PARALLÈLE

ChatGPT analyse maintenant la structure existante et prépare le contrat serveur transactionnel :

- analyse du mois écoulé ;
- seuil configurable ;
- minimum de notes configurable ;
- unicité élève + matière + mois ;
- pas de doublon multi-appareil ;
- création du dossier de rattrapage ;
- notification/convocation in-app ;
- règles financières 60 % enseignant / 40 % école selon la décision existante ;
- aucune migration de production avant revue du contrat et validation de Loms.

### File suivante

Après P0-8 :

- Claude intègre complètement #64 (profils, parent principal, personnes autorisées, sortie en deux étapes, suspendre/réactiver/retirer accès) sur le backend déjà servi ;
- le centre notifications #66 est conservé côté interface/in-app, mais **le service worker Firebase ne doit plus être développé comme cible finale**. Il sera réécrit en Web Push standard selon le contrat transport à venir.

## 6. VPS

Le baseline VPS peut continuer à être préparé côté backend/infrastructure, mais **aucun basculement frontend avant la fin fonctionnelle de l'application**.

Chaque future école réutilisera le déploiement SchoolSafe validé comme modèle durci, avec son propre VPS isolé.

## 7. Règle de priorité

En cas de contradiction entre un ancien commentaire/issue et ce document, **ce document du 10 août 2026 prévaut**, sauf décision ultérieure explicite de Loms.
