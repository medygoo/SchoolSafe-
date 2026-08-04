# SchoolSafe — sécurité Auth sur le plan Supabase gratuit

**Date :** 4 août 2026  
**Organisation Supabase :** Prodeli  
**Plan vérifié :** `free`

## Décision

L'alerte Supabase « leaked password protection disabled » ne peut pas être
supprimée sur le plan actuel : la protection native contre les mots de passe
déjà divulgués est disponible uniquement sur le plan Pro et supérieur.

SchoolSafe reste sur le plan gratuit. Le projet ne doit donc pas annoncer que
cette protection est active.

## Ce qui ne sera pas fait

- aucune fausse case « protection activée » dans l'application ;
- aucun envoi du mot de passe complet vers un service externe ;
- aucun stockage temporaire ou journalisation d'un mot de passe ;
- aucun contournement de Supabase Auth avec un système artisanal de mots de
  passe ;
- aucun passage au plan payant sans décision explicite de Loms.

## Protections gratuites retenues

### 1. Comptes créés sur invitation

Les profils de Direction, Caisse, Gardien, Enseignant et Parent sont préparés
dans SchoolSafe puis reliés à Supabase Auth par le contrat d'invitation. La
création libre de comptes administratifs n'est pas permise.

### 2. Mot de passe fort

À raccorder dans l'interface Auth et à confirmer dans les réglages Email de
Supabase :

```text
longueur minimale recommandée : 12 caractères
au moins une minuscule
au moins une majuscule
au moins un chiffre
au moins un symbole
```

Le frontend doit afficher les exigences avant la soumission et transmettre les
erreurs `WeakPasswordError` sans les masquer.

### 3. Changement de mot de passe sensible

Pour les comptes sensibles, l'application doit demander une session récente ou
une réauthentification avant changement de mot de passe. Le mot de passe actuel
doit être exigé lorsque le flux le permet.

### 4. MFA pour les rôles sensibles

La Direction 1, la Caisse et les comptes administratifs doivent être prioritaires
pour l'authentification multifacteur dès que le flux frontend est raccordé et
testé.

### 5. Limitation des rôles dans la base

La sécurité ne repose jamais uniquement sur le mot de passe :

- les rôles sont conservés dans `public.users` et reliés à `auth.users` ;
- aucune autorisation n'utilise les métadonnées modifiables par l'utilisateur ;
- les RLS et RPC revérifient le rôle actif ;
- un utilisateur ne peut pas s'auto-promouvoir ;
- les fonctions sensibles vérifient `auth.uid()` et le profil SchoolSafe.

### 6. Surveillance

L'avertissement du conseiller Supabase reste **connu et accepté tant que le plan
est gratuit**. Il doit être reconsidéré si l'organisation passe au plan Pro.

## État réel

```text
Protection native contre mots de passe divulgués : indisponible sur Free
Mot de passe fort dans le frontend                   : à raccorder par Claude
Réglages Email Auth Supabase                         : à confirmer dans le dashboard
MFA rôles sensibles                                  : à raccorder et tester
Contrat d'invitation sécurisé                        : déployé
RLS / rôle serveur                                   : déployés
```

## Référence officielle

Supabase Auth — Password security : la documentation indique que la protection
contre les mots de passe divulgués est disponible sur le plan Pro et supérieur.
