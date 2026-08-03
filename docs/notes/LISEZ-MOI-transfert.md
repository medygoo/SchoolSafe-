# Paquet de transfert — SchoolSafe

**Destination :** `medygoo/SchoolSafe-`
**Origine :** une autre installation de SchoolSafe, pour **la même école**
(Complexe Scolaire Le Sage / The Wise School International, Kinshasa).

Ce dossier ne contient **aucune ligne de code applicatif**, aucun secret, aucune
donnée d'élève. Il contient ce qu'une année de corrections a appris, et les
outils qui permettent de le vérifier sur place.

---

## Comment le déposer

Copier le **contenu** de ce dossier à la racine du dépôt de destination :

```
CLAUDE.md          → à la racine
tools/             → à la racine
notes/             → à la racine (ou dans docs/)
package.json       → fusionner s'il en existe déjà un
```

Si un `CLAUDE.md` existe déjà là-bas, ne pas l'écraser : garder les deux et les
fondre à la main. Ce fichier-ci ne connaît pas le nouveau code.

Puis :

```bash
npm install     # acorn et acorn-walk, rien d'autre
npm run audit   # la première chose à faire
```

---

## La première chose à faire, et pourquoi

**Lancer les audits avant d'ajouter quoi que ce soit.**

Leur sortie *est* l'inventaire des manques — au lieu d'en discuter. En une
exécution on saura : quelles pages sont blanches à l'exécution sans que le
contrôle de syntaxe le voie, quelles tables sont lues sans être déclarées,
quelles mutations n'ont pas de contrôle de rôle, si les cotes et les classements
donnent les mêmes nombres sur tous les écrans.

C'est aussi la façon la plus honnête de commencer une mission d'audit : des
faits, pas des impressions.

---

## Ce qu'il y a dedans

| | |
|---|---|
| `CLAUDE.md` | la mémoire de travail : le cadre de collaboration, l'école, les documents officiels congolais, et les leçons qui valent dans n'importe quel code |
| `notes/collaboration.md` | le protocole en version opérationnelle : cycle d'une fonctionnalité, compte rendu, matrice de confidentialité par rôle |
| `notes/la-base-vue-du-frontend.md` | **la base appartient à ChatGPT.** Ce document sert à reconnaître un symptôme depuis l'écran et à le décrire assez précisément pour qu'il soit corrigeable |
| `notes/deja-resolu.md` | mission A1–A12 : ce qui est déjà tranché ailleurs, et surtout **ce qui a cassé** |
| `tools/` | dix outils d'audit, exécutables sans navigateur |

---

## Ce qui n'est PAS dedans, volontairement

- **L'identifiant du projet Supabase et les clés.** Cette couche appartient à
  ChatGPT, et un identifiant de projet recopié dans un dépôt n'y a rien à faire.
- **Les migrations SQL et les politiques RLS** de l'autre installation. Le
  nouveau modèle de paiement est en cours de conception par ChatGPT ; recopier
  l'ancien nuirait.
- **Le sel des mots de passe et la clé du cache chiffré.** Ils ne comptent que
  si les comptes et les données hors ligne **existants** doivent continuer de
  fonctionner. Si c'est le cas, ce sont deux chaînes à reprendre à l'identique :
  les changer rend tout compte inaccessible et toute donnée locale illisible.
  **À demander à Loms, jamais à deviner.**
- **Toute donnée réelle** d'élève, de parent ou de paiement.

---

## Les outils, en une ligne chacun

```
audit-portee.mjs        un nom lu hors de sa portée, ou avant sa déclaration
                        → LES PAGES BLANCHES. Le contrôle de syntaxe ne les voit pas.
audit-invariant.mjs     toute table lue est-elle déclarée ?
audit-gardes.mjs        les mutations exposées sans contrôle de rôle
audit-mort.mjs          les fonctions exposées sans appelant
audit-writes.mjs        les écritures dont l'échec est invisible
verif-coherence.mjs     la chaîne de calcul, EXÉCUTÉE — cotes, bulletin, classements
audit-logo.mjs          l'emblème sur les documents · et son ABSENCE de l'interface
audit-charte.mjs        gris · blanc · or sur les documents (--detail)
audit-portee-parent.mjs de quelles données un rôle a-t-il réellement besoin
audit-schema.mjs        code ↔ SQL — À ADAPTER : suppose des fichiers .sql au dépôt
```

Tous lisent `index.html` à la racine. Si le nouveau dépôt a une autre structure
— des sources et un dossier `dist`, par exemple — il faut ajuster ce chemin en
tête de chaque outil. C'est une ligne.

`audit-schema.mjs` est le seul qui touche au domaine de ChatGPT : il compare ce
que le code écrit à ce que le schéma déclare. **Il ne modifie rien** — il
produit la liste des écarts, qui est exactement ce qu'une issue doit contenir.

---

## Trois principes appris en écrivant ces outils

1. **Un outil s'éprouve dans les deux sens.** Il doit dire « incomplet » avant
   et « en place » après. Une vérification qui ne sait dire que oui ne vérifie
   rien.
2. **Il déclare ce qu'il ne sait pas vérifier**, au lieu de se taire. Un audit
   avait un angle mort — une forme d'écriture courante qu'il ignorait en entier
   — et dix manques passaient sans un mot.
3. **La bonne question n'est pas « chaque accès porte-t-il sa garde ? » mais
   « la valeur peut-elle seulement être autre chose ? »** Un audit signalait 498
   accès « non gardés » ; aucun n'était un défaut. Il a été supprimé.

Et un aveu utile : `audit-portee.mjs` a commis, en s'écrivant, la faute exacte
qu'il traque — son cache déclaré sous la fonction qui le lit. C'est dire si
elle est facile à faire.
