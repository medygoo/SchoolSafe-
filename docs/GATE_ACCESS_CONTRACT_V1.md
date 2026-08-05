# SchoolSafe — contrat portail v1 et validation backend

Date : 3 août 2026  
Responsable backend : ChatGPT  
Responsable intégration finale et publication `main` : Claude

## Migration

- Supabase : `20260803155814_harden_gate_access_contract`
- GitHub : `supabase/migrations/20260803155814_harden_gate_access_contract.sql`
- Projet : `lcnronymkccgyltttqry`

## Objet

La RPC `public.get_gate_access_status(p_sid text)` fournit désormais une réponse
stable de dix champs, y compris lorsque l'identifiant est vide ou que l'élève
est introuvable.

Champs :

- `student_id`
- `student_name`
- `matricule`
- `class_id`
- `class_name`
- `photo_url`
- `access_status`
- `allowed`
- `instruction`
- `checked_at`

Aucun montant, solde, reçu, devise, trimestre ou motif financier détaillé n'est
retourné.

## Instructions autorisées

| État | Instruction |
|---|---|
| `allowed` | Accès autorisé |
| `exception` | Accès temporairement autorisé |
| `orient` | Accès autorisé — suivi administratif requis |
| `blocked` | Accès non autorisé — orienter vers la Caisse |
| `unavailable` | Contrôle manuel requis |

## Permissions

- `PUBLIC` : révoqué
- `anon` : révoqué
- `authenticated` : autorisé, avec contrôle métier obligatoire par `private.can_scan()`
- `service_role` : autorisé pour opérations serveur
- `search_path` : vide

La fonction reste volontairement `SECURITY DEFINER` parce qu'elle doit produire
une réponse minimale commune à plusieurs rôles sans leur ouvrir les tables
financières. L'appel est refusé lorsque le compte authentifié ne possède pas un
rôle de scan reconnu. Le conseiller Supabase continue donc à afficher un
avertissement générique sur cette fonction ; il est documenté comme exception
intentionnelle et ne doit pas être ignoré pour les autres anciennes RPC.

Références Supabase :

- https://supabase.com/docs/guides/database/functions
- https://supabase.com/docs/guides/api/securing-your-api

## Tests exécutés

### Structure des réponses

Cas testés : identifiant vide, identifiant introuvable et absence de données
actives.

Résultat : les réponses contiennent toutes exactement les dix mêmes clés,
`checked_at`, un état `unavailable` et une instruction générique.

### Appel non autorisé

Un appel `authenticated` avec un identifiant Auth ne correspondant à aucun
profil SchoolSafe actif a été refusé avec `Accès refusé`.

### Droits SQL

ACL vérifiée :

```text
postgres = EXECUTE
 authenticated = EXECUTE
 service_role = EXECUTE
 PUBLIC / anon = aucun droit
```

### Données de test

Aucune donnée réelle n'a été modifiée. Les tests d'autorisation ont été exécutés
dans des transactions terminées par `ROLLBACK`.

## Limite actuelle

La base ne contient actuellement aucun élève actif et un seul rôle Auth actif
(Direction 1). Les scénarios réels Gardien, Direction 2, Caisse et Enseignant
devront être rejoués pendant l'intégration finale avec les comptes de test
contrôlés, puis nettoyés.

## Consigne Claude

- intégrer cette RPC sans recalculer le solde dans JavaScript ;
- conserver les dix champs comme contrat stable ;
- appliquer une expiration hors ligne de 5 minutes à partir de `checked_at` ;
- après expiration, afficher `Contrôle manuel requis` ;
- ne jamais afficher un détail financier au Gardien, à Direction 2 ou à
  l'Enseignant ;
- effectuer les tests finaux, demander l'autorisation de Loms, puis publier
  `main` conformément à `coordination/PUBLICATION_MAIN.md`.
