# Vérification du patch MCP 1.1 — 14 octobre 2026

## Résultats obtenus en local

- `node --test mcp-server/tests/*.test.mjs` : **45 tests réussis, 0 échec**. La nouvelle migration est chargée avant les tests existants : planning, rapports, rôles, isolation, hook OAuth et conservation des fichiers des portails.
- Parcours SDK MCP → SQL : création de site préparée, refus sans accord, accord humain puis création effective et lecture du site ; préparation d'agent et refus des champs mot de passe/rôles privilégiés.
- SQL exécuté dans PGlite : refus inter-organisation et lecture seule, rôle limité à agent/chef d'équipe, anti-doublon, idempotence, expiration, interdiction d'approbation OAuth, finaliseur inaccessible aux utilisateurs, résultats incertains bloqués, révocation pendant la création Auth.
- Création Auth simulée : vérification de `createUser`, mot de passe fourni uniquement côté serveur, `email_confirm: true`, aucune API d'invitation appelée, aucune fuite des erreurs administratives ou du mot de passe dans les résultats.
- `node mcp-server/tests/directory-concurrency.mjs` : **3 contrôles réussis** sur PostgreSQL **18.4** local. Une seule réservation pour deux confirmations, une seule création réservée pour deux propositions de même e-mail, un seul site pour deux confirmations concurrentes. Zéro connexion distante.
- `node mcp-server/tests/directory-ui.mjs` : **7 contrôles réussis** dans Chrome local à largeur 390 px avec Auth/RPC simulés : accord explicite obligatoire, rendu des deux créations, pas d'exécution de HTML fourni comme données, refus, absence de débordement horizontal. Capture agent examinée visuellement.
- `node mcp-server/tests/ui.mjs` : contrôle de non-régression de la validation planning, **7 contrôles réussis**, avec Auth/RPC simulés.

## Limites

Le Supabase de production indiqué dans la conversation est PostgreSQL 17.6. Le test de concurrence a utilisé PostgreSQL 18.4 local ; il ne constitue pas un test de production. Aucun compte réel n'a été créé, aucun secret configuré, aucune migration appliquée à distance, aucun fichier poussé sur GitHub. La connexion effective d'un nouvel agent et l'actualisation des outils dans ChatGPT Business restent à vérifier après installation.

L'appel Auth puis l'insertion du profil ne peuvent pas partager une transaction SQL. Après une réponse incertaine, le plan reste bloqué pour contrôle QG au lieu de répéter la création ou d'annoncer un succès non vérifié. Aucune suppression automatique de compte.

Le secret du mot de passe initial n'est pas dans le ZIP. Aucun changement obligatoire de mot de passe à la première connexion n'a été ajouté.
