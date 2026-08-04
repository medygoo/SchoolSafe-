# Brancher `cslesage.com` — guide pour Loms

**Ce que vous avez à faire : deux étapes, une dizaine de minutes.**
Tout le reste est déjà fait.

Ma part est terminée : le site est dans le dépôt **`medygoo/the-wise-school`**,
avec ses cinq pages, ses 21 photos, son fichier `CNAME` et ses liens vers
l'application. Il ne lui manque que l'adresse.

---

## Où va quoi, une fois fini

| Adresse | Ce qu'on y trouve |
|---|---|
| **`cslesage.com`** | le site de l'école — accueil, l'école, programmes, galerie, contact |
| **`www.cslesage.com`** | renvoie vers `cslesage.com` |
| `medygoo.github.io/SchoolSafe-/` | l'application SchoolSafe, inchangée |

Le bouton **« Espace App SchoolSafe »** est présent sur les cinq pages du site
— vingt boutons au total — et mène à l'application. Et depuis l'écran de
connexion de l'application, un lien ramène au site.

---

## ÉTAPE 1 — Activer GitHub Pages (2 minutes)

1. Ouvrez **https://github.com/medygoo/the-wise-school/settings/pages**
2. Sous **Source**, choisissez **Deploy from a branch**
3. Branche : **`main`** · dossier : **`/ (root)`** → **Save**
4. Attendez une minute. GitHub affiche une adresse en `medygoo.github.io/the-wise-school/` — **c'est normal, ce n'est pas encore la bonne.**
5. Toujours sur la même page, dans **Custom domain**, tapez :

```
cslesage.com
```

puis **Save**.

> GitHub affichera d'abord une erreur de vérification DNS. **C'est attendu** :
> les enregistrements de l'étape 2 n'existent pas encore. Passez à l'étape 2,
> puis revenez ici.

---

## ÉTAPE 2 — Les enregistrements chez Cloudflare (5 minutes)

Ouvrez votre tableau de bord Cloudflare → domaine **cslesage.com** → **DNS**.

### 2.1 · Les quatre lignes de l'adresse principale

Cliquez **Add record** quatre fois. À chaque fois :

| Champ | Valeur |
|---|---|
| Type | **A** |
| Name | **@** |
| IPv4 address | *(voir la liste ci-dessous)* |
| Proxy status | **DNS only** ← le nuage doit être **GRIS**, pas orange |
| TTL | Auto |

Les quatre adresses, une par ligne :

```
185.199.108.153
185.199.109.153
185.199.110.153
185.199.111.153
```

### 2.2 · La ligne du `www`

| Champ | Valeur |
|---|---|
| Type | **CNAME** |
| Name | **www** |
| Target | **medygoo.github.io** |
| Proxy status | **DNS only** ← nuage **GRIS** |
| TTL | Auto |

### ⚠️ Le nuage gris — le seul piège de toute l'opération

Cloudflare met le nuage **orange** par défaut. Orange veut dire « je fais passer
le trafic par moi ». GitHub ne peut alors plus vérifier que le domaine vous
appartient, **et le certificat HTTPS ne sera jamais délivré**.

**Les cinq lignes doivent être en nuage GRIS (« DNS only »).**

Si vous voyez encore une ancienne ligne `A` ou `CNAME` sur `@` ou `www`,
supprimez-la : deux lignes qui se contredisent empêchent tout.

---

## ÉTAPE 3 — Revenir à GitHub (2 minutes, après 10 à 30 minutes d'attente)

1. Attendez que la propagation se fasse — de dix minutes à une heure.
2. Retournez sur **https://github.com/medygoo/the-wise-school/settings/pages**
3. L'erreur de l'étape 1 doit avoir disparu.
4. Cochez **Enforce HTTPS**.

> La case **Enforce HTTPS** reste parfois grisée quelques dizaines de minutes,
> le temps que le certificat soit émis. Ce n'est pas une panne : revenez plus
> tard et cochez-la.

---

## Comment savoir que c'est réussi

Dans cet ordre :

| # | À vérifier |
|---|---|
| 1 | **`https://cslesage.com`** affiche l'accueil de l'école — pas une page d'erreur, pas l'écran de connexion SchoolSafe |
| 2 | Le **cadenas** est présent dans la barre d'adresse |
| 3 | **`https://www.cslesage.com`** bascule tout seul vers `cslesage.com` |
| 4 | Le bouton **« Espace App SchoolSafe »** en haut de page ouvre bien l'application |
| 5 | Les **photos** s'affichent — l'équipe, la galerie, le promoteur |
| 6 | Depuis l'application, le lien **« Visiter le site de l'école »** revient au site |

**Envoyez-vous le lien sur WhatsApp** : il doit maintenant montrer le nom de
l'école, sa description et une photo. Avant, il apparaissait nu.

---

## Si quelque chose ne marche pas

| Ce que vous voyez | Ce que c'est |
|---|---|
| **404 de GitHub** | Pages n'est pas activé, ou la branche choisie n'est pas `main` — reprenez l'étape 1 |
| **« Domain's DNS record could not be retrieved »** | Les enregistrements ne sont pas encore propagés. Attendez, puis rechargez |
| **Le cadenas n'apparaît jamais** | Le nuage Cloudflare est resté **orange**. Repassez les cinq lignes en **DNS only** |
| **Le site s'affiche sans ses images ni ses couleurs** | Prévenez-moi : un fichier manque au dépôt |
| **`cslesage.com` affiche l'écran de connexion SchoolSafe** | Un `CNAME` a été posé par erreur sur le dépôt de l'application. Prévenez-moi immédiatement |

---

## Ce qui reste après, et qui est de mon côté

Une fois `cslesage.com` en service :

1. je fais pointer le lien de l'application vers `https://cslesage.com` ;
2. je nettoie le dépôt de l'application — les cinq pages du site y sont encore
   en double, et son `robots.txt` doit demander à Google de ne pas indexer
   l'application ;
3. je corrige `manifest.json`, dont la portée désigne un fichier au lieu d'un
   chemin — ce qui restreint l'application installée à une seule adresse.

Je ne fais rien de tout cela **avant** que le domaine réponde : tant qu'il ne
répond pas, tout continue de fonctionner comme aujourd'hui, et rien n'est cassé.

---

## Ce qui n'a pas besoin de vous

- **Le CORS Supabase** : déjà fait. ChatGPT a vérifié que les trois fonctions
  R2 acceptent déjà `cslesage.com` et `www.cslesage.com`.
- **L'application** : elle ne bouge pas. Elle reste sur son adresse GitHub,
  et aucun compte, aucun raccourci installé sur un téléphone ne sera perturbé.
