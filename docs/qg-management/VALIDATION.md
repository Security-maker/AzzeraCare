# Validation locale — gestion QG 1.3

Date : 20 octobre 2026.

## Résultats

| Contrôle | Résultat et portée |
|---|---|
| Tests de l’application | 22 tests réussis (`npm test`). |
| Syntaxe et ressources | `npm run check` réussi. |
| Suite MCP et SQL | 69 tests réussis avant ajout du test de livraison ; moteur PostgreSQL local PGlite, SDK MCP réel. |
| Livraison | 1 test supplémentaire réussi : scripts SQL de diagnostic, restauration exacte des cinq anciennes fonctions, puis réinstallation. |
| Navigateur application | 10 contrôles réussis dans Chrome, avec appels aux vraies fonctions SQL locales ; authentification simulée. |
| Navigateur approbation | 8 contrôles réussis dans Chrome, Auth/RPC simulés : avant/après, checklist, pointages, avertissements de suppression/archivage/transfert, accord et refus. |
| Concurrence | 6 scénarios réussis sur PostgreSQL 18.4 local, dont suppression contre modification et répétition simultanée de suppression. |
| Découverte MCP | 32 outils avec écriture, 12 en lecture seule ; vérification finale du protocole après ajustement d’une description. |
| Dépôt de départ | Six fichiers modifiés comparés aux fichiers GitHub avant modification, identiques à des lignes vides finales près. |

Les journaux et captures sont dans `VERIFICATIONS` du ZIP. Les sources des tests sont dans `VERIFICATIONS/SOURCES_TESTS`, avec leur chemin d’origine.

## Cas métier et sécurité couverts

- Modification d’une mission terminée ; conservation des identifiants de tâches, preuves et précision des pointages inchangés.
- Ajout/retrait de tâches, correction de réalisation, mise à jour du rapport client.
- Rejet d’identifiants de tâches étrangers, dupliqués ou de dates de pointage invalides.
- Annulation intégrale d’une correction si la publication du rapport échoue.
- Suppression d’intervention, détachement des demandes liées, conservation de l’audit.
- Modification, archivage, restauration des clients/sites/agents et blocage d’un agent désactivé.
- Cloisonnement entre organisations, refus d’élévation de rôle et des appels directs aux fonctions privées.
- Conservation de la lecture seule du connecteur Nacer.
- Approbation humaine distincte, refus des propositions périmées et répétition sans doublon.
- Requêtes MCP natives pour les nouvelles opérations, puis vérification réelle des effets en SQL.
- Réexécution de la migration sans écrasement de la sauvegarde initiale des fonctions.

## Reproduire dans le projet complet

Avec les dépendances du projet et de `mcp-server` installées :

```sh
npm test
npm run check
node --test mcp-server/tests/*.test.mjs
node mcp-server/tests/management-ui.mjs
node mcp-server/tests/ui.mjs
node mcp-server/tests/concurrency.mjs
```

Les tests navigateur utilisent Chrome installé. Le test de concurrence utilise PostgreSQL embarqué. Les tests ne se connectent pas à la production.

## Limites explicites

- Pas de déploiement GitHub Pages ou Supabase réalisé par cette intervention.
- Pas de validation de l’authentification OAuth ni des droits réels de Yannice dans le serveur distant.
- Pas de test sur une session ChatGPT réelle après déploiement.
- Pas de test sur un téléphone physique ; contrôle mobile à 390 px dans Chrome.
- La restauration du code SQL ne restaure pas les données supprimées. Le nettoyage définitif des fichiers Storage et la suppression des comptes Auth ne sont pas implémentés ici.
- Les fichiers complets remplacent les six fichiers de départ vérifiés ; toute modification ultérieure de ces fichiers doit être fusionnée avant installation.
