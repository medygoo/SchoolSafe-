# P0-9 — Rattrapages mensuels : contrat backend propre pour Claude

> Branche ChatGPT : `chatgpt/p0-9-rattrapages-clean`
> Statut : **DRAFT — aucune production modifiée**.
> Cette version remplace la PR brouillon #71 après réaudit du Supabase réel et du frontend Claude.

## 1. Règles fonctionnelles conservées

- La détection porte sur le **mois civil écoulé**, jamais le mois en cours.
- Elle travaille **par matière**.
- Minimum configurable : **2 notes** par défaut.
- Seuil configurable : **50 %** par défaut.
- Moyenne pondérée selon `grades.weight` et `grades.pct` / `note/max`.
- Un dossier automatique unique par **élève + matière + mois**.
- Plusieurs matières faibles = plusieurs dossiers pédagogiques, mais **une seule convocation familiale par élève/mois** qui agrège les matières.
- Direction 1 et Direction 2 sont informées. Le Parent reçoit la convocation.
- Le Parent ne déclare jamais lui-même avoir payé.
- Direction 1 organise le cours et les conditions financières.
- Direction 2 reste pédagogique et ne reçoit **aucune donnée financière**.
- Caisse encaisse, mais ne reçoit jamais la part enseignant.
- Part par défaut : **60 % enseignant / 40 % école**.
- Cette part est figée au moment où Direction 1 fixe les conditions financières.
- La part enseignant n'est **acquise** qu'après paiement complet confirmé.
- Une contrepassation qui fait repasser le total sous le montant dû retire automatiquement `paid=true` et le montant acquis.

## 2. Différences importantes avec l'ancien brouillon #71

1. La branche repart du `main` courant : aucun ancien code frontend ou Sortie n'est transporté.
2. L'anti-doublon est réellement **mensuel**. Un dossier non terminé en janvier ne bloque pas à lui seul la détection pédagogique de février.
3. `run_monthly_rattrapage_detection()` refuse le mois courant ou futur (`PERIOD_NOT_COMPLETE`).
4. Les matières sont normalisées en minuscules pour l'unicité tout en conservant un libellé d'affichage.
5. Le paiement général garde son contrat P0-1 mais :
   - ignore les obligations `manual_allocation_only=true` en auto-allocation ;
   - verrouille une obligation avant allocation explicite ;
   - interdit la sur-allocation.
6. Les obligations de rattrapage reçoivent un `installment_no` séquentiel sous verrou transactionnel ; l'unicité réelle `(sid, fee_type_id, school_year, installment_no)` est respectée.
7. Aucun calcul officiel 60/40 n'est laissé au JavaScript.
8. Le montant acquis enseignant reste une **créance calculée du rattrapage**, pas un paiement de salaire. Le transfert vers `salaries/direct_primes` reste au lot Personnel/Salaires afin d'éviter un double paiement.
9. Les lectures passent par `get_rattrapage_center()` et non par un SELECT identique pour tous les rôles.
10. Le cycle pédagogique dispose de RPC dédiées ; le frontend n'a plus besoin de patcher directement `rattrapages`.

## 3. RPC du contrat final

### Réglages

- `get_rattrapage_settings()`
- `set_rattrapage_settings(p_threshold, p_min_notes, p_teacher_share)` — Direction 1.

### Détection

- `run_monthly_rattrapage_detection(p_period_month)` — Direction 1 pour recette/manuelle.
- `private.detect_monthly_rattrapages(p_period_month)` — future exécution automatique VPS/service role.

### Cycle du dossier

- `validate_rattrapage(p_rattrapage_id, p_decision, p_note)` — Direction 1 ou Direction 2 ; `approved|refused`.
- `assign_rattrapage_teacher(p_rattrapage_id, p_teacher_id)` — Direction 1.
- `schedule_rattrapage_session(p_rattrapage_id, p_session_date, p_session_time, p_session_place)` — Direction 1, après paiement complet.
- `mark_rattrapage_done(p_rattrapage_id, p_note)` — Direction 1 ou enseignant affecté, après paiement + planification.
- `archive_rattrapage(p_rattrapage_id, p_reason)` — Direction 1, uniquement dossier refusé ou effectué.

### Finance

- `set_rattrapage_financial_terms(p_rattrapage_id, p_amount, p_currency, p_due_date)` — Direction 1.
- `record_payment_transaction(...)` reste le ledger officiel ; pour un rattrapage, Claude doit fournir explicitement :

```js
p_allocations: [{ obligation_id: item.fee_obligation_id, amount: montant }]
```

- `reverse_payment_transaction(...)` reste la contrepassation officielle.

### Lecture

- `get_rattrapage_center(p_sid, p_period_month)`.

Données par rôle :

- **Direction 1** : pédagogique + montant + paiement + 60/40.
- **Direction 2** : pédagogique uniquement, zéro montant/devise/paiement/part.
- **Enseignant** : uniquement ses dossiers, pédagogique uniquement.
- **Parent** : uniquement ses enfants ; montant + payé/non payé, jamais le partage interne.
- **Caisse** (`direction3` serveur) : montant, devise, solde/obligation et état payé ; jamais la part enseignant.
- **Gardien** : aucun accès.

## 4. Ce que Claude doit remplacer dans le frontend

Quand ce contrat sera validé puis réellement déployé/testé :

1. La détection `checkRattrapageAuto` ne doit plus créer les dossiers/convocations depuis le navigateur. Elle peut devenir un affichage ou un bouton Direction 1 de recette vers `run_monthly_rattrapage_detection`.
2. Toutes les lectures de dossiers passent par `get_rattrapage_center`.
3. Ne plus faire de `pushSync('rattrapages','patch'|'post',...)` pour : validation, enseignant, montant, paiement, planification, effectué, archivage.
4. Direction 2 ne reçoit jamais `amount`, `currency`, `paid`, `fee_obligation_id`, `teacher_share_*`.
5. Le Parent n'a aucun bouton « signaler mon paiement ».
6. La Caisse utilise le même reçu/contrepassation P0-1 que les autres frais, avec allocation explicite vers l'obligation rattrapage.
7. Après paiement ou contrepassation : recharger le centre depuis le serveur avant d'afficher succès/état.
8. La paie enseignant doit lire plus tard le montant acquis serveur (`teacher_share_amount`) plutôt que recalculer `amount * DB.settings.rattrapage_share_teacher` dans le navigateur.

## 5. Notifications

La détection insère dans `public.notifs` avec `dedupe_key`. Les triggers actuels `notifs_stamp_metadata` et `notifs_queue_push` restent responsables du centre in-app et de la mise en file Push. Aucun e-mail/WhatsApp n'est ajouté.

## 6. Déploiement

Les SQL restent sous `supabase/drafts/` et finissent par `ROLLBACK`.

Le timer mensuel `systemd` sera créé **uniquement lors de la phase VPS**, après fin du frontend SchoolSafe, tests complets et accord explicite de Loms. Il appellera la fonction interne avec service role ; il ne dépendra d'aucun navigateur.
