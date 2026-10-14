# Vérification du patch MCP 1.2 — 14 octobre 2026

## Résultats locaux

- `node --test mcp-server/tests/*.test.mjs` : 51 tests réussis, aucun échec. Le test d’upgrade ajouté ensuite a été exécuté séparément : 1 test réussi, aucun échec, soit 52 tests au total. Journaux inclus dans le ZIP.
- Parcours du véritable SDK MCP vers SQL local : outil create_client exposé, proposition sans insertion, refus sans accord, accord via session native, création confirmée, résultat idempotent, recherche du nouveau client puis création d’un site rattaché à son identifiant.
- Droits : accès lecture seule, agent ordinaire, appels anonymes, permissions révoquées, approbation par OAuth, champs de propriété injectés et champs inconnus refusés. Les 12 outils de consultation restent seuls disponibles en lecture seule ; un compte autorisé en écriture dispose de 25 outils.
- Fiches clients : validation des longueurs, e-mail facultatif, coordonnées enregistrées, protection des organisations, doublons normalisés refusés même pour une fiche désactivée, recontrôle avant création, expiration/refus respectés. Aucun appel Auth pour créer une fiche client.
- Migration 1.1 vers 1.2 : les lignes d’une proposition de site approuvée et d’une proposition d’agent en attente sont conservées à l’identique. Le site peut être confirmé après mise à jour ; les clients deviennent disponibles.
- Concurrence sur PostgreSQL 18.4 local : 4 contrôles réussis. Une réservation Auth pour deux confirmations ; une réservation pour deux propositions du même e-mail ; un site pour deux propositions concurrentes ; un client pour deux propositions concurrentes du même nom. Aucune connexion distante.
- Page de validation dans Chrome local, largeur 390 px, Auth/RPC simulés : 10 contrôles réussis pour clients/sites/agents. Accord explicite, bon appel RPC, refus, texte HTML non exécuté, aucun débordement horizontal. Capture de validation client examinée visuellement.
- Validation planning existante : 7 contrôles navigateur réussis avec Auth/RPC simulés.
- Syntaxe des fichiers JavaScript modifiés vérifiée par Node.
- Architecture de sécurité conservée : table privée avec RLS et sans accès direct utilisateur, fonctions à search_path vide et contrôle des droits en base, finalisation Auth réservée au service_role. Aucun nouvel accès privilégié attribué. Les tests locaux ne remplacent pas les advisors de l’instance Supabase réelle.

## Limites

Aucune migration appliquée en production, aucun déploiement Supabase/GitHub, aucune création de compte réel ni essai dans le compte ChatGPT de Yannice. Les appels Supabase Auth sont simulés. Les tests PostgreSQL 18.4 locaux ne valident pas la version du serveur distant. Il reste à contrôler les outils et une création après installation.

La création de comptes agents conserve le fonctionnement 1.1 : mot de passe initial fourni par le secret serveur, aucun e-mail envoyé, aucun compte existant réinitialisé. Auth et PostgreSQL ne partagent pas une transaction : un résultat incertain bloque la proposition pour contrôle QG. Aucun changement obligatoire du mot de passe à la première connexion n’est ajouté.

Le ZIP ne contient ni mot de passe ni secret. Les copies SECOURS_LOCAL_1.1 proviennent du disque local, pas d’une sauvegarde vérifiée de production.
