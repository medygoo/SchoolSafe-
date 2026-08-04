# Connecter le site à l'application — état, obstacle, et ce qu'il faut

**Question de Loms, 4 août 2026 :** *« le site doit être connecté à
l'application pour la mise à jour du site et ajouter les informations. »*

**Réponse courte : oui, c'est prévu dans le code — et ça ne peut pas
fonctionner en l'état.** Pas à cause d'un bug : parce que le raccordement a été
construit pour un modèle **multi-écoles** qui n'est plus celui-ci.

---

## 1. Ce qui existe déjà — la plomberie est là

L'écran **« Mon site web »** de la Direction existe et fonctionne à l'écran. Il
sait éditer, et le site statique sait lire :

| ce que la Direction édite | ce que le site affiche |
|---|---|
| `school_name` · `school_name_en` · `tagline` | l'en-tête et le pied de page |
| `about_text` · `mission` · `founded_year` | la page « L'École » |
| `address` · `city` · `phone` · `whatsapp` · `email` | la page Contact |
| `programs` · `pillars` · `stats` | l'accueil et les Programmes |
| `staff` (nom, rôle, photo, citation) | l'équipe |
| `gallery` · `hero_photos` · `hero_url` · `logo_url` | la galerie et les grandes images |
| `theme` · `primary_color` | les couleurs |

Le site lit ces champs dans `assets/site-data.js`, l'application les écrit dans
`saveSiteData()`. **Les deux moitiés se correspondent déjà.** Il n'y a rien à
réécrire de ce côté.

---

## 2. L'obstacle — ce n'est pas un bug, c'est un modèle abandonné

Les deux moitiés ne se parlent pas parce qu'elles passent par un **serveur
central de l'éditeur**, qui n'existe pas pour une école seule.

Côté application :

```js
const CENTRAL_URL = '';   // À configurer de manière sécurisée
const CENTRAL_KEY = '';
// lecture : CENTRAL_URL + '/rest/v1/school_sites?license_key=eq.' + clé
```

Côté site :

```js
const SITE_LICENSE_KEY = '__SCHOOL_KEY__';
const _SS_CENTRAL = '';
const _SS_CKEY    = '';
```

**Trois constantes vides et une clé de licence jamais remplie.** L'écran
« Mon site web » enregistre donc dans le vide — et ne le dit pas.

C'est l'architecture d'un éditeur qui hébergerait les sites de **plusieurs**
écoles dans un projet central, chacune identifiée par une clé de licence. Le
lien « Espace App » du site pousse d'ailleurs `?school=<clé>` vers
l'application, qui la retient en `localStorage`.

**Loms a retiré ce modèle le 3 août.** Il ne reste qu'une école, son
application et son site. La clé de licence ne désigne plus rien, et un serveur
central n'a plus de raison d'être.

---

## 3. Ce qu'il faut à la place — une école, un projet

```
   ┌──────────────────┐        écrit          ┌─────────────────────┐
   │  SchoolSafe      │ ────────────────────▶ │  Supabase de        │
   │  « Mon site web »│   direction seule     │  l'école            │
   └──────────────────┘                       │  table site_content │
                                              └─────────────────────┘
   ┌──────────────────┐        lit                      │
   │  cslesage.com    │ ◀───────────────────────────────┘
   │  pages statiques │   lecture publique, clé anon
   └──────────────────┘
```

Plus de projet central, plus de clé de licence : **le site lit le projet
Supabase de l'école**, celui que ChatGPT a construit.

C'est la seule forme qui tient, parce que le site est **statique** : déposé par
FTP chez LWS, il ne peut afficher du contenu frais qu'en allant le chercher au
chargement de la page.

---

## 4. Ce que ça demande — et à qui

### ChatGPT — la couche serveur (je ne la touche pas)

1. **Une table** qui porte le contenu du site, avec les champs du §1.
   Une seule ligne : il n'y a qu'une école. Le nommage t'appartient.

2. **Deux politiques RLS, et elles ne se ressemblent pas :**
   - **lecture publique**, sans authentification — le site est consulté par des
     parents qui n'ont pas de compte. C'est la seule table de tout le projet
     dans ce cas ;
   - **écriture réservée à `direction`**. Une écriture ouverte laisserait
     n'importe qui remplacer le contenu du site de l'école.

3. **Le CORS de PostgREST doit accepter `cslesage.com`.** Tu l'as fait pour les
   trois fonctions R2 ; il faut le vérifier pour l'API REST, qui est ce que le
   site appellera.

4. **Confirmer que la clé publique (anon) peut être écrite en clair dans un
   fichier JavaScript déposé sur `cslesage.com`.** Elle est publique par
   construction — mais je ne mets aucune clé dans un fichier public sans que tu
   l'aies dit, et sûrement pas si une politique de lecture large la rendait
   plus puissante qu'elle ne devrait.

### Claude — une fois que ces quatre points sont tranchés

- brancher `_loadSiteDataForPage` et `saveSiteData` sur le projet de l'école,
  et **retirer `CENTRAL_URL`, `CENTRAL_KEY`, `license_key`** — vestiges du
  modèle multi-écoles ;
- retirer `SITE_LICENSE_KEY` et `?school=` du site : une seule école, aucun
  contexte à transporter ;
- faire lire `site-data.js` depuis le projet de l'école, **avec le contenu
  actuel gardé en repli** — si Supabase ne répond pas, le site s'affiche
  quand même. Un site d'école qui montre une page vide parce qu'une base est
  lente est pire qu'un site figé ;
- rendre visible l'échec d'enregistrement dans « Mon site web » : aujourd'hui
  il écrit dans le vide **sans le dire**, ce qui est le pire des deux mondes.

### Loms — une décision

**Les photographies.** Le site en porte 21, déposées par FTP. Si la Direction
doit pouvoir en ajouter depuis l'application, elles doivent aller dans **R2**,
et le site les lira par leur adresse. Sinon, une nouvelle photo demandera
toujours un dépôt FTP.

Ce n'est pas la même quantité de travail, d'où la question.

---

## 5. Ce qui marche déjà sans rien attendre

**Le bouton « Espace App SchoolSafe »** — vingt sur les cinq pages — mène à
l'application. Ce sens-là fonctionne, il n'a jamais dépendu du serveur central.

Et **le lien de retour** depuis l'écran de connexion de l'application vers le
site est en place.

---

## 6. En attendant, comment le site se met à jour

Par **FTP**, comme le dépôt initial : je prépare les fichiers, Loms les dépose,
les anciens sont écrasés. C'est immédiat et ça ne casse rien.

C'est acceptable pour un site qui change peu. Ça ne l'est plus dès que la
Direction veut publier une annonce ou une photo elle-même — et c'est
exactement ce que la question de Loms demande.

---

## 7. Le point qui décide de la suite

> **La question à trancher n'est pas « comment brancher », c'est « où vit le
> contenu du site ».**

Tant que la réponse est « dans un projet central de l'éditeur », rien ne peut
marcher : ce projet n'existe pas et n'a plus de raison d'exister. Dès que la
réponse est « dans le projet Supabase de l'école », tout le reste est du
raccordement — et le raccordement est chez moi.

**Une réponse de ChatGPT sur les quatre points du §4 suffit à démarrer.**
