# P0-9 — Rattrapages v2 : finance et lectures par rôle

Statut : **DRAFT / NON DÉPLOYÉ**.

Ce complément part d'un audit en lecture seule du Supabase réel du 11 août 2026. Il complète `P0-9_MONTHLY_REMEDIAL_BACKEND_PROPOSAL.md` sans toucher à la production.

## Décision d'architecture

Un rattrapage ne crée pas un deuxième système d'encaissement.

Il utilise le système financier SchoolSafe déjà sécurisé :

`rattrapage -> student_fee_obligations -> payment_allocations -> payment_transactions`

Conséquences :

- la Caisse conserve `record_payment_transaction()` et le reçu séquentiel existant ;
- l'auteur de l'encaissement reste figé côté serveur ;
- la contrepassation existante reste la source de vérité ;
- le booléen historique `rattrapages.paid` devient un miroir calculé du ledger, jamais une saisie navigateur ;
- la prime enseignant n'est acquise que lorsque l'obligation de rattrapage est entièrement couverte par des transactions `confirmed`.

## Pourquoi une obligation spéciale

La fonction actuelle `record_payment_transaction()` répartit automatiquement un paiement sans allocations explicites sur toutes les obligations actives du même élève/devise.

Pour éviter qu'un paiement de minerval soit absorbé accidentellement par un rattrapage, on ajoute à `student_fee_obligations` :

`manual_allocation_only boolean NOT NULL DEFAULT false`.

Les obligations de rattrapage portent `manual_allocation_only=true`.

Le chemin automatique ignore ces obligations. Le chemin avec `p_allocations` explicite continue de les accepter.

## Termes financiers du rattrapage

Direction 1 fixe le montant via :

`set_rattrapage_financial_terms(p_rattrapage_id, p_amount, p_currency, p_due_date)`

La fonction :

- refuse les autres rôles ;
- exige un dossier réel, non archivé et un enseignant actif ;
- refuse de modifier le prix si un paiement confirmé a déjà commencé ;
- fige le pourcentage enseignant depuis `settings.rattrapage_share_teacher` ;
- crée ou met à jour une obligation `ft_rattrapage` liée au dossier ;
- ne marque jamais le dossier payé elle-même.

## Réconciliation du paiement

Le serveur recalcule le paiement à partir des allocations confirmées.

- paiement partiel : `paid=false`, aucune prime enseignant acquise ;
- paiement complet : `paid=true`, `payment_completed_at` fixé et `teacher_share_amount = amount * teacher_share_pct / 100` ;
- contrepassation qui ramène le total sous le montant dû : `paid=false` et `teacher_share_amount=NULL`.

À ce stade P0-9, `teacher_share_amount` signifie **prime acquise / payable**, pas « salaire déjà versé ». Le règlement effectif dans `salaries` sera raccordé dans le lot Personnel/Salaires afin de ne pas mélanger deux fonctionnalités.

## Lecture par rôle

La table `rattrapages` reste fermée directement aux autres rôles. La lecture passe par `get_rattrapage_center(...)`.

- Direction 1 : pédagogique + paiement + part 60/40 ;
- Direction 2 : pédagogique uniquement, aucun montant, aucune devise, aucun état financier ;
- Enseignant : uniquement ses dossiers attribués, pédagogique uniquement ;
- Parent : uniquement ses enfants, montant à régler et état payé, jamais la part enseignant ;
- Caisse : informations minimales d'encaissement, sans la part enseignant ;
- Gardien : aucun accès.

## Réglages

`get_rattrapage_settings()` devient la lecture dédiée au module.

- seuil et nombre minimum de notes : Direction 1, Direction 2, Enseignant ;
- partage enseignant : Direction 1 uniquement.

Le legacy `rattrapage_rate` présent dans `get_safe_settings()` est financier. Lors de la consolidation finale avec le lot Web Push, il devra être masqué aux rôles non financiers. Cette branche ne doit pas écraser la version concurrente de `get_safe_settings()` préparée pour Web Push.

## Contrat frontend Claude

1. Ne jamais écrire directement `rattrapages.paid`, `amount`, `teacher_share_pct` ou `teacher_share_amount`.
2. Direction 1 fixe le prix par `set_rattrapage_financial_terms`.
3. La Caisse récupère `fee_obligation_id` via `get_rattrapage_center` puis appelle `record_payment_transaction` avec une allocation explicite vers cette obligation.
4. Après paiement ou contrepassation, recharger `get_rattrapage_center` ; ne pas modifier le miroir local avant succès serveur.
5. Direction 2 et Enseignant ne doivent jamais recevoir les champs financiers.
6. Le Parent peut voir son montant et son statut, mais jamais le pourcentage ou la prime de l'enseignant.

## Sécurité / rollback

- nouveau SQL uniquement dans `supabase/drafts/` ;
- `ROLLBACK` final volontaire ;
- aucune donnée réelle modifiée ;
- aucune migration de production ;
- aucun VPS modifié ;
- le modèle est additif et peut rester dormant tant que Claude n'a pas raccordé le frontend.
