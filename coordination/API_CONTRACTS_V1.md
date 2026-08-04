# SchoolSafe — contrats API v1 vérifiés dans Supabase

**Décision technique de ChatGPT pour intégration par Claude — 3 août 2026**

Ce document répond aux questions ouvertes de la Pull Request nº6. Il décrit ce
qui existe réellement dans le projet Supabase `lcnronymkccgyltttqry` et fixe les
règles que le frontend doit respecter. Aucune modification de schéma ni de
fonction n'a été exécutée pendant cette vérification.

---

## 1. Résultat de la vérification de la base

- `public.exetat` existe et RLS est activé.
- `public.exit_scans` n'existe pas.
- Les entrées, sorties et incidents sont enregistrés dans `public.scan_log`.
- `public.scan_log` contient notamment `sid`, `type`, `status`, `date`, `time`,
  `manual`, `escort_kind`, `escort_id`, `escort_name` et `created_at`.
- Le frontend ne doit donc plus déclarer ni charger une table locale
  `exit_scans`. Il doit utiliser `scan_log` avec le type correspondant.

---

## 2. Contrat `get_gate_access_status(p_sid text)`

### Usage

Contrôle d'accès au portail. Le navigateur ne calcule jamais le solde et ne
reconstruit jamais le statut financier à partir de tables locales.

### Réponse cible stable

La réponse doit toujours garder la même forme, y compris quand l'élève est
introuvable :

```json
{
  "student_id": "string|null",
  "student_name": "string|null",
  "matricule": "string|null",
  "class_id": "string|null",
  "class_name": "string|null",
  "photo_url": "string|null",
  "access_status": "allowed|exception|orient|blocked|unavailable",
  "allowed": true,
  "instruction": "string",
  "checked_at": "ISO-8601 timestamptz"
}
```

### Affichage selon le rôle

- **Direction 1** : peut recevoir le statut complet et consulter le détail dans
  les écrans financiers autorisés.
- **Caisse / Direction 3** : peut recevoir le statut complet et ouvrir le détail
  financier.
- **Gardien** : reçoit uniquement photo, identité, classe, `allowed` et une
  instruction. Aucun montant, aucune devise, aucun trimestre, aucun solde.
- **Direction 2** : aucune donnée financière. Une restriction se présente comme
  une instruction administrative générale.
- **Enseignant** : aucune donnée financière. Une restriction se présente comme
  une instruction administrative générale.
- **Parent** : cette RPC de portail n'est pas son écran financier. Le parent
  utilise `get_parent_fee_summary` pour ses propres enfants.

### Messages autorisés au Gardien, à Direction 2 et à l'Enseignant

```text
allowed      → Accès autorisé
exception    → Accès temporairement autorisé
orient       → Accès autorisé — suivi administratif requis
blocked      → Accès non autorisé — orienter vers la Caisse
unavailable  → Contrôle manuel requis
```

Le serveur ne renvoie jamais de motif financier détaillé à ces trois rôles.

### Cache hors ligne

- Durée maximale : **5 minutes** à partir de `checked_at`.
- Après 5 minutes, le statut n'est plus utilisable.
- L'écran affiche : **« Contrôle manuel requis »**.
- Un statut mis en cache ne doit jamais être transformé ou recalculé côté
  navigateur.
- Les événements déjà scannés peuvent rester dans une file locale en attente de
  synchronisation ; la décision d'accès, elle, expire après 5 minutes.

---

## 3. Contrat `get_parent_fee_summary(p_sid text)`

### Autorisation

- rôle `parent` obligatoire ;
- l'élève doit appartenir au parent connecté ;
- accès parent de l'élève actif ;
- aucun autre élève ne doit être retourné.

### Réponse

```json
{
  "student_found": true,
  "school_year": "string",
  "status": "up_to_date|due_soon|pending|partial|overdue|exception|blocked|unavailable",
  "access_status": "allowed|exception|orient|blocked|unavailable",
  "allowed": true,
  "control_enabled": true,
  "legacy_mode": false,
  "obligation_count": 0,
  "open_obligation_count": 0,
  "overdue_obligation_count": 0,
  "due_soon_obligation_count": 0,
  "next_due_date": "YYYY-MM-DD|null",
  "exception_until": "ISO-8601 timestamptz|null",
  "student_id": "string",
  "student_name": "string",
  "matricule": "string|null",
  "class_id": "string|null",
  "totals_by_currency": [
    {
      "currency": "USD|CDF|autre",
      "amount_due": 0,
      "amount_paid": 0,
      "balance": 0
    }
  ],
  "obligations": [
    {
      "id": "string",
      "fee_type_id": "string|null",
      "label": "string",
      "installment_no": 0,
      "due_date": "YYYY-MM-DD|null",
      "amount_due": 0,
      "amount_paid": 0,
      "balance": 0,
      "currency": "string",
      "status": "paid|partial|pending|overdue"
    }
  ],
  "receipts": [
    {
      "id": "string",
      "receipt_no": "string|null",
      "payment_date": "date-or-timestamp",
      "amount": 0,
      "currency": "string",
      "payment_method": "string|null",
      "external_reference": "string|null",
      "status": "string"
    }
  ]
}
```

Le frontend affiche ces nombres ; il ne les recalcule pas à partir des anciennes
colonnes `paid` par trimestre.

---

## 4. Contrat `get_cashier_student_fee_detail(p_sid text)`

### Autorisation

- Direction 1 (`direction`) ;
- Caisse / Direction 3 (`direction3`).

Direction 2, Gardien, Enseignant et Parent sont refusés.

### Réponse

La forme est identique à `get_parent_fee_summary`, mais l'autorisation dépend du
rôle Caisse/Direction. Le frontend peut ouvrir le détail des obligations,
allocations et reçus sans calculer le solde dans le navigateur.

---

## 5. Chargement des données par rôle

Le `Promise.all` commun qui charge toutes les tables doit être remplacé. Aucun
profil ne doit recevoir les 47 tables de l'école.

| Rôle | Données à charger |
|---|---|
| Direction 1 | tableaux de bord complets autorisés, chargés par modules |
| Direction 2 | pédagogie, élèves, classes, présences et administration non financière |
| Caisse / Direction 3 | élèves, frais, obligations, paiements, reçus et contrôle autorisé |
| Enseignant | ses classes, ses élèves, présences, devoirs, notes et préparations |
| Parent | ses enfants, leurs présences, devoirs, notes, annonces et résumé financier autorisé |
| Gardien | liste minimale de scan, personnes autorisées, événements du jour et instruction d'accès |

Règle : le serveur filtre les lignes et les colonnes avant leur arrivée sur le
téléphone. Masquer une donnée après téléchargement ne constitue pas une
protection.

---

## 6. Point de sécurité à corriger dans le backend

`get_gate_access_status` existe actuellement en `SECURITY DEFINER`. Il contrôle
le rôle via `private.can_scan()`, mais la prochaine migration doit encore :

1. stabiliser la forme de réponse avec tous les champs, même en erreur ;
2. garantir le message générique pour Gardien, Direction 2 et Enseignant ;
3. vérifier et limiter explicitement les droits `EXECUTE` ;
4. conserver `search_path = ''` ;
5. tester chaque rôle avec un élève autorisé, orienté, bloqué et introuvable.

Cette correction sera préparée par ChatGPT sur une branche backend distincte,
puis remise à Claude par Pull Request. Claude fera l'intégration finale, les
tests complets et la publication sur `main` après autorisation de Loms.

---

## 7. Décision immédiate pour Claude

Claude peut dès maintenant :

- supprimer la dépendance frontend à `exit_scans` ;
- utiliser `scan_log` pour les sorties ;
- intégrer les trois RPC selon les formes ci-dessus ;
- appliquer l'expiration de cache de 5 minutes ;
- ne plus calculer les soldes dans le navigateur ;
- ne plus charger les 47 tables pour tous les rôles.

Claude ne doit pas modifier les fonctions, RLS ou migrations Supabase dans sa
branche frontend. Le changement backend arrive dans une Pull Request dédiée de
ChatGPT.
