# Protocole de collaboration — mémo opérationnel

Résumé exécutable du protocole v1.0 (2 août 2026), du dossier d'exécution du
point 19 et de la décision de Loms du 3 août 2026. En cas de divergence, **ce
sont les documents et décisions de Loms qui font foi**.

La règle complète et prioritaire se trouve dans
[`coordination/PUBLICATION_MAIN.md`](../../coordination/PUBLICATION_MAIN.md).

---

## Décision obligatoire sur la publication

- **Claude est l'unique responsable de l'intégration finale, de la fusion des
  travaux validés et de la publication finale sur `main`.**
- Claude traite les bugs applicatifs, intègre les livraisons, exécute les tests
  finaux, demande l'autorisation de Loms, puis fusionne et publie.
- ChatGPT ne fusionne pas et ne publie pas la version finale sur `main`.
  ChatGPT remet ses travaux à Claude par branche et Pull Request.
- Tout travail déjà réalisé par Claude ou ChatGPT est considéré comme demandé
  par Loms. On continue à partir de là ; on ne recommence pas sans sa décision.

---

## Le cycle d'une fonctionnalité

```
1. Loms exprime le besoin
2. Analyse fonctionnelle
3. ChatGPT écrit le CONTRAT TECHNIQUE lorsque le backend est concerné
4. Issue GitHub
5. Branche dédiée
6. Développement LIMITÉ au besoin reçu
7. Tests
8. Pull Request en BROUILLON
9. Revue technique + contrôle de Loms
10. Corrections et intégration finale par Claude
11. Autorisation explicite de Loms
12. Fusion sur main + publication + contrôle par Claude
```

On ne construit pas une interface sur des champs supposés. Un champ backend
absent du contrat est demandé à ChatGPT avant intégration.

## Nommage des branches

```
claude/...                         bugs, frontend, site, intégration
feature/parent-fees-dashboard      interface
feature/payment-scanner-ui         scanner
fix/payment-status-display         correction
backend/…  security/…              ChatGPT
release/…                          préparation finale par Claude
```

---

## Compte rendu après chaque livraison

```
TÂCHE :
BRANCHE :
PULL REQUEST :
COMMITS :
RESPONSABLE :

1. Résultat livré
2. Fichiers modifiés
3. Impact Supabase / RLS / Auth / R2 / PWA / domaine
4. Tests exécutés et résultats
5. Risques ou limites
6. Retour arrière
7. Travail attendu de Claude pour l'intégration finale
8. Décision attendue de Loms
```

**Le point 3 se remplit même quand la réponse est « aucun ».** C'est la ligne
que l'autre agent lit en premier ; l'omettre oblige à relire tout le diff.

**Le point 4 gagne à porter la sortie des audits.** C'est une preuve vérifiable,
pas une affirmation.

---

## Ce qu'on ne fait jamais seul

| | |
|---|---|
| Table, colonne, vue, fonction, trigger, index, migration | coordination obligatoire |
| Politique RLS | coordination obligatoire |
| Désactiver RLS pour contourner une erreur | jamais, sous aucun prétexte |
| Ajouter un secret au dépôt | jamais |
| Publier la version finale sur `main` | **Claude uniquement, après autorisation de Loms** |
| Calculer un solde uniquement dans le navigateur | jamais |

Une poussée directe sur `main` reste interdite pour le travail ordinaire. Claude
publie la version finale par fusion de Pull Requests validées. Une intervention
directe d'urgence exige une autorisation explicite de Loms et une documentation
immédiate.

Et : **signaler AVANT de coder** tout impact sur Supabase, Auth, R2, le cache
PWA, le service worker ou les permissions. Après, c'est trop tard — le travail
est fait.

---

## La confidentialité par rôle — la matrice à ne pas trahir

C'est le point le plus facile à casser par inadvertance, parce qu'une donnée
peut fuir par un écran **partagé** entre plusieurs rôles.

| Rôle | Voit après un scan |
|---|---|
| Direction 1 | tout : détail, paiements, solde, blocages, dérogations |
| **Direction 2** | **rien de financier.** Le scanner financier est masqué |
| Caisse / Direction 3 | détail financier complet, échéancier, reçus |
| Gardien | photo, identité, classe, **instruction seule — aucun montant** |
| Enseignant | scanner financier masqué |
| Parent | résumé détaillé **de ses propres enfants uniquement** |

**Protection de Direction 2 :** même en scannant dans un autre contexte, aucune
raison financière, aucun montant, aucun statut de paiement ne doit lui revenir.
Une restriction éventuelle se présente comme une **instruction administrative
générale**.

⚠️ Le piège vérifié dans l'autre installation : les écrans **partagés** — les
présences, les messages, le calendrier — portent aussi la branche de la
Direction. Un découpage « par table » y est indécidable. C'est pourquoi la
restriction doit porter sur les **lignes** que le serveur renvoie, pas sur ce
que l'interface choisit d'afficher.

**Corollaire mesuré :** dans l'autre installation, un parent recevait les 47
tables de l'école à chaque cycle — toutes les cotes, les salaires, le journal
comptable. À 250 familles et une réception par minute, ~11 750 requêtes/minute,
et le téléphone d'une famille détenait les résultats de tous les autres enfants.
C'est exactement ce que le nouveau contrat serveur doit empêcher.

---

## Ce qu'on demande à ChatGPT plutôt que de le deviner

- un champ absent du contrat — **on ne le déduit pas côté navigateur** ;
- le comportement attendu quand le serveur ne répond pas ;
- la durée de validité d'un statut mis en cache ;
- le message exact à afficher pour chacun des états ;
- qui a le droit de déclencher quoi, quand un doute existe.

**Poser la question coûte un aller-retour. La deviner coûte une fonctionnalité.**
