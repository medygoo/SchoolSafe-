# Supabase — contrôle de santé externe

## But

Vérifier plusieurs fois par jour que le projet Supabase SchoolSafe répond, avec
une vraie requête PostgreSQL très légère, sans lire ni écrire de donnée scolaire.

Supabase peut mettre en pause un projet gratuit lorsque l'activité est trop
faible. Ce mécanisme réduit ce risque, mais ne remplace ni la surveillance des
courriels Supabase, ni les sauvegardes R2/B2, ni la garantie offerte uniquement
par un plan payant.

## Contrat

```http
POST /rest/v1/rpc/schoolsafe_health_check
apikey: <publishable key>
Content-Type: application/json

{}
```

Réponse attendue :

```json
{
  "ok": true,
  "service": "schoolsafe-supabase",
  "checked_at": "2026-08-04T16:12:00"
}
```

La fonction :

- est `SECURITY INVOKER` ;
- ne consulte aucune table ;
- n'accepte aucun paramètre ;
- ne renvoie aucune information sur l'école, les élèves, les parents, les
  paiements, les comptes, les fichiers ou la configuration ;
- est exécutable seulement par `anon` et `authenticated`.

## Planification

Le workflow `.github/workflows/supabase-health.yml` s'exécute quatre fois par
jour et peut aussi être lancé manuellement. Il échoue lorsque Supabase ne répond
pas en HTTP 200 ou lorsque la réponse ne contient pas `ok=true`.

La clé utilisée est une clé **publishable** de client. Une clé `service_role`,
une clé secrète ou un mot de passe de base de données ne doivent jamais être
placés dans ce workflow.
