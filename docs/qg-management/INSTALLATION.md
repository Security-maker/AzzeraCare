# Azzera Care — gestion QG 1.3

Ce patch part de la version MCP 1.2 avec création des clients, sites et agents. Il ajoute la modification des interventions déjà commencées ou terminées, leur checklist, leurs pointages et leur suppression. Les clients, sites et agents peuvent être modifiés, archivés et restaurés.

## Ce que fait la suppression

- **Intervention** : suppression de la fiche, des tâches, affectations, pointages et du rapport publié. Les demandes client liées sont détachées et marquées annulées. Une copie avant suppression est conservée dans l’audit privé QG. Les fichiers restent dans le stockage privé ; ils ne sont pas purgés par ce patch.
- **Client, site ou agent** : retrait des listes courantes par archivage et désactivation. Les historiques et affectations sont conservés. Le bouton **Archives** permet la restauration. Les missions existantes ne sont pas automatiquement annulées ; réattribuer les missions d’un agent désactivé si nécessaire.
- Les comptes QG restent protégés. La modification de l’e-mail de connexion et du mot de passe d’un agent ne fait pas partie de ce patch.

Une correction d’intervention déjà publiée recalcule le rapport client. Si la publication échoue, la correction est annulée dans la même transaction. Un changement de client d’un site transfère aussi la visibilité de son historique : un motif est obligatoire.

## 1. Vérifier et sauvegarder

1. Conserver une sauvegarde de la base et télécharger la fonction `care-mcp` actuellement déployée. Le dossier `SECOURS_LOCAL_1.2` contient les anciens fichiers locaux, pas une sauvegarde du serveur Supabase.
2. Dans **Supabase → SQL Editor → New query**, exécuter `01_PREREQUIS.sql`.
3. Les contrôles de la première requête doivent être vrais. Yannice doit être actif, QG, autorisé au MCP et à l’écriture. Si ce n’est pas le cas, arrêter et transmettre les résultats : ce patch ne modifie pas les autorisations individuelles.
4. Terminer ou abandonner les propositions ChatGPT en attente. Après installation, demander une nouvelle proposition pour toute modification.

Les six fichiers de départ modifiés ont été comparés au dépôt GitHub `Security-maker/AzzeraCare` le 20 octobre 2026 : ils correspondaient, à des lignes vides finales près. Les définitions SQL et la fonction Edge de production n’ont pas été vérifiées à distance. Si tu as modifié ces fichiers depuis, fusionner les changements avant de les remplacer.

## 2. Installer le SQL

Dans **Supabase → SQL Editor → New query**, copier tout le fichier :

`A_REMETTRE_SUR_GITHUB/supabase/migrations/20261020142523_care_qg_full_management.sql`

Cliquer sur **Run**. Exécuter uniquement cette nouvelle migration, pas toutes les anciennes. Elle est transactionnelle : en cas d’erreur, arrêter ici et transmettre le message exact. Ne pas supprimer de table pour contourner l’erreur.

Cette migration conserve les données métier existantes et ajoute les champs d’archivage. Elle sauvegarde les cinq anciennes fonctions remplacées pour permettre un retour du code SQL à l’état précédent.

## 3. Mettre à jour GitHub

Dans le dépôt **Security-maker/AzzeraCare**, déposer le **contenu** du dossier `A_REMETTRE_SUR_GITHUB` à la racine, en conservant ses sous-dossiers. Ne pas créer un dossier portant ce nom dans le dépôt.

Cela remplace notamment :

- `app.js` et `service-worker.js` ;
- `mcp-auth/app.js` et `mcp-auth/index.html` ;
- les fichiers de la fonction `supabase/functions/care-mcp` ;
- ajoute la migration et cette documentation.

Ne pas remplacer `config.js`, `CNAME`, les logos ou les secrets. Attendre la fin du déploiement GitHub Pages.

## 4. Déployer la fonction Supabase

**Supabase → Edge Functions → care-mcp → Code** : remplacer les cinq fichiers par ceux du ZIP :

1. `index.ts`
2. `core/handler.mjs`
3. `core/tools.mjs`
4. `core/time.mjs`
5. `core/directory.mjs`

Puis cliquer sur **Deploy updates**.

Déposer les fichiers sur GitHub ne met pas à jour la fonction Supabase. Conserver les variables d’environnement, le mot de passe initial configuré et les paramètres OAuth existants.

## 5. Contrôler le résultat

1. Dans SQL Editor, exécuter `02_VERIFIER.sql`. Les contrôles SQL doivent être vrais. Ce contrôle ne teste pas les fichiers déployés ni la liste des outils réellement reçue par ChatGPT.
2. Fermer les anciens onglets Azzera Care, rouvrir `https://azzeracare.app` et actualiser la page. Pour la PWA, fermer puis rouvrir l’application après la mise à jour.
3. Avec un compte QG, ouvrir une intervention → **Modifier l’intervention** : la checklist doit être éditable, y compris sur une mission terminée. La suppression demande un motif et une confirmation.
4. Dans **Clients**, **Sites** et **Équipe**, vérifier la présence des actions de modification, suppression et **Archives**.
5. Dans les paramètres du connecteur de Yannice, actualiser les outils si cette action est proposée, puis ouvrir une nouvelle conversation avec Azzera Care activé. La version serveur est `1.3.0` : **32 outils, dont 20 d’écriture et 12 de lecture**.
6. Vérifier notamment `delete_intervention`, `update_client`, `delete_client`, `update_site`, `delete_site`, `update_agent`, `delete_agent`. Pas besoin de recréer le plugin ni le client OAuth.

Le connecteur Nacer configuré en lecture seule reste à **12 outils de lecture**. Les comptes QG dans l’application disposent des nouvelles actions ; les droits des agents et clients restent limités à leur rôle.

### Test conseillé après installation

Utiliser une intervention fictive identifiée comme test, avec des données de test :

1. Modifier son intitulé et ajouter une tâche dans l’application ; rouvrir pour vérifier l’enregistrement.
2. Dans ChatGPT avec Yannice : demander une modification de cette tâche. Ouvrir le lien de validation Azzera, vérifier les différences, autoriser puis demander à ChatGPT de confirmer.
3. Demander la suppression de cette seule intervention de test ; vérifier le résumé, autoriser puis confirmer. Vérifier sa disparition dans l’application.
4. Tester l’archivage et la restauration d’une fiche de test.

Une proposition ou son approbation seule n’applique rien. L’exécution confirmée est nécessaire. Une proposition périmée ou une fiche modifiée entre-temps nécessite une nouvelle proposition.

## Si les nouveaux outils manquent

Vérifier d’abord que **Deploy updates** a été effectué avec les cinq fichiers et que le compte de Yannice possède encore le droit d’écriture. Si la liste présente toujours 25 outils, transmettre la version déployée et la liste visible des outils. Une réinstallation du plugin ne remplace pas le déploiement de la fonction.

## Retour arrière

`03_RETOUR_CODE_SQL.sql` restaure les définitions SQL sauvegardées à l’installation et retire les nouveaux déclencheurs de révision. Restaurer ensuite les six fichiers du dossier `SECOURS_LOCAL_1.2` sur GitHub et les deux anciens fichiers `handler.mjs`/`tools.mjs` dans `care-mcp`, puis redéployer. Les trois autres fichiers Edge n’ont pas changé.

Ce retour arrière restaure le **code**, pas les données supprimées. Il ne réactive pas les fiches archivées et ne restaure pas une intervention supprimée. Les colonnes et audits restent conservés. Restaurer des données nécessite une opération distincte à partir d’une sauvegarde ou de l’audit.

## Vérifications réalisées

Voir `VALIDATION.md`. Tous les tests de ce paquet sont locaux. Aucun changement n’a été appliqué à la production et aucun enregistrement réel n’a été modifié.
