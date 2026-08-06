# Loi de coordination — découverte et création des fonctionnalités

Date de décision : 6 août 2026  
Décision : Loms

## Objectif

Aller plus vite, éviter les doublons et empêcher ChatGPT et Claude de développer la même fonctionnalité séparément.

## Règle obligatoire

### ChatGPT

ChatGPT doit :

1. analyser l’application, Supabase, les rôles et les parcours existants ;
2. détecter les fonctionnalités utiles qui manquent ou les défauts de fonctionnement ;
3. proposer à Claude une spécification claire, avec rôles, écrans, boutons, règles et critères d’acceptation ;
4. ne pas créer l’interface que Claude doit construire ;
5. intervenir sur le backend uniquement lorsqu’un contrat serveur, une migration, une RPC, une Edge Function, une RLS ou une correction de sécurité est nécessaire ;
6. auditer ensuite le travail de Claude et tester sa conformité.

### Claude

Claude doit :

1. créer l’interface et les parcours proposés ;
2. ajouter les boutons, formulaires, affichages et messages ;
3. connecter l’interface aux fonctions serveur validées ;
4. exécuter les tests navigateur et les audits ;
5. publier sur une branche et ouvrir une Pull Request avant fusion sur `main` ;
6. signaler à ChatGPT les besoins backend exacts au lieu de recréer une base parallèle.

## Ordre de travail

1. Diagnostic ChatGPT.
2. Proposition fonctionnelle à Claude dans une issue dédiée.
3. Conception et implémentation Claude.
4. Définition ou correction backend ChatGPT seulement si nécessaire.
5. Recette complète Claude + ChatGPT.
6. Fusion et publication.

## Interdictions

- pas de double développement de la même fonctionnalité ;
- pas de modification directe de `main` pour une nouvelle interface avant revue ;
- pas de création d’un deuxième système de données lorsque le backend existant peut être étendu ;
- pas de fonctionnalité importante sans issue ou contrat écrit ;
- pas d’annonce « terminé » avant tests serveur et navigateur.

## Exemple validé

P0-8 — cartes élèves : ChatGPT a détecté les besoins de registre annuel, duplicata, déclaration de perte, renouvellement, historique et QR permanent. Claude doit créer l’interface correspondante dans l’issue nº 63. ChatGPT auditera et fournira uniquement le backend nécessaire après le contrat d’interface.
