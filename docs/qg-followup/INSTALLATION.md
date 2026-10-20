# Azzera Care — suivi QG 1.3.1

Correctif à installer sur la version Gestion QG 1.3 déjà en place.

Le QG voit les commentaires de chaque tâche dans la fiche intervention, ainsi
que les observations finales de chaque agent dans « Participations individuelles ».
Ces informations sont également reprises dans « Exporter la main courante ».
Les commentaires déjà enregistrés deviennent visibles sans les ressaisir.
Les informations internes restent exclues du portail et du rapport client.

Chaque nouvelle prise et fin de poste crée une notification pour les comptes
QG administrateur et responsable actifs de l'organisation, avec l'agent,
la mission, le site et l'heure de Paris. La fin d'un agent est signalée même
si un autre agent poursuit la mission. Une cloche affiche le nombre total
de notifications non lues et permet de les consulter.

## Installation — dans cet ordre

1. Conserver une sauvegarde du dépôt actuel et de la base selon ta procédure
   habituelle. Le dossier `SECOURS_LOCAL_1.3` du ZIP contient seulement les
   quatre fichiers locaux précédents, pas une sauvegarde de production.
2. Dans **Supabase → Azzera-Care → SQL Editor → nouvelle requête**, exécuter
   `docs/qg-followup/01_PREREQUIS.sql`. Les trois premières valeurs doivent
   être `true`. Si une valeur est `false`, arrêter et transmettre le résultat ;
   ne pas relancer les migrations initiales.
3. Toujours dans SQL Editor, exécuter le contenu entier du **seul nouveau fichier**
   `supabase/migrations/20261020172145_care_qg_followup.sql`.
   Il n'efface aucune donnée métier et ne renvoie pas les anciens événements.
   En cas d'erreur, arrêter et conserver le message exact.
4. Dans **GitHub → Security-maker/AzzeraCare → Add file → Upload files**,
   déposer le **contenu** du dossier `A_REMETTRE_SUR_GITHUB` à la racine du dépôt,
   puis enregistrer. Ne pas déposer ce dossier comme un nouveau sous-dossier.
   Les quatre fichiers applicatifs à remplacer sont :
   - `app.js`
   - `style.css`
   - `modules/reports.js`
   - `service-worker.js`

   Les dossiers `supabase/migrations` et `docs/qg-followup` contiennent le nouveau
   SQL et sa procédure. Attendre la fin du déploiement GitHub Pages, puis
   recharger **https://azzeracare.app**. Sur téléphone, fermer et rouvrir
   l'application après avoir chargé la mise à jour en ligne.
5. Exécuter `docs/qg-followup/02_VERIFIER.sql` dans Supabase.
   Les deux premières valeurs doivent être `true`. La troisième vérifie la
   configuration de la clé publique pour les notifications sur appareil.
6. Avec chaque compte QG qui doit recevoir les alertes : dans Azzera Care,
   ouvrir **Notifications → Activer les notifications**, autoriser sur
   l'appareil, puis **Envoyer un test**. Si l'appareil est déjà inscrit,
   utiliser directement **Envoyer un test**.

**Pas de redéploiement de `care-mcp` ou de `send-push` pour ce correctif.
Pas de réinstallation des plugins de Nacer ou Yannice.**
L'authentification, les accès des connecteurs, le domaine et les clés existantes
restent ceux de la version installée.

## Vérification métier

Utiliser une mission de test clairement identifiée et un compte agent affecté.

1. Démarrer la participation avec le compte agent.
2. Avec le compte QG, actualiser puis ouvrir la cloche :
   une notification « Prise de poste » doit ouvrir cette mission.
3. Avec l'agent, valider une tâche en ajoutant un commentaire.
   Le QG doit voir le texte dans la checklist, son auteur de validation et l'heure.
4. Terminer la participation avec une observation finale.
   Le QG doit recevoir « Fin de poste » et voir le texte dans les participations.
5. Exporter la main courante côté QG : vérifier ces deux textes.
6. Vérifier avec un compte client que ces textes internes ne sont pas exposés.

Les notifications dans l'application sont consultables immédiatement après
actualisation ; la page visible se rafraîchit aussi automatiquement toutes
les 30 secondes lorsqu'aucun formulaire n'est ouvert.
Une correction de pointage par le QG ne simule pas une nouvelle prise de poste
et ne déclenche donc pas ces nouvelles alertes.

## Si l'alerte sur téléphone n'arrive pas

Les notifications internes et les notifications du téléphone sont deux étapes
distinctes. Le correctif branche les nouveaux événements sur le système Web Push
existant. L'envoi sur appareil nécessite une configuration serveur opérationnelle.

- **Aucune notification dans l'application après une nouvelle action agent** :
  exécuter `02_VERIFIER.sql`, vérifier que le compte QG est actif et que la mission
  appartient à la même organisation. Les événements antérieurs au correctif ne
  sont pas recréés.
- **Notification interne présente, aucun appareil inscrit** : activer les
  notifications depuis l'appareil QG et autoriser dans ses réglages.
  Sur iPhone/iPad, utiliser Azzera Care ajoutée à l'écran d'accueil.
- **Notification interne présente, envois en attente** : vérifier le Cron
  d'envoi existant et **Edge Functions → send-push → Logs**.
- **Configuration push à terminer** : ne pas régénérer les clés existantes.
  La configuration initiale du système d'envoi reste nécessaire ; ce ZIP ne
  contient aucune clé privée et ne configure pas le serveur à distance.
- **Envois acceptés mais rien à l'écran** : vérifier les autorisations système,
  le mode Concentration et faire le test appareil verrouillé.
- **L'alerte ouvre l'ancienne adresse** : vérifier le paramètre serveur
  `CARE_APP_URL` de `send-push` ; l'adresse de l'application est désormais
  `https://azzeracare.app/index.html`.

## Retour au code précédent

Uniquement en cas de besoin : restaurer les quatre fichiers contenus dans
`SECOURS_LOCAL_1.3`, puis exécuter `03_RETOUR_CODE_SQL.sql`.
Ce retour retire les nouvelles alertes mais ne restaure ni n'efface les données
métier. Il ne retire pas les notifications déjà transmises à un appareil.

## Limites de validation

Les contrôles livrés sont locaux, sur des comptes et interventions de test.
Le projet Supabase distant, la réception réelle sur téléphone et les navigateurs
Safari/iOS physiques n'ont pas été testés dans cette livraison.
Les dimensions mobiles testées dans Chrome ne constituent pas un test sur iPhone.

Référence de conception : [déclencheurs PostgreSQL dans Supabase](https://supabase.com/docs/guides/database/postgres/triggers).
