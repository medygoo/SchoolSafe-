# P0-8 — Registre des cartes d'élèves · frontend livré

**Pour ChatGPT.** Issue #63, contrat canonique du 10 août 2026 §5 Lot A.
Aucune migration créée, aucune RLS touchée, aucun RPC appelé qui n'existe pas.

---

## 1. Décisions de Loms qui écartent la matrice de l'issue #63

Deux, et elles sont de lui — 10 août 2026 :

1. **« On fait maternelle et primaire pour la carte. »**
   Le studio proposait encore *Humanités* et *Secondaire*. Retirés de
   `cycleLabel` dans `R.cards`. L'école s'arrête à la 6ᵉ primaire.

2. **« Direction 1 et 2. »**
   L'issue #63 §7 réservait *déclarer perdue* et *révoquer* à Direction 1.
   **Loms a tranché : les deux Directions ont les mêmes droits sur les
   cartes.** Un seul normaliseur porte ce droit, `_peutCarte()` — c'est là
   qu'il faudra le restreindre si tu le juges nécessaire, à un seul endroit.

Les autres rôles sont conformes à ton §7 : gardien = scan seul, enseignant =
lecture de l'état, parent = lecture de la carte de son enfant, caisse = rien.

---

## 2. Ce que j'ai trouvé en ouvrant le code — trois défauts vérifiés

| | |
|---|---|
| Le « duplicata » **n'invalidait rien** | il incrémentait `card_print_count` et réimprimait la même carte. L'ancienne restait valable au portail : une carte perdue dans la rue ouvrait toujours l'école. |
| « Imprimé » était **une bascule** | on pouvait « dé-imprimer ». `card_print_date` s'effaçait avec elle, et rien ne gardait qui avait imprimé. |
| Le QR imprimé **n'était pas signé** | `ssBuildCarte` produisait `schoolsafe://student/<mat>`. Le scanner refuse un QR non signé 30 jours après la pose de `qr_secret` : **toute carte imprimée aujourd'hui aurait affiché « CARTE PÉRIMÉE » au bout d'un mois.** Et un matricule connu suffisait à fabriquer le même QR. |

---

## 3. La table que ton backend doit servir — `public.student_cards`

Une ligne par carte émise. **Jamais de suppression, jamais de réécriture
d'une ligne passée** — seul `status` et le bloc d'invalidation changent.

| colonne | type | rempli par | notes |
|---|---|---|---|
| `id` | uuid/text PK | serveur (défaut) | le navigateur envoie `crt_…` en attendant |
| `sid` | text/uuid FK → `students.id` | navigateur | |
| `year` | text | navigateur | forme `2026-2027` |
| `card_no` | text **unique** | **SERVEUR** | séquence par `year` — voir §5 |
| `class_id` | text/uuid FK → `classes.id` | navigateur | la classe **au moment de l'émission** |
| `class_name` | text | navigateur | figé : une classe renommée ne réécrit pas les cartes passées |
| `status` | text | navigateur | `active` · `remplacee` · `perdue` · `deterioree` · `revoquee` |
| `emission` | text | navigateur | `initiale` · `renouvellement` · `duplicata_perte` · `duplicata_deterioration` · `correction` |
| `motif` | text null | navigateur | **obligatoire** pour les trois derniers types (contrôlé à l'écran) |
| `note` | text null | navigateur | note administrative libre |
| `photo` | text null | navigateur | la photo **réellement imprimée**, figée |
| `qr_payload` | text null | **SERVEUR** | voir §5 |
| `issued_by` | uuid FK → `users.id` | serveur (`auth.uid()`) | ne pas faire confiance au navigateur |
| `issued_by_name` | text | navigateur | libellé d'affichage, pas une preuve |
| `issued_at` | timestamptz | serveur (`now()`) | |
| `print_count` | int | navigateur | 1 à l'émission, +1 à chaque réimpression |
| `replaces` | id null | navigateur | la carte que celle-ci remplace |
| `replaced_by` | id null | navigateur | la carte qui a remplacé celle-ci |
| `invalidated_at` | timestamptz null | serveur | |
| `invalidated_by` | uuid null | serveur | |
| `invalidated_by_name` | text null | navigateur | |
| `invalidated_reason` | text null | navigateur | |

**Invariants que je tiens à l'écran et que le serveur doit tenir aussi** —
un contrôle navigateur n'est pas une sécurité :

1. **Une seule carte `active` par `(sid, year)`.** Index unique partiel.
2. Une ligne dont `status <> 'active'` **ne redevient jamais** `active`.
3. `motif NOT NULL` quand `emission IN ('duplicata_perte',
   'duplicata_deterioration', 'correction')`.
4. Aucun `DELETE` autorisé, pour aucun rôle.
5. L'ancienne carte est invalidée **avant** que la nouvelle soit active —
   une seule transaction, pas deux appels.

---

## 4. Les appels que mon interface attend

Je ne les appelle pas encore : **rien dans le code ne suppose qu'ils
existent.** Aujourd'hui le registre vit dans `DB.student_cards` et part par
`pushSync('student_cards', 'post'|'patch', …)`, comme toutes les autres
tables de l'application. Le jour où tu sers les RPC, je remplace `pushSync`
par ces appels — dis-moi juste que c'est en place.

### `issue_student_card(p_sid, p_year, p_emission, p_motif, p_note, p_photo, p_class_id, p_replaces)`

Un seul appel, **transactionnel**, qui fait les cinq choses ensemble :

```
  1. vérifie le rôle (direction, direction2)
  2. invalide la carte active de (p_sid, p_year), si elle existe,
     avec l'état déduit de p_emission :
        duplicata_perte         → perdue
        duplicata_deterioration → deterioree
        renouvellement          → remplacee
        correction              → remplacee
  3. attribue card_no depuis la séquence de l'année
  4. calcule qr_payload signé (voir §5)
  5. insère la nouvelle ligne en status='active', print_count=1
```

**Retour attendu :** `{ok, data:{id, card_no, qr_payload, issued_at}, code}`.

Codes de refus que l'écran sait déjà nommer — merci de les distinguer, un
seul code pour quatre pannes envoie chercher au mauvais endroit :
`CARD_ROLE_DENIED` · `CARD_STUDENT_NOT_FOUND` · `CARD_INCOMPLETE_FILE` ·
`CARD_MOTIF_REQUIRED` · `CARD_ALREADY_ACTIVE` · `CARD_QR_SECRET_MISSING`.

### `declare_student_card_lost(p_card_id, p_motif)`

Sépare de l'émission : le parent signale la perte aujourd'hui, la nouvelle
carte s'imprime peut-être demain. **Entre les deux, la carte perdue ne doit
plus rien ouvrir.** Passe la carte en `perdue` avec auteur, date et motif.

### `revoke_student_card(p_card_id, p_motif)`

Invalide sans proposer de duplicata — élève parti, carte saisie.

### `count_student_card_print(p_card_id)`

`print_count = print_count + 1`. Appelé **à la réimpression seulement** :
la première impression est comprise dans `issue_student_card`.

### Lecture — les lignes ROLE_LOAD prêtes à poser

Je ne les ai **pas** ajoutées : lire une table absente ferait échouer une
requête à chaque chargement, pour tous les rôles. Elles attendent ton feu
vert.

```js
// direction · module « eleves »
_T('student_cards', 'select=*&order=issued_at.desc')

// direction2 · module « eleves »
_T('student_cards', 'select=*&order=issued_at.desc')

// enseignant · module « eleves » — lecture seule, ses classes via RLS
_T('student_cards', 'select=id,sid,year,card_no,status,emission,issued_at')

// parent · bootstrap — la carte de SES enfants, via RLS
_T('student_cards', 'select=id,sid,year,card_no,status,issued_at')

// gardien — RIEN en direct : il ne tire jamais la table.
// Le contrôle passe par verify_student_card_qr (voir §5).
```

---

## 5. Le QR permanent — le point qui appartient au serveur

**Deux formats, deux durées de vie, et la différence se lit dans le nombre
de segments :**

```
  quotidien   schoolsafe://student/{mat}/{YYYYMMDD}/{sig8}   6 segments
  permanent   schoolsafe://card/{card_no}/{sig8}             5 segments
```

Le permanent ne porte **que le numéro de carte** — ni matricule, ni nom, ni
rien de la famille. C'est le registre qui dit à qui il appartient : donc une
carte perdue cesse d'ouvrir le portail **à la seconde où on la déclare**,
sans qu'on ait à la récupérer.

**Ce que je fais aujourd'hui, et qui doit passer chez toi :** je signe avec
`DB.settings.qr_secret` et `_hmacSign(secret, 'card:' + card_no)`, la même
mécanique que le QR quotidien déjà déployé. Elle a un défaut que tu connais
mieux que moi : **le secret est dans le navigateur.**

Deux demandes, donc :

1. **`qr_payload` calculé côté serveur** dans `issue_student_card`, avec un
   secret que le navigateur ne voit jamais.
2. **`verify_student_card_qr(p_payload)`** pour le gardien, qui rend
   `{ok, student:{id, name, mat, photo, class_name}, refus_code}` — sans
   jamais renvoyer la famille, le solde ou une donnée financière.

En attendant, `_resoudreCarteQR` fait les cinq contrôles **dans le
navigateur** : signature · carte au registre · `status = active` · année en
cours · élève non archivé. Chacun a son propre message à l'écran du gardien
— un « refusé » sans motif ne se dépanne pas.

**Sans `qr_secret` posé, aucun QR n'est imprimé du tout**, et la page
d'impression le dit en clair. Un QR que le portail refusera vaut moins que
pas de QR : il fait croire que la carte fonctionne.

---

## 6. Ce qui est provisoire, et déclaré comme tel

`card_no` est calculé dans le navigateur — `LS-{année}-{séquence}` — et la
ligne porte **`numero_provisoire: true`**. Ce n'est pas un contournement de
ta règle « les numéros sont générés côté serveur » : c'est un état déclaré,
que `issue_student_card` remplacera. Deux appareils hors ligne le même jour
produiraient le même numéro ; c'est exactement pourquoi la séquence
t'appartient.

---

## 7. La recette — `tools/recette-cartes.mjs`, dans `npm run audit`

36 points, exécutés sur les **vraies** fonctions du fichier :

```
✓ l'aperçu n'écrit aucune carte au registre
✓ la carte initiale est émise et active · numéro séquentiel · auteur · photo figée
✓ QR permanent signé, distinct du quotidien (5 segments vs 6)
✓ un duplicata sans motif est refusé, et le champ est désigné
✓ le duplicata devient actif · l'ANCIENNE passe en perdue
✓ l'invalidation garde auteur et motif · l'ancienne pointe vers la nouvelle
✓ rien n'est effacé · une seule carte active par élève et par année
✓ la carte ACTIVE ouvre le portail · la PERDUE est refusée, avec le motif
✓ signature fausse · numéro inconnu · autre année · élève archivé → refusés
✓ la déclaration de perte invalide immédiatement
✓ parent et enseignant ne peuvent rien émettre · Direction 2 le peut
✓ chaque émission et chaque invalidation partent vers student_cards
✓ sans secret posé, aucun QR n'est fabriqué
```

**Éprouvée dans l'autre sens :** `node tools/recette-cartes.mjs --preuve`
retire l'invalidation de l'ancienne carte — la panne exacte d'avant P0-8 —
et **9 points tombent**, dont « l'ANCIENNE carte est invalidée ». Une
recette qui ne sait dire que « oui » ne vérifie rien.

Les **11 audits** passent. L'application s'ouvre dans un vrai navigateur,
sans erreur de page.

---

## 8. Ce que je n'ai pas pu vérifier

- **La base réelle.** Je lis `supabase/vps/baseline/` et `supabase/migrations`,
  pas les données. Tu écris qu'aucun élève ni aucune carte n'existe encore en
  production ; je ne peux pas le confirmer d'ici.
- **Le scan au portail sur un vrai téléphone.** Le décodage et les cinq
  contrôles sont éprouvés en Node ; la caméra, non.
- **Le rendu d'impression sur une imprimante à cartes PVC.** La page s'ouvre
  et se compose ; le résultat physique, je ne le vois pas.
