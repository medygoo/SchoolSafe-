# Méthode de travail — les 7 jours

**Validée par Loms, 3 août 2026.** Ce document dit comment Claude et ChatGPT
travaillent d'ici la livraison, et surtout **où passe la frontière**.

---

## 1. Le constat qui commande tout

ChatGPT a fini l'essentiel de sa part. La base existe, les RPC existent, R2
tourne, les contrats sont écrits.

**L'application n'appelait aucune de ces portes.** Zéro appel `.rpc()` avant le
2 août. Elle écrit en direct dans 47 tables via PostgREST, comme si la couche
serveur n'existait pas.

**Donc : ce qui manque n'est presque plus du backend. C'est du raccordement, et
le raccordement est entièrement chez Claude.**

Conséquence directe sur la répartition :

> **ChatGPT n'a plus besoin de construire. Il a besoin de documenter ce qu'il a
> déjà construit.** Six des neuf RPC scanner, `private.current_app_role()`,
> `private.current_app_user_id()`, la migration des paiements : tout cela existe
> en base et **n'est nulle part dans le dépôt**. Claude travaille à l'aveugle
> sur le socle.

Chaque nouvelle migration élargit ce qu'il reste à brancher. **Sur ces sept
jours, une migration de plus est un jour de retard.**

---

## 2. L'idée qui décide si on finit — un adaptateur, pas 47 réécritures

Le monolithe a un défaut qui est aussi un cadeau : **il n'a qu'une seule couche
de données.**

Les 502 fonctions ne parlent jamais au serveur. Elles lisent toutes le même
objet `DB` en mémoire. Et les 311 écritures passent toutes par **une seule
fonction**, `pushSync`.

Il n'y a donc pas 502 fonctions à réécrire. **Il y en a deux.**

| | Aujourd'hui | Après |
|---|---|---|
| **Lecture** | `loadFromSupabase()` tire 47 tables, identique pour les six rôles | une **table de chargement par rôle**. Les 143 écrans lisent `DB` sans changer d'une ligne. |
| **Écriture** | `pushSync(table, op, data)` écrit en direct | un **aiguillage** : si la table a une RPC de contrat, il y va ; sinon écriture directe, échec rendu visible. **Les 311 appels ne bougent pas.** |

C'est cela, « tout rassembler dans un seul endroit connecté » : un fichier, une
table de correspondance, lisible d'un coup d'œil.

```
students   → save_student_profile          direction, direction2
users      → save_school_user_profile      direction
scan_log   → record_entry_scan / record_exit_scan / record_scan_incident
…
autres     → écriture directe, refus affiché avec son motif
```

**Ce que ça change :** « réécrire 502 fonctions en 6 jours » devient « écrire
proprement deux fonctions et une table ». C'est la différence entre finir et ne
pas finir.

**Où l'adaptateur ne suffit pas** — travail d'écran, incompressible mais borné à
une dizaine d'écrans sur 143 :

- ceux qui doivent **afficher** un calcul du serveur au lieu de le refaire :
  frais du parent, détail Caisse, statut portail ;
- les défauts de logique : refus compté comme entrée, pages blanches.

---

## 3. La frontière

| | ChatGPT | Claude |
|---|---|---|
| Fichiers | `supabase/` · `docs/` · `coordination/` | `dist/` · `tools/` |
| Décide | schéma, RLS, RPC, R2, sécurité serveur | interface, navigation, intégration, tests |
| Ne fait pas | fusionner, publier | modifier une table, une politique, une RPC |
| Publication `main` | — | **Claude, après autorisation de Loms** |

**On ne touche jamais le même fichier.** ChatGPT pousse quand il veut ; Claude
rebase sur lui, jamais l'inverse.

**Claude ne bloque que sur des faits.** Un choix d'interface, il le prend et il
avance. Une signature de fonction qu'il ne peut pas deviner, il s'arrête et il
demande — et pendant qu'il attend, il travaille sur une autre partie. Les
parties sont découpées pour cela.

---

## 4. Le point de contact — un seul fichier, un tableau

Je demande à ChatGPT de tenir **`coordination/RPC_REGISTRE.md`** : une ligne par
porte, pas de prose.

```
nom · rôles autorisés · paramètres · réponse succès · codes d'erreur
```

C'est exactement ce que consomme la table d'aiguillage. Et `tools/audit-schema.mjs`,
déjà dans le dépôt, compare ce que le code appelle à ce que le registre déclare :
**un écart devient visible en trois secondes au lieu d'un aller-retour d'une
journée.**

---

## 5. Le jeu de 350 élèves — construit au jour 1, pas au jour 6

`tools/jeu-350.mjs` — déterministe, aucune donnée réelle. Un défaut trouvé se
rejoue à l'identique.

```
350 élèves · 12 classes · 288 familles · 272 parents
10 254 cotes · 342 devoirs · 1 400 lignes de paiement
344 présences · 349 scans dont 5 REFUS · 62 élèves en fratrie

à jour 186   ·   PARTIELS 141   ·   rien 23
poids total : 1,83 Mo
```

Deux chiffres à retenir, et ils justifient à eux seuls les parties B et C :

> **1,83 Mo et 10 254 cotes** sont tirés par **chaque** téléphone à chaque
> ouverture — y compris celui d'un parent, qui reçoit les notes de tous les
> élèves de l'école.
>
> **141 familles sur 350 sont en paiement partiel.** Le modèle actuel — un
> booléen par trimestre — les traite **exactement comme les 23 qui n'ont rien
> versé**. À l'échelle réelle, cela veut dire renvoyer 40 % des enfants du
> portail.

À partir de maintenant, chaque test se fait sur ce jeu. Attendre le jour 6 pour
découvrir que l'application ne tient pas, c'est découvrir trop tard.

---

## 6. La cadence

**Un lot par jour, poussé le soir**, avec la sortie des audits collée sur le
canal. Pas de branche longue, pas de travail en cours qui traîne.

**À chaque fin de lot :**

1. pousser sur `claude/new-session-guwhgl` ;
2. poster : livré · sortie des audits · impact Supabase/RLS/Auth/R2/PWA ·
   risques restants · ce que j'attends ;
3. **relire le canal avant d'attaquer le lot suivant** ;
4. ne pas attendre la revue pour enchaîner, sauf dépendance explicite.

**On ne fusionne qu'après avoir lancé les audits.** Ils trouvent une page
blanche en trois secondes. C'est le filet qui rend le travail à deux agents
possible sur un fichier unique.

| Jour | Claude | ChatGPT |
|---|---|---|
| **J1** | corriger mes défauts · normaliseur de rôle · jeu de 350 | **le registre + les définitions manquantes** |
| **J2** | l'aiguillage des écritures · le chargement par rôle | réponses au fil de l'eau |
| **J3** | frais du parent · Caisse · reçus | numéro de reçu |
| **J4** | portail via ses RPC · confidentialité Gardien / D2 | signatures scanner |
| **J5** | documents administratifs · R2 | — |
| **J6** | documents imprimés · épreuve à 350 | registre de délivrance |
| **J7** | recette des six rôles · **publication** | revue |

---

## 7. Ce que j'attends de ChatGPT — par urgence

| # | Demande | Pourquoi |
|---|---|---|
| **1** | **`private.current_app_role()` et `private.current_app_user_id()`** — leur définition, et ce qu'elles renvoient pour une session **non reliée** | 40 usages dans les migrations versionnées. C'est le socle de toute la sécurité, et je ne peux pas le lire. Quatorze lignes `users` n'ont pas d'`auth_user_id` : que voient ces comptes ? |
| **2** | La **liste réelle** des valeurs de `users.role` en base | J'ai trouvé `direction_pedagogique`, `caisse` et `enseignant_maternelle`. L'interface n'en connaissait aucun. Un compte portant l'un d'eux était **rejeté à la connexion**. J'ai posé un normaliseur — dites-moi s'il en manque. |
| **3** | Les **signatures** de `get_scanner_students`, `record_entry_scan`, `record_exit_scan` | Elles existent et je ne les utilise pas. `get_scanner_students` **est** la « liste minimale du Gardien » que je réclamais : ma question sur le matricule tombe si elle le renvoie. |
| **4** | **`coordination/RPC_REGISTRE.md`** | Le point de contact du §4. |
| **5** | La liste des **tables et colonnes par rôle**, avec les vues ou RPC quand le filtre ne s'exprime pas en PostgREST | Partie B. Sans elle, je ne peux pas remplacer le `Promise.all` de 47 tables. |
| **6** | Comment distinguer **« aucune donnée »** de **« accès refusé »** | Aujourd'hui une lecture refusée par RLS rend `[]`, que `safe()` traite comme légitime : le parent verrait des écrans vides **sans message**. |
| **7** | Le SQL des paiements — `20260802205234` absent du dépôt | Partie C. |
| **8** | Le **numéro de reçu** : serveur ? séquentiel par année ? | Une administration doit pouvoir demander « montrez-moi le n° 42 ». |
| **9** | `r2-upload` ou `r2-files upload` ? version 1 ou 4 ? | Vos documents se contredisent. Je pars sur `r2-upload` v4. |
| **10** | **`cslesage.com` dans les origines Supabase et le CORS** | Sinon erreur CORS silencieuse le jour de la bascule. |

**Les trois premières bloquent le jour 2.** Les autres peuvent arriver au fil de
l'eau.

---

## 8. Ce que Claude tranche seul

Interface, navigation, messages, ordre des écrans, rendu, hors ligne, structure
des tests, découpage du code.

**Autorisation demandée seulement pour** : la publication finale, et les règles
métier qui changent ce que voient les gens — le Gardien et Direction 2.

---

## 9. Ce que cette semaine ne fera pas

Découper le fichier de 28 000 lignes. C'est le changement le plus risqué du lot,
parce qu'il touche tout. **Il vient après la rentrée, pas avant.**
