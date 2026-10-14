# Patch MCP 1.2 — création de clients, sites et comptes agents

Ce patch s'ajoute à Azzera Care V3 avec le connecteur MCP 1.0 déjà installé. Il conserve le planning, les réglages OAuth, les comptes et les droits existants. Aucun déploiement distant n'a été effectué pendant sa préparation.

## Résultat

- `create_client` prépare une fiche client : nom obligatoire, e-mail de contact, téléphone et contacts facultatifs. Aucun compte utilisateur ni e-mail envoyé. Une fois le client confirmé, utiliser son identifiant pour créer son site avec une seconde proposition. L’adresse de l’établissement est un champ du site.

- `create_site` prépare un site pour un client actif déjà présent : nom, adresse, consignes générales et contacts facultatifs. Aucun code d'accès n'est exposé par cet outil.
- `create_agent` prépare un compte agent ou chef d'équipe avec nom et adresse e-mail de connexion. Il crée directement le compte, sans envoi d'e-mail, avec le mot de passe initial configuré côté serveur. Le rôle « agent » n'enregistre pas un statut salarié/sous-traitant.
- `confirm_directory_creation` exécute uniquement la proposition approuvée sur la page Azzera par son auteur. Une proposition vaut dix minutes. Le mot de passe ne figure jamais dans les arguments ou les résultats des outils.
- Les droits existants décident qui peut utiliser ces outils. Nacer reste en lecture seule si son accès l'était ; Yannice peut écrire si son accès MCP et son droit d'écriture sont actifs. Aucun droit n'est activé par ce patch.

Un compte existant n'est jamais réinitialisé, réinvité ou rattaché automatiquement. Un site du même nom pour le même client est refusé pour éviter une création involontaire en double.

## 1. Sauvegarder

Télécharger le code actuellement déployé de `care-mcp` dans Supabase et conserver les fichiers GitHub actuels de `mcp-auth`. Les fichiers de secours inclus dans le ZIP proviennent de la copie locale ; ils ne remplacent pas cette sauvegarde de production.

## 2. GitHub

Le ZIP conserve les créations sites/agents 1.1 et ajoute les clients. Il ne faut pas reprendre les anciens fichiers après cette mise à jour.

Dans le ZIP, ouvrir `A_REMETTRE_SUR_GITHUB`. Copier son CONTENU à la racine du dépôt AzzeraCare, en conservant les sous-dossiers `mcp-auth`, `supabase`, `mcp-server` et `docs`. Ne pas ajouter le dossier A_REMETTRE_SUR_GITHUB lui-même comme niveau supplémentaire.

Remplacer les fichiers de mêmes chemins. Ne pas remplacer le `config.js` public existant : il n'est pas inclus dans ce patch. Ne pas remplacer le fichier principal `app.js` à la racine : seul `mcp-auth/app.js` est modifié.

Si GitHub Pages utilise un dossier de publication distinct, reporter `mcp-auth/app.js`, `mcp-auth/index.html` et `mcp-auth/style.css` dans son dossier `mcp-auth`. Attendre la fin du déploiement Pages.

## 3. SQL Supabase

Dans le projet Azzera-Care → SQL Editor, exécuter `docs/mcp/directory/VERIFIER.sql`. La ligne `prerequis_mcp` doit être vraie.

- Si `preparation_installee`, `validation_installee`, `execution_installee` et `finalisation_installee` sont vraies, le patch sites/agents 1.1 est installé : exécuter **uniquement** `supabase/migrations/20261014191808_care_mcp_client_creation.sql`.
- Si ces quatre fonctions sont absentes, exécuter d’abord `supabase/migrations/20261014160126_care_mcp_directory_creation.sql`, puis `supabase/migrations/20261014191808_care_mcp_client_creation.sql`, dans cet ordre.
- Si seules certaines fonctions sont présentes, arrêter l’installation et transmettre le résultat de VERIFIER.sql pour diagnostic. Ne pas supprimer de table.

Pour chaque fichier nécessaire : copier tout son contenu dans une nouvelle requête SQL puis Run. La migration 1.2 étend les créations autorisées aux fiches clients et conserve les propositions sites/agents existantes. Ne pas rejouer les autres migrations. Relancer VERIFIER.sql : `creation_clients_installee` doit être vraie. Ce contrôle SQL ne prouve pas que la fonction Edge et la page GitHub Pages ont été mises à jour.

## 4. Mot de passe initial côté serveur

Supabase → Edge Functions → Secrets : ajouter le secret :

`CARE_MCP_INITIAL_AGENT_PASSWORD`

Valeur : le mot de passe initial commun convenu avec Nacer dans la conversation. Le saisir directement dans Supabase, sans le mettre dans GitHub, dans une description du plugin ou dans une requête ChatGPT.

Ce mot de passe s'applique uniquement aux NOUVEAUX comptes créés par ce connecteur. Les mots de passe existants ne changent pas. Le patch ne force pas un changement de mot de passe à la première connexion : le mot de passe commun doit être changé par l'utilisateur via le parcours habituel.

`SUPABASE_SERVICE_ROLE_KEY` est utilisé uniquement à l'intérieur de la fonction pour créer le compte Auth, jamais dans le navigateur ou dans les réponses MCP. Conserver les secrets existants CARE_MCP_URL et CARE_MCP_REVIEW_URL.

## 5. Déployer la fonction Supabase

GitHub Pages ne déploie PAS les Edge Functions.

Supabase → Edge Functions → `care-mcp` → Code : remplacer/ajouter exactement ces cinq fichiers depuis le patch :

- `index.ts`
- `core/handler.mjs`
- `core/tools.mjs`
- `core/time.mjs`
- **`core/directory.mjs` (nouveau)**

Le nom de la fonction reste **care-mcp**. Ne pas saisir le nom d'un fichier comme nom de fonction. Cliquer sur Deploy updates. Conserver la vérification JWT de passerelle désactivée comme sur la fonction MCP existante : la signature et les droits sont vérifiés dans le serveur et les fonctions SQL. Ne changer ni les fonctions `create-user` et `invite-user`, ni le hook OAuth, ni le client OAuth.

## 6. Vérifier dans ChatGPT

Après les déploiements, actualiser les outils du connecteur si cette action est proposée dans son interface. Ouvrir une nouvelle conversation et sélectionner le connecteur. Si create_client reste absent, vérifier d’abord le fichier core/tools.mjs réellement déployé et les droits du compte ; une reconnexion seule ne remplace pas ce déploiement. Conserver le plugin et le client OAuth existants.

Avec Yannice, demander :

> Liste les outils du connecteur Azzera. Vérifie la présence de create_client, create_site, create_agent et confirm_directory_creation.

Commencer avec une fiche de test :

> Recherche le client TEST CONNECTEUR. S’il est absent, utilise create_client pour préparer sa création. Donne-moi le lien de validation.

Ouvrir le lien Azzera, vérifier « Créer un client », cocher et autoriser. Revenir dans ChatGPT et demander l’exécution de cette proposition. Vérifier `applied: true` et le `client_id` retourné, puis contrôler la fiche dans Azzera Care. Rechercher ce client avec `list_clients` avant de créer son site.

Puis tester avec ce client et une adresse e-mail de test que tu contrôles :

> Prépare la création du site [NOM DE TEST] pour le client [CLIENT EXISTANT], sans intervention. Donne-moi le lien de validation.

Ouvrir le lien, vérifier les champs, cocher et autoriser. Revenir dans ChatGPT :

> Exécute la proposition que je viens d'approuver.

Attendre `applied: true` puis vérifier le site dans Azzera Care. Pour l'agent :

> Prépare un compte agent [NOM DE TEST], adresse [ADRESSE DE TEST], sans envoi d'e-mail. Donne-moi le lien de validation.

Même parcours de validation puis confirmation. Vérifier le profil dans Azzera et le compte dans Authentication → Users. Tester la connexion avec le mot de passe initial configuré. Cette création ne doit envoyer aucun e-mail. Avec Nacer en lecture seule, les quatre outils de création et confirmation ne doivent pas être disponibles.

## Erreurs

- `MCP_INITIAL_PASSWORD_NOT_CONFIGURED` : ajouter le secret à l'étape 4 (12 à 128 caractères), puis réessayer le même plan avant son expiration.
- `MCP_ADMIN_CONFIGURATION_REQUIRED` : configuration serveur manquante. Ne jamais coller une clé privilégiée dans ChatGPT.
- `MCP_APPROVAL_REQUIRED_OR_EXPIRED` : approuver la proposition, ou refaire une proposition si elle a expiré.
- `MCP_ACCOUNT_ALREADY_EXISTS_USE_QG` : gérer le compte existant dans le portail QG. Aucun mot de passe existant n'est remplacé.
- `MCP_CLIENT_ALREADY_EXISTS` : vérifier et utiliser la fiche client existante, y compris si elle est désactivée ; ne pas modifier son nom pour contourner le contrôle.
- `MCP_SITE_ALREADY_EXISTS` : utiliser le site existant après vérification.
- `MCP_ACCOUNT_CREATION_REQUIRES_REVIEW` / `outcome_unknown` : ne pas recréer de proposition pour cette adresse. Auth et PostgreSQL sont deux opérations distinctes. Un délai d'attente peut survenir après la création du compte. Le verrou empêche alors une seconde création automatique. Exécuter VERIFIER.sql, vérifier Authentication → Users et le profil Azzera avec le QG ; conserver le plan et son identifiant pour le diagnostic. Le patch ne supprime jamais automatiquement un compte après un résultat incertain.

## Retour arrière

Pour arrêter uniquement ces nouveaux outils, exécuter `DESACTIVER.sql` puis remettre la sauvegarde précédente du code care-mcp et de mcp-auth. Les données déjà créées restent présentes. Le planning et les droits existants ne sont pas supprimés. Pour réactiver les fonctions sans rejouer la migration, utiliser `REACTIVER.sql` et remettre les fichiers du patch.

## Vérifications locales et limites

Voir VERIFICATION.md. Les tests Auth utilisent des réponses simulées ; aucune création de compte réel, aucun envoi d'e-mail et aucun test dans le compte ChatGPT Business de Yannice n'ont été effectués pendant la préparation.

Référence de l'API d'administration : https://supabase.com/docs/reference/javascript/auth-admin-createuser
