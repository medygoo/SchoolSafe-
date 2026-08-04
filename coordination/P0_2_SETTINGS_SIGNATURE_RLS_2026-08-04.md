# P0-2 — visa de la Direction dans `settings.school.signature`

Date : 4 août 2026

## Réponse exacte

Il n’existe pas de colonne SQL séparée appelée `settings.school.signature`.

La structure réelle est :

```text
public.settings.school  jsonb
```

`signature` est une clé facultative à l’intérieur de cet objet JSONB.

Dans la ligne actuelle `settings.id = 'main'` :

```text
clé school.signature présente : non
longueur de la valeur          : 0
```

Le frontend utilise donc encore sa signature de repli tant qu’une valeur n’est pas enregistrée dans `school.signature`.

## Protection RLS réelle

La table `public.settings` possède une seule politique :

```sql
settings_d1_all
FOR ALL
TO authenticated
USING (private.is_direction())
WITH CHECK (private.is_direction())
```

La fonction de contrôle est :

```text
private.current_app_role() = 'direction'
```

Cela correspond exclusivement à **Direction 1**.

## Recette authentifiée avec rollback

Une valeur fictive a été tentée dans `school.signature` en utilisant la vraie chaîne d’autorisation Auth/RLS.

| Profil simulé | Lignes mises à jour |
|---|---:|
| Enseignant | 0 |
| Direction 1 | 1 |

La transaction a été annulée. Après contrôle :

```text
school.signature présente : non
valeur fictive conservée  : non
```

## Conclusion pour Claude

Le point P0-2 peut être fermé ainsi :

- seule Direction 1 peut enregistrer ou remplacer `settings.school.signature` ;
- Enseignant, Direction 2, Caisse, Gardien et Parent ne passent pas `private.is_direction()` ;
- aucune migration de colonne n’est nécessaire, car `school` est déjà un JSONB ;
- tant que la clé est absente, le frontend conserve le visa de repli validé par Loms.

Lorsqu’un écran permettra de modifier le visa, il doit écrire la clé `signature` tout en conservant les autres propriétés de l’objet `school`.