# Mettre le site sur `cslesage.com` — guide pour Loms

**Le domaine est chez LWS (hebergeur-discount.com), pas chez Cloudflare.**
Cela change le plan — et le simplifie beaucoup.

Votre formule inclut **1 Go d'hébergement HTML**. Or le site de l'école est
exactement cela : des pages HTML, du CSS, des images. Aucun PHP, aucune base de
données. **Il n'y a donc rien à configurer en DNS.** Le domaine pointe déjà sur
votre hébergement, et le certificat HTTPS s'installe tout seul.

---

## Ce que ça donne une fois fini

| Adresse | Ce qu'on y trouve |
|---|---|
| **`cslesage.com`** | le site de l'école — accueil, l'école, programmes, galerie, contact |
| `medygoo.github.io/SchoolSafe-/` | l'application SchoolSafe, inchangée |

Le bouton **« Espace App SchoolSafe »** est sur les cinq pages — vingt boutons
au total — et mène à l'application. Depuis l'écran de connexion de
l'application, un lien ramène au site.

---

## ⚠️ Avant tout : votre mot de passe FTP

Vous m'avez transmis le courriel de LWS. Le mot de passe n'y figurait pas, tant
mieux.

**Ne l'écrivez jamais ici, ni dans le dépôt, ni dans un message.** Un identifiant
FTP donne le droit de remplacer n'importe quel fichier du site de l'école.
Il reste chez vous, dans votre espace client.

Je n'en ai pas besoin : je prépare les fichiers, vous les déposez.

---

## LA MÉTHODE — déposer les fichiers par FTP (15 minutes, une seule fois)

### 1 · Installer FileZilla

C'est gratuit : **https://filezilla-project.org** → *FileZilla Client*.

### 2 · Se connecter

En haut de FileZilla, quatre cases :

| Case | Valeur |
|---|---|
| **Hôte** | `ftp.cslesage.com` |
| **Identifiant** | `csles2841800` |
| **Mot de passe** | *le vôtre, depuis l'espace client LWS* |
| **Port** | `21` |

→ **Connexion rapide**

La fenêtre de droite est votre hébergement. La fenêtre de gauche, votre
ordinateur.

### 3 · Se placer à la racine

À droite, vous devez être à la racine — le chemin affiché est `/`.

> Selon les hébergements, il peut exister un dossier `www`, `public_html` ou
> `htdocs`. **S'il y en a un, entrez dedans** : c'est lui qui est publié.
> Le courriel de LWS dit « laissez vide ou / », donc en principe la racine
> directement.

### 4 · Déposer les fichiers

Décompressez l'archive **`site-cslesage.zip`** que je vous ai envoyée. Elle
contient **33 fichiers** :

```
index.html          ← l'accueil
ecole.html  programmes.html  galerie.html  contact.html
assets/             ← styles et scripts (4 fichiers)
21 photos           ← logo, équipe, galerie
robots.txt  sitemap.xml
```

Dans FileZilla : **sélectionnez tout** dans la fenêtre de gauche, et
**glissez-le** dans la fenêtre de droite. Attendez la fin — 2,4 Mo, une à deux
minutes selon la connexion.

> ⚠️ Déposez bien le **contenu** du dossier, pas le dossier lui-même. À droite
> vous devez voir `index.html` directement, et non un dossier qui le contient.
> Sinon le site s'afficherait à `cslesage.com/site-cslesage/` au lieu de
> `cslesage.com`.

### 5 · Regarder

Ouvrez **`https://cslesage.com`**. L'accueil de l'école doit s'afficher.

> Le certificat HTTPS s'installe automatiquement chez LWS, mais parfois avec
> quelques heures de décalage. Si le cadenas manque au début, essayez
> `http://cslesage.com` — si la page s'affiche, le dépôt est réussi et il ne
> reste qu'à attendre le certificat.

---

## Comment savoir que c'est réussi

| # | À vérifier |
|---|---|
| 1 | **`https://cslesage.com`** affiche l'accueil de l'école |
| 2 | Le **cadenas** est présent (peut prendre quelques heures) |
| 3 | Les cinq pages s'ouvrent : L'École, Programmes, Galerie, Contact |
| 4 | Les **photos** s'affichent — l'équipe, la galerie, le promoteur |
| 5 | Le bouton **« Espace App SchoolSafe »** ouvre l'application |
| 6 | L'adresse affichée est bien **Kabambare 4367, Quartier Bon Marché** |

**Envoyez-vous le lien sur WhatsApp** : il doit montrer le nom de l'école, sa
description et une photo. Avant, il apparaissait nu.

---

## Si quelque chose ne va pas

| Ce que vous voyez | Ce que c'est |
|---|---|
| Une page LWS « site en construction » | Les fichiers ne sont pas au bon endroit — cherchez un dossier `www` ou `public_html` à droite dans FileZilla |
| `cslesage.com/site-cslesage/` fonctionne mais pas `cslesage.com` | Vous avez déposé le dossier au lieu de son contenu. Remontez les fichiers d'un niveau |
| Les pages s'affichent **sans couleurs ni photos** | Le dossier `assets/` ou les images ne sont pas montés. Vérifiez que `assets/site.css` existe bien à droite |
| Le cadenas ne vient jamais après 24 h | Écrivez à l'assistance LWS depuis votre espace client : « certificat SSL non émis sur cslesage.com » |
| Une page blanche | Prévenez-moi tout de suite : c'est un défaut de ma part, pas de l'hébergement |

---

## Et plus tard, quand le site devra changer

Le site est aussi conservé dans le dépôt **`medygoo/the-wise-school`**. C'est là
que je travaille dessus. Quand je le modifie, je vous renvoie une archive à
déposer — la manœuvre est la même, et elle écrase les anciens fichiers.

**Une amélioration possible, si les mises à jour deviennent fréquentes :** LWS
permet de déclarer une zone DNS. On pourrait alors faire servir le site
directement depuis GitHub, et il se mettrait à jour tout seul à chaque
modification, sans FTP.

Ce n'est pas nécessaire aujourd'hui — le site change peu — et **le FTP a
l'avantage d'être immédiat et de ne rien casser**. On y reviendra si le besoin
se présente.

---

## Vos deux adresses e-mail

Votre formule inclut **deux adresses** et 2 Go. Elles se créent depuis
« Administration E-mails » de votre espace client.

Suggestion, si vous n'avez pas encore décidé :

```
contact@cslesage.com     ← celle qui figurera sur le site et les documents
direction@cslesage.com   ← la Direction
```

Dites-moi celle que vous retenez : **je la mettrai sur la page Contact et sur
les documents officiels**, où il n'y a aujourd'hui qu'un numéro de téléphone.

---

## Ce qui reste de mon côté, après votre dépôt

1. faire pointer le lien de l'application vers `https://cslesage.com` ;
2. nettoyer le dépôt de l'application — les cinq pages du site y sont encore
   en double, et son `robots.txt` doit demander à Google de ne pas indexer
   l'application ;
3. corriger `manifest.json`, dont la portée désigne un fichier au lieu d'un
   chemin — ce qui restreint l'application installée à une seule adresse.

Je ne touche à rien **avant** que `cslesage.com` réponde. Tant qu'il ne répond
pas, tout continue de fonctionner comme aujourd'hui.

---

## Ce qui n'a besoin de personne

- **Le CORS Supabase** : déjà fait, ChatGPT l'a vérifié — les trois fonctions R2
  acceptent déjà `cslesage.com`.
- **L'application** : elle ne bouge pas. Aucun compte, aucun raccourci installé
  sur un téléphone ne sera perturbé.
