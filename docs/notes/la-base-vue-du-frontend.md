# La base de données, vue du frontend

**Cette couche appartient à ChatGPT.** Rien ici n'autorise à modifier une table,
une colonne, une fonction ou une politique RLS. Ce document sert à autre chose,
et c'est presque aussi utile : **reconnaître un symptôme depuis l'écran, et le
décrire assez précisément pour que ChatGPT sache quoi corriger.**

Un rapport qui dit « ça ne marche pas » coûte trois allers-retours. Un rapport
qui dit « PostgREST rejette la ligne entière parce que la colonne X est absente,
voici la requête et le message » se corrige en une migration.

---

## Le symptôme n° 1 : la donnée qui « se perd toute seule »

C'est de loin le plus fréquent, et le plus mal diagnostiqué.

> L'enseignant saisit un devoir. Il le voit à l'écran. À la synchronisation
> suivante, il a disparu.

L'utilisateur croit à un bug d'affichage. Ce n'en est pas un. **PostgREST rejette
la LIGNE ENTIÈRE dès qu'un seul champ pose problème.** Trois causes :

| Cause | Message serveur |
|---|---|
| Une colonne inconnue au schéma | `column "x" of relation "y" does not exist` |
| Une valeur qui ne correspond pas au type de sa colonne | `invalid input syntax for type numeric: ""` |
| Un droit manquant (RLS) | `new row violates row-level security policy` |

Mesuré une fois : **8 tables et 55 colonnes manquaient** au schéma. Une note
corrigée, une absence excusée, une fiche de préparation partaient dans le vide,
et l'opération se réempilait indéfiniment sans jamais aboutir.

**Ce qu'il faut faire côté interface :** afficher le motif du refus, pas un
« erreur de synchronisation » générique. Le serveur dit toujours pourquoi ; il
faut transporter sa réponse jusqu'à l'écran. Puis ouvrir une issue avec le
message exact.

### Un type de colonne est une promesse au code

Un champ de durée demandait « 45 minutes », « 1h30 » — du texte libre. La colonne
était NUMERIC. **Aucun devoir n'atteignait le serveur.**

Quand le code et la colonne se contredisent, c'est en général **la colonne qui
s'aligne** : la sémantique est dans le code, pas dans le schéma. Mais ce n'est
pas notre décision — on la documente et on la propose.

Deuxième cas de la même famille rencontré : une colonne BOOLEAN qui recevait une
année scolaire.

---

## Le symptôme n° 2 : « ça se perd quand je recharge »

**Règle absolue : POUSSER avant de TIRER.**

Un rechargement remplace les données locales par l'instantané du serveur. Tirer
alors qu'une écriture attend en file **efface cette écriture**. Une
synchronisation périodique qui tire sans avoir poussé fait disparaître le
travail de l'utilisateur toutes les trois minutes.

Corollaire : **une file non vide signifie que le serveur est en retard sur
l'appareil**, jamais l'inverse. On ne tire que si la file est vide.

Et : **une opération n'est jamais jetée.** Après plusieurs échecs, on la met de
côté en la conservant — elle porte une saisie humaine — au lieu de la supprimer.

---

## Le symptôme n° 3 : deux orthographes du même champ

Le site public et l'application n'emploient pas toujours le même mot :
`statut`/`status`, `trimester`/`trimestre`. Les deux colonnes finissent par
exister.

**On réconcilie à la LECTURE**, avec une petite fonction dédiée, plutôt que de
reprendre vingt écritures d'une application en service. C'est le motif du
*normaliseur*, et c'est presque toujours le bon arbitrage.

---

## Le symptôme n° 4 : un modèle de paiement trop simple

Une table de paiements réduite à *(élève, trimestre, booléen payé)* ne sait pas
représenter un versement partiel, plusieurs types de frais, un échéancier ni un
reçu. Les conséquences, toutes mesurées :

- une famille ayant versé 80 % d'un trimestre était affichée **exactement comme
  une famille n'ayant rien payé** ;
- le contrôle des frais au portail **renvoyait son enfant à la maison** ;
- l'accès au bulletin lui était refusé ;
- l'activation automatique de l'accès ne se déclenchait jamais.

Le drapeau « payé » ne se levait que si le trimestre était réglé **en entier**
ET que le versement portait son type de frais et son trimestre.

**Leçon transposable :** « avoir payé » doit avoir **une seule définition**, dans
une fonction que tous les écrans appellent. Quand cette définition est côté
serveur — ce que prévoit le nouveau contrat — l'interface ne la recalcule pas.
Elle l'affiche.

---

## Le symptôme n° 5 : un garde-fou qui dépend de ce qu'il protège

Un amorçage se gardait par « si la table contient déjà des lignes, ne rien
faire » — or ce tableau se remplissait en **lisant** la table, qui n'existait
pas. Le garde-fou ne se déclenchait donc jamais, et neuf écritures vouées à
l'échec repartaient à chaque cycle.

**Un verrou d'amorçage doit vivre ailleurs que dans la donnée qu'il amorce.**

---

## Ce que l'interface doit garantir, quoi qu'il arrive

1. **Toute table lue est déclarée** dans la structure de données locale, donc
   initialisée à un tableau vide au chargement. Une table lue sans être déclarée
   donne un résultat toujours indéfini — et un écran qui ment en silence. C'est
   ce qui affichait l'heure d'arrivée d'un enfant **déjà sorti**.
   → `tools/audit-invariant.mjs` vérifie cette garantie.
2. **Une lecture ratée ne remplace jamais des données par du vide.** Distinguer
   « la table est vide » de « la lecture a échoué » : les confondre efface les
   données locales à la moindre coupure, et la sauvegarde suivante enregistre ce
   vide.
3. **Une écriture partielle n'envoie que les champs modifiés**, jamais l'objet
   entier. Un seul champ local sans colonne fait rejeter toute la ligne.
4. **Un identifiant se génère avec un préfixe et de l'aléa**, jamais avec
   l'horloge seule : deux écritures de la même milliseconde partagent une clé
   primaire, et une seule survit.

---

## Comment écrire un rapport utile à ChatGPT

```
SYMPTÔME     ce que voit l'utilisateur, à l'écran, en une phrase
REPRODUCTION les gestes exacts, et à partir de quel moment ça casse
MESSAGE      la réponse du serveur, mot pour mot
FRÉQUENCE    systématique ? seulement avec des données existantes ?
HYPOTHÈSE    colonne absente / type / droit — et sur quoi elle repose
IMPACT       qui est bloqué, et depuis quand
```

La ligne **MESSAGE** est celle qui fait gagner le plus de temps. Sans elle, on
devine ; avec elle, la cause est presque toujours immédiate.
