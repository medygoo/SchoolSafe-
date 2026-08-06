# P0-24 — e-mail OU téléphone : backend servi

Date : 6 août 2026  
Décision : Loms  
Backend : ChatGPT  
Intégration visible et recette navigateur : Claude

## État production

Migration active dans Supabase : `p0_24_single_contact_auth`.

Migration miroir :

`supabase/migrations/20260806092200_p0_24_single_contact_auth.sql`

## Contrat désormais actif

- `save_school_user_profile` accepte e-mail seul, téléphone seul, ou les deux.
- Zéro coordonnée rend `CONTACT_REQUIRED`.
- Une adresse fournie mais invalide rend `VALIDATION_ERROR`, `field=email`.
- Un numéro fourni mais invalide rend `VALIDATION_ERROR`, `field=phone`.
- Le canal principal doit posséder sa coordonnée ; sinon `PRIMARY_CONTACT_UNAVAILABLE`, `field=access_channel`.
- `prepare_account_invitation` exige uniquement une adresse disponible.
- `prepare_parent_phone_access` exige uniquement un téléphone disponible.
- `handle_new_auth_user` ne bloque plus sur `contact_setup_complete`.
- `contact_setup_complete` reste un indicateur informatif : vrai uniquement lorsque les deux coordonnées existent.
- `login_email_enabled` et `login_phone_enabled` suivent la disponibilité réelle des coordonnées.

## Recette production effectuée avec ROLLBACK

- profil Parent avec e-mail seul : enregistré ; invitation préparée ;
- profil Parent avec téléphone seul : enregistré ; accès WhatsApp préparé ;
- profil sans coordonnée : refusé avec `CONTACT_REQUIRED` ;
- aucune donnée synthétique restante.

## Travail Claude restant

1. Retirer `_msgChampManquant` et les textes disant que le serveur exige encore les deux.
2. Nommer les nouveaux codes :
   - `CONTACT_REQUIRED` : « Renseignez un numéro ou une adresse e-mail. »
   - `PRIMARY_CONTACT_UNAVAILABLE` : « Le canal choisi ne possède pas sa coordonnée. »
   - `EMAIL_REQUIRED` : « Cette fiche n’a pas d’adresse pour recevoir une invitation. »
   - `PHONE_REQUIRED` : « Cette fiche n’a pas de numéro pour recevoir un code WhatsApp. »
3. Garder les boutons conditionnels déjà intégrés : invitation seulement avec e-mail, WhatsApp seulement avec téléphone.
4. Exécuter les audits et la recette navigateur, puis publier.

Aucune modification d’Edge Function n’est requise pour P0-24.
