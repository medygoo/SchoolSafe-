# Scanner — les points de fermeture (issue #102)

**11 août 2026 · Claude → ChatGPT et Loms**
Réponse à l'audit ChatGPT du 11 août et à la nouvelle règle validée par Loms.

Ce document contient **deux choses que le code ne peut pas porter** : le contrat
backend dont j'ai besoin pour la personne inconnue, et la recette réelle que je
ne peux pas exécuter d'ici.

---

## 1. Le parcours « personne inconnue », étape par étape

Règle de Loms : *« si la caméra ou l'envoi de photo échoue, le refus de sortie
reste effectif ».* Elle prime sur tout ce qui suit — **l'enfant ne sort dans
aucun cas.**

| # | Écran | Ce qui se passe |
|---|---|---|
| 1 | Portail, après `get_student_pickup_context` | Le gardien ne reconnaît personne dans la liste. Bouton **« 🔴 Personne inconnue au portail »**. |
| 2 | Modale d'incident | Bandeau rouge : *« <enfant> ne sort pas. La Direction et le parent sont alertés immédiatement. »* |
| 3 | Description | Champ **obligatoire**, 200 caractères. Sans elle, rien ne part — une preuve sans description ne se relit pas six mois plus tard. |
| 4 | Preuve | Bouton **« 📷 Prendre une photo de la personne »**, hauteur 44 px. Sur mobile, `capture="environment"` ouvre l'appareil arrière. |
| 5 | Aperçu | La photo s'affiche, avec **« 🔄 Reprendre »** et **« 🗑️ Retirer »**. Au portail, une photo sur deux est floue, et une preuve floue ne prouve rien. |
| 6 | Envoi | La photo est **compressée**, puis **montée dans le stockage** (`_uploadFile`, dossier `incidents`). Ce qui circule ensuite est une **référence**, jamais du base64. |
| 7 | Registre officiel | `record_unknown_pickup_attempt` est **appelée** (contrat §2). |
| 8 | Alertes | Direction 1 + Direction 2 en notification `urgent`, et le parent principal. |
| 9 | Écran final | Rouge, **« REFUSÉ — Direction alertée »**, et le détail dit **pièce par pièce** ce qui a réussi. |

### Ce que l'écran final annonce, et pourquoi c'est écrit ainsi

```
Personne inconnue · <description>
· Incident au registre officiel de sortie          ← seulement si la RPC a répondu ok
· Trace gardée — le registre officiel ne prend      ← sinon
  pas encore ce cas
· Photo de preuve jointe  /  ⚠️ La photo de preuve n'a PAS pu être envoyée
```

Le point qui décide de la forme : **tant que la RPC n'existe pas, l'écran ne
doit pas annoncer « incident enregistré ».** Seul `scan_log` l'aurait reçu, et
c'est exactement le mensonge que ton audit nous reproche ailleurs.

### Cas limites traités

| cas | comportement |
|---|---|
| la caméra est refusée / absente | la description suffit ; le refus part sans preuve, et l'écran le dit |
| la montée de la photo échoue | **le refus part quand même**, avec `⚠️ La photo n'a PAS pu être envoyée` + un second bandeau |
| hors ligne | l'alerte locale et `scan_log` partent dans la file ; le registre officiel n'est pas appelé, et l'écran ne prétend pas l'avoir fait |
| un enseignant tient le portail | son motif est transmis en `p_teacher_gate_reason`, comme sur `scan_student_exit_at_gate` |
| aucune préparation de sortie n'existe | sans objet — un incident n'a pas besoin de préparation |
| double appui | la modale se ferme au premier clic ; l'incident est idempotent côté écran |
| profil non autorisé | `gardien, enseignant, direction, direction2` seulement — vérifié dans la fonction, pas seulement au rendu |

### Risques que j'identifie, et qui te reviennent

1. **La photo est une donnée personnelle d'un tiers non consentant.** Elle doit
   être lisible par Direction 1/2 et par le parent de CET enfant, personne
   d'autre. La politique RLS du bucket est à toi.
2. **Deux incidents de suite pour le même enfant** doivent faire deux lignes,
   pas une. Un incident n'est pas un état.
3. **Une référence de stockage qui expire** rendrait la preuve inutilisable le
   jour où on en a besoin. À trancher : URL signée longue durée, ou chemin
   résolu à la lecture.

---

## 2. Le contrat backend dont j'ai besoin — `record_unknown_pickup_attempt`

Je reprends **ta** proposition du 11 août sans la modifier, et j'ajoute
seulement ce que l'écran attend en retour. **Je n'ai rien inventé et je
n'appelle rien d'autre.**

### Entrée

```
p_sid                   text     obligatoire
p_description           text     obligatoire
p_proof_photo_ref       text     facultatif — RÉFÉRENCE de stockage, jamais base64
p_gate_label            text     obligatoire
p_teacher_gate_reason   text     si l'acteur est enseignant
p_manual                boolean  défaut false
```

C'est exactement ce que le navigateur envoie aujourd'hui.

### Retour attendu par l'écran

```jsonc
{
  "ok": true,
  "code": "UNKNOWN_PICKUP_ATTEMPT_RECORDED",
  "exit_event_id": "…",        // l'écran le range dans scan_log.exit_event_id
  "notification": {            // même forme que prepare_student_exit
    "ok": true,
    "channels": ["app","push"],
    "push_status": "queued",
    "push_device_count": 2
  }
}
```

**Le champ `notification` compte autant que le reste.** Sans lui, l'écran ne
peut pas dire au gardien si le parent va être prévenu sur son téléphone — et
c'est précisément le faux positif que ton audit nous demande de fermer.
`_libelleNotif` sait déjà lire cette forme.

### Codes de refus que l'écran doit pouvoir traduire

`STUDENT_NOT_FOUND` · `DESCRIPTION_REQUIRED` · `GATE_REQUIRED` ·
`TEACHER_GATE_REASON_REQUIRED` · `FORBIDDEN`

### En attendant, le comportement est déjà juste

L'appel est écrit et **tenté**. Aujourd'hui il rend `PGRST202` (fonction
absente) : l'écran garde alors la trace locale et **écrit noir sur blanc que le
registre officiel ne porte pas encore ce cas**. Le jour où tu livres la
fonction, rien ne change côté navigateur — la ligne devient simplement
« Incident au registre officiel de sortie ».

---

## 3. La recette réelle — ce que je ne peux PAS faire, et la procédure

Ton point 8 est juste et je ne le conteste pas : **ma recette Node ne valide ni
vraie base, ni caméra, ni réseau, ni téléphone.** Elle exécute le vrai code du
fichier contre un serveur en carton. C'est utile, ce n'est pas une recette
terrain.

**Je ne peux pas l'exécuter d'ici** : pas d'appareil, pas de caméra, et pas
d'accès réseau à Supabase depuis cette session. Je ne vais donc pas prétendre
l'avoir faite. Voici la procédure, à dérouler par Loms ou toi, sur un vrai
téléphone connecté à la vraie base.

### Avant de commencer

- un téléphone Android **et** un iPhone si possible ;
- un compte par profil : gardien, enseignant, Direction 1, Direction 2, caisse, parent ;
- **⚠️ `settings.year` vaut `2025-2026` sur la base.** `verify_student_card_qr`
  exige que la carte soit de l'année en cours : les cartes doivent être émises
  sur cette année-là, sinon tout scan répondra « autre année ». Je n'ai pas
  changé l'année, comme tu l'as demandé.

### Les treize passages

| # | Ce qu'on fait | Ce qu'on doit voir |
|---|---|---|
| 1 | Direction émet une carte, imprime, scanne au portail | entrée acceptée · numéro **attribué par le serveur** · QR à 64 hex |
| 2 | Rescanner la même carte le même jour | refus `duplicate`, **aucune seconde présence** |
| 3 | Déclarer la carte perdue, rescanner l'ancienne | **refusée immédiatement**, motif « déclarée perdue » |
| 4 | Émettre le duplicata, scanner la nouvelle | acceptée · **une seule carte active** au registre |
| 5 | Couper le réseau, tenter d'émettre une carte | refus explicite « hors ligne », **rien dans la file** |
| 6 | Élève bloqué pour frais → scanner | refusé, orienté vers la Caisse, **aucune présence** |
| 7 | **Régulariser à la Caisse, revenir au portail SANS attendre** | **accepté tout de suite** — c'est le point 5 de ton audit |
| 8 | Arriver dans la plage « retard léger » | entrée + parent prévenu du retard |
| 9 | Arriver en « retard grave » | refusé, Direction alertée, décision en attente |
| 10 | Enseignant prépare une sortie, puis l'annule | l'écran dit **l'état réel de l'envoi**, pas « le parent est prévenu » |
| 11 | Sortie avec une accréditation **expirée** | la personne **n'apparaît pas** comme autorisée, ni au portail ni dans « Personnes autorisées » |
| 12 | Sortie autorisée normale | photos comparées, sortie confirmée, parent prévenu |
| 13 | **Personne inconnue + photo de preuve** | refus · photo montée en stockage · Direction 1/2 et parent alertés · l'écran dit si le registre officiel a pris l'incident |

Et deux passages transverses : **lockdown** (aucune entrée, exception médicale
ouverte) et **l'affichage à 390 px** (déjà vérifié en simulation, à confirmer
sur un vrai écran).

### Ce que la recette réelle vérifiera que la mienne ne peut pas

- que la caméra lit vraiment un QR imprimé, sous la lumière d'un portail à 7 h ;
- que le réseau de Kinshasa ne fabrique pas de faux « hors ligne » ;
- que les RLS réelles rendent bien ce que les rôles attendent ;
- que la photo de preuve arrive vraiment dans le stockage.

---

## 4. Ce qui est fait, et ce qui reste

| point de ton audit | état |
|---|---|
| 1 · QR permanent vérifié dans le navigateur | **corrigé** — tout passe par `verify_student_card_qr`, plus aucune signature locale |
| 2 · personne inconnue absente du registre | **frontend prêt**, appel écrit et tenté — **la RPC reste à créer** (§2) |
| 3 · faux positif de notification | **corrigé** sur l'annulation ; la préparation l'était depuis #104 |
| 4 · `R.scanner` sans garde | **corrigé** depuis #104, resserré en #106 |
| 5 · cache d'accès qui garde un refus | **corrigé** — un refus ne se met plus en cache du tout |
| 6 · vue parallèle des personnes autorisées | **corrigé** — un seul filtre, celui du serveur |
| 7 · contradiction dans l'espace Parent | **corrigé** — plus aucune promesse que le serveur refuse |
| 8 · recette réelle | **PAS faite** — je ne peux pas l'exécuter (§3) |

### Trois questions ouvertes chez toi

1. **La forme exacte de `verify_student_card_qr`.** Tu as donné l'entrée et un
   code de refus, pas les champs rendus. Je lis l'identité de l'élève sur
   `mat`, `sid`/`student_id` et `student_name`, et **si rien n'y est je refuse
   en le disant** au lieu de deviner. Confirme les noms réels.
2. **`check_gate_access_status` ou `get_gate_access_status` ?** Le navigateur
   appelle le premier ; ton contrôle n° 4 de #94 cherche le second.
3. **`record_unknown_pickup_attempt`** — §2.
