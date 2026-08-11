# Inscription élève — contrat backend propre pour Claude

> Suivi : #89  
> Branche ChatGPT : `chatgpt/student-registration-clean`  
> Statut : **DRAFT — aucune production modifiée**.

## 1. Audit réel du 11 août 2026

Le parcours manuel et la préinscription ne produisent pas encore le même dossier.

### Création manuelle actuelle

`save_student_profile(p_student jsonb)` est réellement déployée et autorise Direction 1 / Direction 2. Elle valide nom, classe, matricule, parent, photo-référence et autorisation de sortie seule, puis renvoie la ligne PostgreSQL.

Mais elle :

- exige encore un `id` fabriqué par le navigateur ;
- accepte encore `mat` et `num_inscription` venant du navigateur ;
- ne persiste pas `sexe`, `ecole_provenance`, `tutelle_principale` ;
- ne crée pas les obligations financières configurées ;
- ne produit pas d'audit métier explicite de création/modification.

### Préinscription actuelle

`validate_preinscription_email(...)` utilise déjà :

- `private.school_counters('student_mat:' || année)` ;
- ID serveur `student_<uuid>` ;
- matricule serveur `LS-<année>-<6 chiffres>` ;
- numéro d'inscription `INS-<année>-<6 chiffres>` ;
- `sexe`, `ecole_provenance`, `tutelle_principale` ;
- création des obligations actives dont le montant est > 0 ;
- audit serveur.

Le contrat final doit donc aligner la création manuelle sur ces invariants, pas créer un deuxième système.

## 2. Contrat cible de `save_student_profile`

La signature reste :

```sql
save_student_profile(p_student jsonb) returns jsonb
```

### Création

Le navigateur **n'est plus l'autorité** de :

- `id` ;
- `mat` ;
- `num_inscription` ;
- `created_by` / `created_by_name` / `created_at`.

Pour une création, Claude envoie `id: null` ou omet `id`. Le serveur :

1. détermine l'année scolaire ;
2. incrémente atomiquement `private.school_counters` ;
3. crée l'ID ;
4. crée le matricule ;
5. crée le numéro d'inscription ;
6. insère la fiche ;
7. crée les obligations financières configurées ;
8. écrit l'audit ;
9. renvoie **la ligne serveur** et le nombre d'obligations créées.

### Modification

Pour une modification, `id` est obligatoire et doit déjà exister.

`mat` et `num_inscription` sont immuables : les renvoyer avec la même valeur est toléré pour compatibilité ; tenter de les changer renvoie `IMMUTABLE_STUDENT_NUMBER`.

Les clés absentes du JSON **conservent la valeur serveur**. Le formulaire ne doit jamais réécrire une valeur qu'il ne gère pas avec une vieille copie locale.

### Champs pédagogiques / identité pris en charge

- `name`
- `cid`
- `dob`
- `lieu_naissance`
- `sexe`
- `ecole_provenance`
- `nom_papa`
- `nom_maman`
- `adresse`
- `tutelle_principale`

Le parent principal est un cas séparé :

- création initiale : `pid` peut être fourni ;
- changement ultérieur : Claude appelle `set_student_primary_parent(p_sid,p_parent_id)` pour rendre l'intention explicite et exploiter l'audit dédié.

## 3. Numéros et contraintes serveur

Préparer :

- unicité de `lower(btrim(mat))` quand non NULL ;
- unicité de `lower(btrim(num_inscription))` quand non NULL ;
- FK `cid -> classes(id)` avec `ON DELETE RESTRICT` ;
- FK `pid -> users(id)` avec `ON DELETE RESTRICT` ;
- FK `created_by -> users(id)` avec `ON DELETE SET NULL` ;
- FK `leave_alone_authorized_by -> users(id)` avec `ON DELETE SET NULL`.

Aucune suppression physique d'un élève depuis le navigateur.

## 4. Frais scolaires

Le serveur possède déjà 9 `fee_types`, tous actifs mais actuellement à `montant_defaut=0`. Il n'existe donc encore aucune obligation financière réelle à créer aujourd'hui.

Le helper proposé `private.ensure_student_fee_obligations(...)` :

- lit l'année serveur ;
- crée uniquement les types actifs dont `montant_defaut > 0` ;
- respecte l'unicité `(sid, fee_type_id, school_year, installment_no)` ;
- est idempotent (`ON CONFLICT DO NOTHING`).

Ainsi, dès que la Direction configurera les montants, un élève créé manuellement et un élève issu d'une préinscription auront le même dossier financier.

## 5. Photo élève + R2

Le stockage R2 actuel exige que `owner_type=student` existe déjà. Une création avec photo doit donc être **en deux temps** :

1. `save_student_profile({ ...sans photo... })` -> succès + `student.id` serveur ;
2. `r2-upload` avec :
   - `owner_type=student`
   - `owner_id=<student.id>`
   - `category=photo`
3. conserver `file.id` UUID renvoyé ;
4. `set_student_photo_file(p_sid,p_file_id)` ;
5. recharger la fiche depuis le serveur.

Une URL signée R2 expire après 300 secondes : elle n'est **jamais** enregistrée comme photo permanente.

Le draft ajoute `students.photo_file_id uuid`. `students.photo` reste uniquement comme fallback historique tant que les anciennes photos n'ont pas été migrées.

### Lecture de la photo

- Direction 1 / Direction 2 / Enseignant / Parent peuvent utiliser le `download(file_id)` déjà présent dans `r2-files` quand leurs droits sur l'élève l'autorisent.
- Gardien : l'accès générique R2 reste interdit. Une fonction spécialisée `r2-student-photo` ne signe que la photo d'un élève visible au scanner et ne rend aucune liste R2.

Le scanner devra progressivement lire `photo_file_id` puis utiliser cette fonction spécialisée ; `photo` reste fallback historique pendant la transition.

## 6. Transitions qui ne doivent pas rester dans `save_student_profile`

Ces états sont trop sensibles pour un patch générique :

- parent principal -> `set_student_primary_parent` ;
- autorisation de sortie seule -> RPC dédiée à conserver/ajouter selon l'inventaire frontend ;
- archivage/réactivation -> RPC dédiée ;
- blocage accès / finance -> fonctions métier correspondantes ;
- photo -> `set_student_photo_file`.

## 7. Verrouillage des écritures directes — phase 2 uniquement

Aujourd'hui `authenticated` possède encore `INSERT/UPDATE/DELETE` sur `public.students` et la policy `students_direction_write FOR ALL` laisse Direction 1/2 contourner les RPC.

Le draft de verrouillage est **séparé** et ne doit pas être appliqué tant que Claude n'a pas publié dans #89 l'inventaire :

```bash
node tools/audit-schema.mjs --table students --verbose
```

Après raccordement de chaque bouton :

- `REVOKE INSERT, UPDATE, DELETE ON public.students FROM authenticated` ;
- suppression de la policy directe `students_direction_write` ;
- les lectures restent sous RLS ;
- les écritures passent uniquement par RPC contrôlées / service role.

## 8. Ordre frontend final

Création sans photo :

```text
formulaire -> save_student_profile -> ligne serveur -> succès
```

Création avec photo :

```text
formulaire sans photo
-> save_student_profile
-> ligne serveur / ID réel
-> r2-upload
-> file.id permanent
-> set_student_photo_file
-> relecture serveur
-> succès final
```

Si l'upload photo échoue après création de l'élève, l'écran doit dire :

> « L'élève est enregistré, mais sa photo n'a pas été ajoutée. Réessayez la photo. »

Il ne doit ni supprimer l'élève, ni annoncer que tout a échoué.

## 9. Codes proposés

- `STUDENT_CREATED`
- `STUDENT_UPDATED`
- `STUDENT_NOT_FOUND`
- `CLASS_NOT_FOUND`
- `PARENT_NOT_FOUND`
- `IMMUTABLE_STUDENT_NUMBER`
- `VALIDATION_ERROR` + `field`
- `STUDENT_PHOTO_LINKED`
- `FILE_NOT_FOUND`
- `FILE_OWNER_MISMATCH`
- `FILE_CATEGORY_INVALID`
- `STUDENT_ARCHIVED`
- `FORBIDDEN`

## 10. Ce qui reste à Claude avant verrouillage

1. lister toutes les écritures directes `students` du `main` actuel ;
2. indiquer le bouton/écran correspondant à chacune ;
3. confirmer quels champs sont actuellement visibles dans le formulaire élève ;
4. ne pas supprimer les écritures directes au hasard avant que leurs RPC soient posées ;
5. après convergence, recette serveur + navigateur avec un élève synthétique dans une transaction/jeu de test sans conserver de donnée réelle.
