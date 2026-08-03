# Bascule vers `cslesage.com`

**Décision de Loms, 3 août 2026 :**

| Adresse | Contenu |
|---|---|
| `cslesage.com` · `www.cslesage.com` | le **site de l'école** — Complexe Scolaire Le Sage |
| `medygoo.github.io/SchoolSafe-/` (domaine GitHub gratuit) | l'**application** SchoolSafe |

Ce document dit ce qui est déjà fait, ce qui reste, et par qui.

---

## 1. La contrainte à connaître avant tout

**GitHub Pages n'accorde qu'un seul domaine personnalisé par dépôt.**

Aujourd'hui, `medygoo/SchoolSafe-` publie **les deux** depuis `dist/` : l'application
à `/index.html` et le site à `/site.html`. Si l'on pose un fichier `CNAME` portant
`cslesage.com` dans ce dépôt, alors **tout** bascule sur ce domaine — application
comprise — et l'adresse `medygoo.github.io/SchoolSafe-/` se met à rediriger vers
`cslesage.com`. On n'obtient pas la répartition décidée : on la perd.

Pour obtenir ce que Loms a décidé, il faut **deux dépôts** :

```
Dépôt A — nouveau, ex. medygoo/cslesage-site
  contenu : les 5 pages du site, assets/, les 21 photos, robots.txt, sitemap.xml
  CNAME   : cslesage.com
  site.html devient index.html          ← pour que cslesage.com affiche l'accueil
  → sert https://cslesage.com/

Dépôt B — celui-ci, medygoo/SchoolSafe-
  contenu : l'application seule — index.html, auth.html, sw.js, manifest.json,
            les icônes, patrimoine/, les vidéos
  aucun CNAME
  → continue de servir https://medygoo.github.io/SchoolSafe-/
```

Une seule alternative si l'on tient à un dépôt unique : héberger le site sur
**Cloudflare Pages** (le DNS y est déjà) et laisser GitHub Pages à l'application.
Le résultat est identique ; le choix appartient à ChatGPT.

**Tant que la séparation n'est pas faite, on ne pose aucun `CNAME`.** Le site et
l'application restent servis ensemble depuis `medygoo.github.io/SchoolSafe-/`,
exactement comme aujourd'hui. Rien n'est cassé.

---

## 2. Pourquoi séparer, au-delà du domaine

Trois raisons techniques, mesurées sur le code actuel.

**Le service worker de l'application contrôle aussi le site.** Il est enregistré
depuis `index.html` avec la portée `/` — donc l'origine entière — et sa règle de
repli renvoie `./index.html` pour toute navigation qui échoue. Un visiteur qui a
déjà ouvert SchoolSafe, puis revient sur le site avec un mauvais réseau, peut
recevoir **l'application à la place du site de l'école**. Le site n'a aucun
service worker à lui. Deux origines distinctes suppriment le problème ; aucun
réglage ne le supprime aussi proprement.

**L'indexation.** Un `sitemap.xml` ne peut déclarer que des adresses de sa propre
origine. Site et application mélangés sur une même origine obligent à un
`robots.txt` qui autorise et interdit dans le même fichier — c'est ce qu'il fait
aujourd'hui.

**Les deux noms.** Le logiciel s'appelle SchoolSafe, l'école s'appelle Le Sage.
Deux adresses, c'est cette distinction rendue visible — celle que `CLAUDE.md`
signale comme « la plus souvent perdue, et elle se paie cher ».

---

## 3. Ce qui est déjà fait — Claude, commit de ce lot

Ces corrections sont valables quelle que soit l'organisation retenue. Elles ne
dépendent d'aucun DNS et ne cassent rien avant la bascule.

### 3.1 Les images du site ne dépendent plus d'un dépôt étranger

**56 adresses** dans les cinq pages pointaient vers
`https://medt121.github.io/zalavrai/` — un autre compte GitHub, un autre dépôt :
le logo, la photo d'accueil, le promoteur, les neuf membres de l'équipe, toute la
galerie.

Les **21 fichiers existent déjà** dans `dist/`. Ils sont désormais servis depuis
le dépôt de l'école. Le jour où `medt121/zalavrai` est renommé, supprimé ou passé
en privé, le site ne perdra plus ses photos.

Contrôle exécuté : toutes les références locales résolvent vers un fichier
présent, et il ne reste aucune trace de l'ancien domaine dans `dist/`.

### 3.2 Le lien de l'école est partageable

Les cinq pages portent maintenant `description`, `canonical`, `og:url`,
`og:title`, `og:description`, `og:image`, `og:site_name`, `og:locale`,
`twitter:card` et `theme-color`. **Quatre pages sur cinq n'avaient rien du tout** :
ni description, ni balise de partage.

Concrètement : partagé sur WhatsApp — le canal principal à Kinshasa — le lien de
l'école affichera son titre, sa description et une photo, au lieu d'une adresse
nue.

Les `canonical` et `og:url` désignent **`https://cslesage.com/…`**, c'est-à-dire
la destination décidée. Avant la bascule DNS ces adresses ne répondent pas encore ;
c'est sans conséquence, les pages n'étaient de toute façon pas indexées sous la
bonne adresse.

### 3.3 `robots.txt` et `sitemap.xml`

Les deux désignaient encore `medt121.github.io/zalavrai/` : Google était dirigé
vers l'ancien site. Le `sitemap.xml` ne déclarait **qu'une seule page sur cinq**.

Ils déclarent désormais les cinq pages sous `cslesage.com`, et `robots.txt` exclut
`auth.html` en plus de `index.html` — la page de mot de passe n'a rien à faire
dans un moteur de recherche.

⚠️ **Ces deux fichiers appartiennent au site.** Ils partent dans le dépôt A. Le
dépôt B (l'application) recevra alors son propre `robots.txt` :

```
User-agent: *
Disallow: /
```

### 3.4 L'adresse de l'école

**11 occurrences** corrigées sur les cinq pages :

```
avant   Kabambare A4, Quartier Ndolo, Commune de Barumbu
après   Kabambare 4367, Quartier Bon Marché, Commune de Barumbu
```

C'est l'adresse que `CLAUDE.md` retient comme la bonne, après que trois variantes
eurent coexisté sans qu'aucune le soit. Une adresse fausse sur le site public
d'une école envoie les familles au mauvais endroit.

Note : quand la liaison décrite au §5 sera rétablie, cette adresse viendra des
**Paramètres** de l'application et la Direction pourra la corriger elle-même. La
valeur écrite dans les pages reste le repli.

---

## 4. Ce qui reste à ChatGPT

### 4.1 Hébergement et DNS

1. Créer le dépôt A (ou la cible Cloudflare Pages) et y publier le site.
2. Y renommer `site.html` en `index.html` pour que `cslesage.com` affiche
   l'accueil, et non une page d'erreur.
3. Poser `CNAME` = `cslesage.com` dans l'artefact publié du dépôt A.
4. Enregistrements DNS Cloudflare pour l'apex vers GitHub Pages :
   `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, `185.199.111.153`
   (et les AAAA correspondants), plus `www` en `CNAME` vers `medygoo.github.io`.
   À adapter si le site part sur Cloudflare Pages.
5. HTTPS, certificat, `www` → apex, et vérifier la propagation.
6. Ne poser **aucun** `CNAME` dans ce dépôt-ci : il doit rester sur le domaine
   GitHub gratuit.

### 4.2 Le point qui fera tout échouer s'il est oublié

> **Ajouter les nouvelles origines aux origines autorisées Supabase et au CORS des
> Edge Functions R2** (`r2-upload`, `r2-files`, `r2-archives`).

L'application reste sur `medygoo.github.io`, donc son origine ne change pas — mais
le site, lui, arrive sur `cslesage.com`, et c'est de là que partiront les appels
`school_announcements` et `school_sites` décrits au §5. Sans cette autorisation,
le site ne recevra jamais ses annonces, et le navigateur n'affichera qu'une erreur
CORS que personne ne pense à regarder.

### 4.3 Ce dont j'ai besoin pour rebrancher « Mon site web »

Voir §5 : l'URL du projet central et sa clé **publique** (jamais `service_role`),
et la `license_key` de l'école.

---

## 5. Le défaut de fond : « Mon site web » écrit dans le vide

La Direction dispose dans l'application d'un écran **« Mon site web »** qui règle
les couleurs, la galerie, les annonces, les contacts et l'adresse. Il écrit dans
`school_sites`. Le site public est censé les lire au chargement, via
`dist/assets/site-data.js`.

Or ce fichier porte encore son gabarit :

```js
const SITE_LICENSE_KEY = '__SCHOOL_KEY__';   // placeholder jamais remplacé
const _SS_CENTRAL = '';                       // vide
const _SS_CKEY = '';                          // vide
```

Conséquences, toutes vérifiées dans le code :

- `_ssPatchAppLinks()` sort à la première ligne — les liens « Espace App » ne
  portent donc pas le contexte école `?school=…` que `index.html` attend ;
- les deux `fetch` (`school_announcements`, `school_sites`) partent vers une
  adresse vide et échouent en silence ;
- **tout ce que la Direction règle dans « Mon site web » ne parvient jamais au
  site.**

C'est une fonctionnalité entière branchée à rien — un « champ mort » au sens de
`CLAUDE.md`, à l'échelle d'un écran. Ce n'est pas une régression de la bascule :
c'est antérieur. Mais le changement d'adresse est le bon moment pour le régler,
puisque la liaison devra de toute façon connaître la nouvelle origine.

**Ce que je ne fais pas :** remplir ces trois constantes en devinant. Une clé et
un identifiant de projet ne se supposent pas.

---

## 6. À la bascule — ce que je reprendrai côté frontend

Rien de ceci n'est fait aujourd'hui : ces valeurs ne deviennent justes qu'une fois
les deux adresses en service. À faire dans le même lot, une fois ChatGPT prêt.

| Où | Aujourd'hui | Après |
|---|---|---|
| Site → application (17 liens sur 5 pages) | `href="index.html"` | `https://medygoo.github.io/SchoolSafe-/` |
| Application → site (écran de connexion) | `href="site.html"` | `https://cslesage.com/` |
| `manifest.json` · `start_url` et `scope` | `./index.html` | à revoir — voir ci-dessous |
| `sw.js` | précache `./index.html` | version de cache à incrémenter |

**`manifest.json` porte par ailleurs un défaut indépendant du domaine :**

```json
"scope": "./index.html"
```

Une portée doit être un **préfixe de chemin**, pas un fichier. En l'état,
l'application installée est limitée à cette seule adresse : toute autre page de
l'origine sort de la portée et s'ouvre hors de l'application. La valeur juste est
`"./"`. À corriger au même moment, parce que changer une portée de manifeste
touche les installations existantes et ne doit se faire qu'une fois.

---

## 7. Deux questions restées ouvertes pour Loms

1. **La palette du site.** Elle est crème / brun / laiton, et sa variable CSS
   s'appelle littéralement `--emerald` — c'est le **premier** des quatre essais de
   couleur qu'a connus l'école. La charte retenue, d'après `CLAUDE.md`, est
   **gris bleuté `#6b7d8b` · blanc · or `#c09018`**. Le laiton du site, `#c0962e`,
   en est très proche ; c'est le fond crème qui diffère du blanc.
   Refait-on le site à la charte, ou la charte ne concerne-t-elle que les
   documents imprimés ?

2. **Le numéro de téléphone.** Le site affiche `+243 816 722 901`. L'application
   porte `243978444167` comme numéro opérateur. Les deux sont-ils justes, l'un
   pour l'école et l'autre pour PRODELI ?

---

## 8. Retour arrière

`git revert` du commit de ce lot. Les images redeviennent distantes, les balises
de partage disparaissent, l'adresse revient à l'ancienne. Aucun effet sur
l'application, sur Supabase, sur R2 ni sur le déploiement : `dist/` contient
toujours **144 fichiers**, la valeur exigée par `.github/workflows/pages.yml`.
