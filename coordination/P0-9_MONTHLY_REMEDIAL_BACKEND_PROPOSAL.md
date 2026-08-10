# P0-9 — Rattrapages mensuels côté serveur — proposition vérifiée

**État : DRAFT / NON APPLIQUÉ EN PRODUCTION**  
**Responsable backend : ChatGPT**  
**Décisions fonctionnelles : Loms**  
**Frontend : Claude après contrat backend validé**

Ce document formalise le remplacement de la détection locale navigateur par un mécanisme transactionnel, idempotent et exécutable côté serveur.

## 1. Règles fonctionnelles déjà validées

- analyse du **mois civil écoulé**, jamais du mois en cours ;
- analyse **par matière**, pas sur la moyenne générale ;
- minimum de **2 notes** dans la matière sur le mois ;
- seuil par défaut : **50 %** ;
- moyenne pondérée avec `grades.weight`, défaut 1 ;
- si l'élève est sous le seuil dans plusieurs matières : un dossier de rattrapage par matière, mais **une seule convocation familiale pour le mois** ;
- aucun nouveau dossier dans une matière lorsqu'un rattrapage de cette matière est encore ouvert ;
- aucun doublon possible si deux appareils ou deux exécutions lancent la détection ;
- parent averti dans le centre de notifications SchoolSafe ; Direction 1 et Direction 2 reçoivent un résumé ;
- part financière validée : **60 % enseignant / 40 % école** ;
- l'enseignant n'est payé que lorsque la famille a réellement payé ;
- Direction 2 garde le suivi pédagogique mais ne doit pas accéder aux données financières du rattrapage.

## 2. État réel vérifié le 10 août 2026

Lecture seule du Supabase actuel :

- `public.rattrapages` : **0 ligne** ;
- `public.grades` : **0 ligne** ;
- aucune fonction SQL/RPC contenant `rattrapage` ;
- `rattrapages` n'a qu'une clé primaire `id` et un index sur `sid` : **aucune unicité mensuelle** ;
- la RLS de `rattrapages` autorise actuellement les écritures/lectures directes uniquement à Direction 1 ;
- `settings.rattrapage_threshold` existe mais est NULL ;
- `settings.rattrapage_rate` existe comme ancien réglage ;
- **`settings.rattrapage_min_notes` n'existe pas** ;
- **`settings.rattrapage_share_teacher` n'existe pas** ;
- `get_safe_settings()` ne peut donc pas retourner ces deux réglages ;
- `convocations` existe et possède les champs utiles au rattrapage, mais n'a pas de clé de période mensuelle ;
- le centre de notifications `notifs` existe déjà avec déduplication, accusé, archivage et `push_requested`.

Conclusion : le frontend actuel utilise deux réglages qui ne peuvent pas être persistés et sa protection `localStorage` ne protège ni contre un second appareil ni contre une exécution serveur concurrente.

## 3. Contrat de schéma proposé

### `settings`

Ajouter :

- `rattrapage_min_notes integer NOT NULL DEFAULT 2`, borné à une plage raisonnable ;
- `rattrapage_share_teacher numeric(5,2) NOT NULL DEFAULT 60`, borné de 0 à 100 ;
- donner à `rattrapage_threshold` un défaut 50 et une validation 0–100.

`rattrapage_rate` reste temporairement présent pour compatibilité historique mais devient obsolète.

### `rattrapages`

Ajouter la trace serveur :

- `class_id text` ;
- `school_year text` ;
- `period_month date` — toujours le premier jour du mois analysé ;
- `grade_count integer` ;
- `detected_at timestamptz` ;
- `teacher_share_pct numeric(5,2)` — copie du partage applicable au dossier lorsqu'il est financièrement validé ;
- `teacher_share_amount numeric(14,2)` — fixé côté serveur lorsque le paiement est confirmé.

Créer une unicité serveur pour les dossiers automatiques :

`(sid, matière normalisée, period_month)` lorsque `auto_triggered=true`.

Cette unicité est la protection définitive contre deux appareils ou deux exécutions simultanées.

### `convocations`

Ajouter :

- `period_month date` ;
- `school_year text`.

Créer une unicité : une convocation automatique `convoc_type='rattrapage'` par élève et par mois.

## 4. Calcul mensuel serveur

Fonction interne proposée :

`private.detect_monthly_rattrapages(p_period_month date default null)`

Si `p_period_month` est NULL, le serveur prend le **mois précédent** selon le fuseau `Africa/Kinshasa`.

Pour chaque élève non archivé et chaque matière :

1. prendre les notes dont `grades.date` appartient au mois analysé ;
2. ignorer le groupe si le nombre de notes est inférieur à `rattrapage_min_notes` ;
3. calculer le pourcentage de chaque note avec `grades.pct`, ou à défaut `note/max*100` si `max>0` ;
4. calculer la moyenne pondérée `SUM(pct*weight)/SUM(weight)` avec `weight=1` par défaut ;
5. ignorer si moyenne >= seuil ;
6. ignorer si un dossier non archivé et non terminé existe déjà pour le même élève et la même matière ;
7. créer le dossier automatique avec période, moyenne et nombre de notes ;
8. le trimestre et l'année sont dérivés des notes du mois, avec repli sur les réglages actifs ;
9. après toutes les matières, créer/réparer **une seule convocation** pour l'enfant avec la liste des matières faibles ;
10. créer les notifications in-app dédupliquées pour le parent et le résumé Direction 1/Direction 2.

La fonction est transactionnelle et peut être relancée sans créer de doublons.

## 5. Attribution de l'enseignant

Ordre proposé pour déterminer `teacher_id` d'une matière :

1. enseignant ayant effectivement saisi les notes de cette matière sur le mois (`grades.by`) lorsqu'il est identifiable ;
2. à défaut, enseignant déclaré sur l'emploi du temps pour cette classe/matière ;
3. à défaut, titulaire de classe ;
4. à défaut, `classes.teacher_id`.

Le backend doit enregistrer la valeur choisie ; le navigateur ne choisit pas l'auteur du cours automatiquement.

## 6. Notifications

Le calcul crée d'abord l'événement dans SchoolSafe. Les notifications sont stockées dans `notifs` avec une `dedupe_key` mensuelle.

- Parent : catégorie `convocation`, accusé requis, détail sensible uniquement après authentification ;
- Direction 1 / Direction 2 : résumé du mois et de la classe/matière ;
- le transport extérieur n'est pas codé ici : la cible finale est le **Web Push standard VPS** défini dans la coordination canonique ;
- Brevo n'est jamais utilisé pour ces alertes quotidiennes : Brevo reste Auth uniquement.

## 7. Lecture par rôles

Ne pas ouvrir directement `rattrapages` à tous les rôles.

Créer une RPC de lecture filtrée afin de préserver les finances :

- Direction 1 : dossier complet ;
- Direction 2 : informations pédagogiques, **sans montant, paiement, part enseignant** ;
- enseignant : uniquement ses cours assignés, sans données financières du parent ;
- parent : uniquement ses enfants, avec les informations nécessaires à la convocation et au montant à régler ;
- autres rôles : aucun accès sauf contrat explicite futur.

## 8. Réglages — ne plus réécrire toute la table `settings`

Créer une RPC Direction 1 :

`set_rattrapage_settings(p_threshold, p_min_notes, p_teacher_share)`

Elle valide les bornes et modifie uniquement les trois paramètres rattrapage. Claude devra remplacer l'ancien `pushSync('settings','upsert',DB.settings)` pour ce formulaire.

`get_safe_settings()` sera étendu pour retourner les trois valeurs non sensibles.

## 9. Part 60/40 — autorité serveur

Le navigateur ne doit plus être l'autorité de la prime.

Proposition :

- quand Direction 1 valide le montant du cours, le serveur fige `teacher_share_pct` depuis le réglage courant ;
- quand le paiement est réellement confirmé, le serveur calcule `teacher_share_amount = amount * teacher_share_pct / 100` ;
- un changement ultérieur du réglage 60/40 ne modifie donc pas rétroactivement un ancien dossier déjà validé ;
- la paie de l'enseignant lit la valeur serveur, pas un recalcul JavaScript.

## 10. Déclenchement automatique gratuit sur le VPS

Le VPS final pourra lancer la fonction via **systemd timer**, sans service payant et sans dépendre de l'ouverture de l'application.

Le timer peut s'exécuter quotidiennement avec une fonction idempotente : seul le mois précédent est traité et les clés uniques empêchent les doublons. Le calendrier exact sera installé uniquement lors de la phase VPS, après migration et tests.

Pour le développement actuel sur GitHub/Cloud, une RPC Direction 1 contrôlée permettra une exécution manuelle de recette.

## 11. Sécurité / rollback

Avant application :

- aucune donnée actuelle de rattrapage ou note n'est à migrer (tables actuellement vides) ;
- sauvegarde requise avant toute migration production ;
- la migration doit être additive ;
- aucune suppression de colonne historique ;
- rollback fonctionnel possible en désactivant le déclencheur/timer et en revenant à l'ancien parcours pendant les tests ;
- les nouvelles colonnes peuvent rester sans affecter les anciens écrans si le frontend n'est pas encore raccordé.

## 12. État de ce lot

Cette proposition est **préparée mais non appliquée**. La prochaine étape ChatGPT est le SQL de migration sur la branche `chatgpt/p0-9-rattrapages-mensuels`, puis revue avant toute écriture sur la base de production.
