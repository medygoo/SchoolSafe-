# Finance/RH — Reçu de paiement V2 validé

État : **CONSTRUIT SUR BRANCHE, NON ACTIVÉ EN PRODUCTION**.

Branche : `chatgpt/finance-rh-construction`
Fichier : `dist/recu-paiement-v2.js`
Recette statique : `tools/recette-recu-v2.mjs`

## Décisions validées par Loms — 11 août 2026

- Le reçu devient le modèle Finance/RH de référence pour la future bascule unique.
- Format impression : **demi-A4 = A5 paysage**, pour rester lisible sur téléphone sans zoom.
- Charte : blanc, gris, noir, or ; vert seulement pour confirmer un paiement.
- Logo : vrai logo de l’école via `SCHOOL_LOGO`, `SCHOOL_LOGO_DOC`, puis `./logo.jpg` en repli.
- Devise de l’école : **Former, Réformer, Exceller**.
- Ne pas imprimer « Éducation d’Excellence, Discipline et Valeurs ».
- Les montants importants, surtout `Montant reçu` et `Montant payé`, sont volontairement agrandis.
- Zones `Lu et approuvé`, `Établi par`, `Visa & cachet de l’école` : **VIDES**. Aucune signature automatique, aucune image `SCHOOL_SIGNATURE`, aucun `_officialFooter`.
- Le reçu doit être rempli automatiquement depuis les données réelles, jamais depuis des exemples.
- Mode de paiement et référence externe sont prévus.
- Détail des obligations : désignation, période, montant attendu, montant payé, solde restant.
- Duplicata prévu sans changer le numéro d’origine.
- Annulation/contrepassation visible ; le reçu ne disparaît jamais.

## Branchement final prévu

Ne pas remplacer immédiatement les fonctions live : Loms a demandé de terminer **toute la partie Finance/RH puis de lancer une seule fois**.

Lors de la bascule finale :

1. charger `recu-paiement-v2.js` dans `dist/index.html` ;
2. router `printVersementRecu` vers `printVersementRecuV2` ;
3. router le reçu Parent vers le même builder (`viewReceiptV2`) ;
4. transmettre dans la notification Parent le mode de paiement, la référence et les allocations/solde utiles ;
5. vérifier les reçus normaux, partiels, duplicata et contrepassés sur téléphone et PDF ;
6. seulement ensuite retirer les anciens gabarits dupliqués.

## Important pour Claude

Ne recrée pas un troisième gabarit de reçu. Si tu travailles sur Finance/RH avant la bascule, conserve ce contrat et signale toute donnée frontend qui manque au builder V2. La base de données n’a pas été modifiée par ce chantier.
