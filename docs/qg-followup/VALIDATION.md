# Validation locale — suivi QG 1.3.1

Vérifications réalisées le 20 octobre 2026 sur la copie locale.
Aucune requête sur la base de production, aucun push GitHub et aucun déploiement
Supabase n'ont été effectués.

| Contrôle | Résultat |
|---|---|
| Syntaxe, imports et ressources de l'application | Réussi |
| Tests applicatifs, dont confidentialité des rapports | 23 réussis |
| Suite SQL/MCP, incluant le suivi QG et ses diagnostics | 81 réussis |
| Parcours Chrome avec appels métier vers la base locale | 7 contrôles réussis |
| Pointages concurrents sur PostgreSQL 18.4 local | 3 contrôles réussis |

Couverture du correctif :

- lecture des commentaires par QG administrateur et responsable, avec affichage
  des retours à la ligne et échappement du contenu HTML ;
- observations finales par agent, également dans l'export interne ;
- commentaires conservés dans l'espace agent et exclus des données client ;
- prise et fin de poste : destinataires actifs de la même organisation uniquement ;
- alerte de fin individuelle avant la fin de la mission multi-agents ;
- retries et appels concurrents sans nouvelles notifications en double ;
- absence d'alerte après refus ou annulation de transaction ;
- silence des corrections de pointage QG et prévisualisations MCP ;
- mise en file des push pour les appareils inscrits, annulation après révocation ;
- installation et réinstallation sans envoi de l'historique ;
- scripts de diagnostic et restauration du prédicat SQL précédent ;
- cloche, compteur, marquage comme lu, ouverture de mission ;
- rendu Chrome à 1440, 390 et 320 pixels sans débordement horizontal.

Le navigateur utilise une session d'authentification simulée localement.
Les opérations métier et les snapshots utilisés par ce navigateur passent
par les fonctions SQL réelles chargées dans PGlite. Les contrôles de concurrence
utilisent deux connexions à une instance PostgreSQL 18.4 temporaire locale.
Les appareils push des tests sont synthétiques : aucun envoi externe.

Les sources et journaux sont fournis dans `VERIFICATIONS` dans le ZIP.
L'ancien contrôle d'identité intégrale de la feuille CSS a été adapté :
le contenu CSS antérieur reste strictement identique ; les règles de la 1.3.1
sont ajoutées à la fin. La suite complète est passée après cette adaptation.

La réception réelle des notifications, la configuration de `send-push` et du
Cron distants, ainsi que les appareils Safari/iOS physiques restent à vérifier
avec la procédure d'installation. Un résultat local ne prouve pas leur état.
