# SchoolSafe — règle verrouillée des documents officiels

Décision de Loms — 12 août 2026.

## Installation concernée

Cette version de SchoolSafe est construite pour **une seule école** :

- **Complexe Scolaire Le Sage**
- **The Wise School International**
- Devise : **Former, Réformer, Exceller**

Il ne faut donc pas traiter le nom de cette école comme un paramètre multi-écoles susceptible de changer d'établissement dans cette installation. Les documents officiels doivent conserver une identité unique et cohérente.

## Format officiel

**Tout document officiel produit, téléchargé, imprimé ou remis par SchoolSafe est un PDF.**

Cela comprend notamment : reçus, listes de présence, registres du personnel, listes élèves/tuteurs, bulletins, palmarès, devoirs imprimés, rapports, documents Finance/RH, documents comptables et administratifs.

Un CSV/JSON reste possible uniquement comme **export technique de données** ou format d'import. Il ne doit jamais être présenté comme un document officiel, un reçu, une liste officielle ou une pièce à remettre.

## Identité visuelle obligatoire

Chaque PDF officiel doit porter :

1. le logo du Complexe Scolaire Le Sage (via le mécanisme document existant `SCHOOL_LOGO_DOC` / `_logoDoc`) ;
2. « Complexe Scolaire Le Sage » ;
3. « The Wise School International » ;
4. la devise exacte « Former, Réformer, Exceller » lorsque le gabarit prévoit la devise ;
5. les éléments de traçabilité propres au document (date, période, référence, auteur/visa quand applicable).

Les règles existantes de signature restent inchangées : un document de travail n'est pas signé uniquement parce qu'il est en PDF.

## Correction de la PR #122

La phrase « Plus une version tableur pour qui doit trier ou envoyer » ne décrit plus un document officiel. La liste officielle **Élèves et tuteurs** est proposée en PDF uniquement. Si un export CSV est conservé dans le code pour traitement technique, il reste un export de données distinct et ne doit pas apparaître comme seconde version officielle de la liste.

## Reçu de paiement V2

Le reçu V2 respecte déjà le chemin PDF : `dlPDF(..., Recu-....pdf)`. Il reste dormant jusqu'à la bascule Finance/RH prévue ; cette règle ne l'active pas prématurément.

## Limites de cette décision

Aucune modification Supabase, RLS, RPC, VPS ou donnée métier. Cette règle concerne le format et la présentation des documents côté application.
