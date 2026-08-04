# La préinscription en ligne — comment on y arrive · 4 août 2026

**Demande de Loms :** *« les billets de vacances et l'affiche visibles sur le
site ; la fiche de renseignements remplie en ligne si possible, pour permettre
au parent de s'inscrire en ligne et de venir payer à l'école. »*

---

## L'idée en une phrase

> **Le parent remplit, l'école encaisse.** Rien d'autre ne change.

La famille arrive à l'école avec ses renseignements **déjà écrits**. La
Direction confirme et encaisse. C'est tout le gain — et il est réel : à
350 élèves, c'est plusieurs jours de secrétariat économisés à la rentrée, et
zéro fiche illisible.

**Aucun paiement ne passe par le site.** Le versement se fait à la Caisse,
contre un reçu. Un site scolaire qui demanderait de l'argent en ligne serait la
première chose qu'un escroc imiterait — et une famille grugée s'en prendrait à
l'école, pas au faux site.

---

## Pourquoi en deux étapes

Le site est **statique** : des pages HTML déposées par FTP chez LWS. Il n'a pas
de serveur à lui.

Brancher la préinscription sur la base demande une table, deux politiques et un
réglage CORS — **quatre points qui appartiennent à ChatGPT**
(`coordination/SITE_CONNECTE_A_L_APP.md`). Attendre cela pour ouvrir la
préinscription, **c'est perdre la rentrée**.

D'où deux étapes, dont la première est déjà livrée.

---

# Étape 1 — livrée, ne dépend de personne

Dépôt `medygoo/the-wise-school`, commit `daead75`. Page `inscription.html`.

## Ce que le parent voit

| | |
|---|---|
| **L'affiche** « Inscriptions en cours 2026-2027 », agrandissable | ce qu'il connaît déjà des réseaux sociaux |
| **Le minerval** — 900 $, trois tranches : 400 / 100 / 400 | écrit noir sur blanc, plus besoin d'appeler |
| **Cantine, jouets, uniforme** — 25 $/mois · 15 $ · 20 $ ou 5 000 FC | |
| **Les horaires** des deux cycles, récréations comprises | |
| **Les quatre billets de vacances** — maternel, primaire 1-2, 3-4, 5-6 | agrandissables, imprimables |
| **Les quatre NB** de la Direction | |
| **Ce que les frais comprennent** | informatique, danse, musique, poterie, taekwondo, cantine |

## Ce que le parent fait

```
   ①  il remplit la fiche          ②  il l'envoie ou l'imprime      ③  il vient payer
      sur son téléphone                 WhatsApp Direction              la fiche est déjà prête
      5 minutes                          ou fiche papier                 il ne reste qu'à confirmer
```

Le bouton **WhatsApp** ouvre une conversation avec la Direction, message déjà
écrit. Le bouton **Imprimer** ouvre une fiche à l'emblème et à la charte de
l'école, avec les **trois colonnes de signature** — parent, secrétariat,
Direction — et cette mention, qui est la plus importante de la page :

> **Préinscription.** Cette fiche a été remplie en ligne par la famille. Elle
> ne vaut pas inscription : l'inscription est confirmée à la Direction, après
> paiement de la première tranche du minerval, **contre un reçu de l'école**.

## Deux choix qui comptent

**Les champs portent déjà les noms de l'application** — `nom`, `dob`,
`lieu_naissance`, `adresse`, `nom_papa`, `nom_maman`, `blood_group`,
`medical_notes`. L'étape 2 ne demandera **aucune ressaisie** ni aucune table de
correspondance.

**Le formulaire dit ce qui manque, pas « veuillez remplir ce champ ».** Sur
quinze lignes, la phrase du navigateur ne dit pas où regarder. Il dit
« Il manque le nom de l'élève », et il met le curseur dedans.

## Éprouvé, pas supposé

Rempli et déclenché dans un vrai navigateur :

```
fiche vide      →  « Il manque le nom de l'élève. »
fiche remplie   →  la page imprimable s'ouvre — regardée
WhatsApp        →  le lien produit a été décodé et vérifié
```

Neuf nouveaux couples texte/fond mesurés, de 4,77:1 à 16,11:1 : **aucun sous le
seuil AA**.

---

# Étape 2 — quand la base sera prête

Le même formulaire écrira une **demande de préinscription** dans le projet
Supabase de l'école, et la Direction la verra tomber dans SchoolSafe.

## Ce qu'il faut de ChatGPT

C'est la **même** infrastructure que celle demandée pour connecter le site
(§4 de `SITE_CONNECTE_A_L_APP.md`) — une table de plus, et **une politique qui
n'existe nulle part ailleurs dans le projet** :

> **écriture publique, sans authentification.** Un parent qui préinscrit n'a
> pas encore de compte. C'est la seule table du projet dans ce cas, et elle
> demande donc des précautions que les autres n'ont pas :
>
> - **écriture seulement** — un parent ne doit jamais pouvoir *lire* la table,
>   sinon il lit les fiches des autres familles ;
> - **un frein** contre le remplissage automatique : sans lui, la table se
>   remplit de milliers de fausses fiches en une nuit ;
> - **lecture réservée à la Direction et au secrétariat.**

Si tu préfères une **Edge Function** plutôt qu'une écriture directe, c'est
mieux : elle valide, limite le débit, et ne laisse pas la table exposée. Le
choix t'appartient — je m'adapte à ce que tu exposes.

## Ce que Claude fera ensuite

- envoyer la fiche à la porte que tu auras ouverte, **en gardant WhatsApp et
  l'impression** : une famille sans réseau doit pouvoir préinscrire quand même ;
- un écran **« Demandes de préinscription »** pour la Direction — accepter
  crée l'élève et son parent, refuser garde la trace ;
- rendre visible l'échec d'envoi. *Une écriture dont l'échec est invisible est
  pire qu'une écriture absente.*

---

# Étape 3 — les idées qui viennent ensuite

Notées ici pour ne pas les réinventer. **Aucune n'est engagée.**

| idée | ce qu'elle apporte | ce qu'elle coûte |
|---|---|---|
| **Le parent suit sa demande** avec un numéro | il n'appelle plus l'école pour savoir | dépend de l'étape 2 |
| **Les billets de vacances tirés de l'application** | la Direction change une fourniture sans refaire une affiche | l'écran « Mon site web » les gère déjà, il suffit de les raccorder |
| **Un calendrier de rentrée** sur la page | dates de reprise, réunions de parents | contenu de la Direction |
| **Les annonces de la Direction** publiées sur le site | une seule saisie pour l'app et le site | dépend du site connecté |
| **Un QR code sur l'affiche imprimée** menant à la page | les parents qui voient l'affiche au portail préinscrivent sur place | quelques lignes |

**Celle qui rapporte le plus pour le moins d'effort est la dernière.** Un QR
code sur l'affiche que la Direction imprime déjà, et le parent qui la lit
devant l'école remplit la fiche avant même d'être entré.

---

## Ce que Loms doit décider

1. **Le numéro WhatsApp de la préinscription.** J'ai mis **+243 978 444 167**,
   celui des affiches. L'autre — +243 816 722 901 — est celui du site.
   Dites-moi si ce n'est pas le bon.
2. **La cantine du primaire.** Les affiches disent « voir la Direction pour le
   montant ». La page le répète tel quel. **Ne rien afficher vaut mieux
   qu'afficher faux** — mais si le montant est fixé, il vaut mieux l'écrire.
3. **Les photographies des billets.** Elles viennent de vos affiches, telles
   quelles. Si une fourniture change, il faut une nouvelle image — ou passer
   par l'idée « billets tirés de l'application » ci-dessus.
