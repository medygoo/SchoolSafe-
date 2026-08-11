# Accès WhatsApp + carte de première connexion — ma moitié est posée

**Pour ChatGPT.** Décision de Loms du 11 août 2026. Aucune migration créée,
aucune RLS touchée, aucun champ inventé côté navigateur.

Le navigateur est prêt et **appelle déjà ton contrat existant**
(`parent-phone-access`, actions `provision` / `reset`). Il te reste **trois
choses**, et elles sont petites.

---

## 1. Le format du code temporaire — une ligne

`supabase/functions/parent-phone-access/index.ts` :

```ts
function tempCode(): string {
  return `Sa-${digits(4)}-${digits(4)}`;      // aujourd'hui : Sa-1234-5678
}
```

Loms a arrêté : **exactement 2 lettres + 6 chiffres, sans tiret, sans espace,
sans symbole** — `LS482731`.

Le navigateur ne le fabrique pas et ne doit pas le fabriquer : ce code **est**
le mot de passe Auth que tu poses par la clé d'administration. Il le reçoit et
l'affiche. Il sait déjà reconnaître le format (`window._codeAuFormat`) et
**prévient la Direction**, sur l'écran de la carte, tant que le serveur rend
l'ancienne forme. Le jour où tu changes cette ligne, l'avertissement disparaît
tout seul.

## 2. `public.users.login_name` — la colonne qui manque

La carte validée par Loms porte **quatre lignes** : téléphone, abréviation,
nom de connexion, code temporaire.

- **Téléphone** : `users.phone`, servi. ✔
- **Abréviation** : `users.initials`, servi, et `saveUser` la tient déjà
  unique sur l'ensemble des comptes. ✔
- **Nom de connexion** : **n'existe dans aucune colonne de `public.users`.**

Je ne l'ai pas inventé. Une valeur écrite par le navigateur dans une colonne
absente ne serait jamais enregistrée, et un identifiant imprimé sur une carte
qui n'ouvre rien est pire que pas d'identifiant du tout : la famille se plaint
d'un code « qui ne marche pas » alors que c'est la ligne qui n'aurait pas dû
être là.

**Donc aujourd'hui la carte n'écrit pas cette ligne**, et l'écran dit à la
Direction pourquoi. Elle apparaîtra d'elle-même, sans que je touche au
navigateur, dès que `users.login_name` existe et arrive dans `ROLE_LOAD` :
`window._identifiantsDe` la lit déjà.

Ce que je te demande, à toi de décider de la forme :

| | |
|---|---|
| colonne | `login_name text`, **unique**, minuscules |
| qui l'écrit | `save_school_user_profile` — proposée automatiquement depuis le nom, corrigeable |
| lecture | l'ajouter au `select` de `users` dans les bootstraps direction et direction2 |

## 3. `resolve_school_login_identity` — un canal de plus

Aujourd'hui :

```sql
if v_channel='email' then …
elsif v_channel in ('phone','phone_whatsapp') then …
else return jsonb_build_object('ok',false,'code','INVALID_CREDENTIALS');
```

Loms veut que **les trois identifiants ouvrent le même compte avec le même mot
de passe**. Il manque donc un canal.

**Je te demande UN canal, pas deux** — `identifier` — qui essaie `initials`
puis `login_name` :

```sql
elsif v_channel='identifier' then
  v_identifier := lower(btrim(coalesce(p_identifier,'')));
  select * into v_user from public.users
   where (lower(initials)=v_identifier or lower(login_name)=v_identifier)
     and status='active' and access_ready limit 1;
```

**Pourquoi un seul et pas deux :** le navigateur ne peut pas savoir lequel des
deux on lui a tapé — il ne lit pas `users` avant la connexion, la RLS le lui
interdit, et c'est tout l'objet du relais `school-login`. S'il devait deviner,
il refuserait une abréviation valide parce qu'elle ressemble à un nom de
connexion.

Le navigateur envoie déjà `channel:'identifier'`. Tant que tu ne le sers pas,
le serveur rend `INVALID_CREDENTIALS` et **l'écran ne dit pas « mot de passe
incorrect »** : il dit que cette voie n'est pas encore ouverte et renvoie au
numéro. Si tu préfères un code dédié, rends `UNSUPPORTED_CHANNEL` — l'écran le
sait déjà nommer.

---

## Ce qui est fait, et qui ne t'attend pas

| | |
|---|---|
| la carte | dessinée sur canvas, au design validé, **remplie avec les vraies données**. Jamais de valeur d'exemple. Une ligne dont la valeur manque ne s'imprime pas. |
| le message WhatsApp | exactement les mots de Loms, avec les mêmes lignes que la carte |
| le partage | Web Share **avec fichier** quand l'appareil l'accepte ; sinon la carte se télécharge, prête à joindre. Puis WhatsApp avec le texte prérempli. |
| la réinitialisation | le **même** bouton : `reset` au lieu de `provision`, nouveau code, nouvelle carte, l'ancien accès invalidé par ton contrat, **aucun second profil** |
| l'écran de connexion | accepte les trois formes et route sur le bon canal |

**Et ce que je n'ai pas fait exprès :** `wa.me` ne sait pas joindre un
fichier — sans l'API WhatsApp Business, aucune image ne part automatiquement.
L'écran le dit en clair au lieu de laisser croire que la carte est partie.

## Ce que je n'ai pas pu vérifier

**Le parcours contre la vraie base.** Pas d'accès réseau à Supabase depuis mon
environnement : je n'ai exécuté **aucune** des deux étapes serveur. Ce qui est
éprouvé, c'est le dessin de la carte, le format du code, le message et le
partage, dans un vrai navigateur. La recette de Loms — créer un profil,
essayer les trois identifiants, créer le mot de passe, vérifier que le code
temporaire ne marche plus — reste à faire une fois les trois points ci-dessus
servis.
