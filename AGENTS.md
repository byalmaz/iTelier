# Consignes pour les agents (Codex, Claude Code)

Codex lit ce fichier automatiquement ; Claude Code le lit via `CLAUDE.md`, qui l’importe. Plusieurs agents travaillent parfois en même temps dans ce même dossier, sans branches séparées : ces règles évitent qu’un agent écrase le travail d’un autre. Le reste de la documentation du projet (README, `CONTRIBUTING.md`, `docs/`) s’applique aussi.

## Coordination entre agents

1. **Lire `.agents/claims.md` avant toute modification.** Ne pas modifier un fichier ou dossier réservé par un autre agent tant que sa ligne est `en cours`. En cas de besoin, s’arrêter et le signaler à l’utilisateur plutôt que de passer outre.
2. **Réserver avant d’écrire.** Ajouter une ligne au tableau de `.agents/claims.md` (créer le fichier s’il manque) avec la date, l’agent, les fichiers précis et la tâche. Réserver des fichiers, pas tout un dossier, sauf pour `dist/`.
3. **Relire juste avant d’éditer.** Un fichier peut avoir changé depuis la dernière lecture. Si son contenu ne correspond plus, relire et refaire la modification, ne jamais réécrire depuis une copie ancienne.
4. **Modifier par petits patchs ciblés.** Pas de réécriture complète d’un fichier existant (`cat > fichier`, écriture intégrale), pas de reformatage global, pas de renommage de masse.
5. **Ne pas annuler le travail d’un autre agent**, même s’il semble inachevé ou casse la compilation : le signaler dans `.agents/claims.md` et à l’utilisateur.
6. **Un seul build à la fois.** Réserver `dist/` avant `bash scripts/build-app.sh` ; ce script remplace `dist/ReScope.app`.
7. **Libérer en fin de tâche.** Passer sa ligne à `terminé` avec un résumé d’une ligne et les tests lancés.
8. **Git.** Ne pas committer, pousser, réinitialiser ou réécrire l’historique sans demande explicite de l’utilisateur.

Une réservation `en cours` de plus de 2 heures sans modification des fichiers concernés peut être considérée comme abandonnée : vérifier les dates de modification, puis demander à l’utilisateur avant de la reprendre.

### Fichiers partagés et conventions anti-conflit

- **Tests** : ajouter les nouveaux tests dans un fichier par domaine (`Tests/ReScopeCoreTests/<Domaine>Tests.swift`), plutôt que d’allonger `CoreValidationTests.swift`. `scripts/test-core.sh` exécute tous les fichiers du dossier ; chaque fichier déclare exactement une classe `XCTestCase`, avec des méthodes `test…()` sans paramètre.
- **Traductions** (`Sources/ReScopeCore/EnglishStrings.swift`) : uniquement des ajouts de lignes, jamais de tri ni de réorganisation. Toute nouvelle chaîne `L("…")` visible reçoit sa traduction anglaise.
- **Fichiers centraux** (`AppModel.swift`, `Package.swift`, `scripts/build-app.sh`) : modifications minimales et réservation obligatoire.

## Commandes

```sh
bash scripts/test-core.sh            # tests du cœur sans XCTest ni appareil
python3 scripts/test-restore-host.py # helper de restauration avec un moteur inerte
swift build --product iTelier        # compilation de l’interface
bash scripts/build-app.sh            # bundle complet dans dist/ (réserver dist/)
```

Ne jamais lancer de restauration, de sauvegarde ou de commande USB sur un appareil réel sans demande explicite de l’utilisateur.

## Règles de sécurité à préserver

- Processus : arguments structurés via `ProcessRunner`, jamais de shell ni de commande interpolée. Les identifiants issus de l’appareil (UDID, ECID, noms de pilotes) sont validés avant d’être passés en argument.
- Secrets : un mot de passe ne passe jamais dans les arguments, l’environnement, les journaux, les rapports ou sur disque. Il transite par un pipe (`standardInput`) ; `ps eww` affiche l’environnement de départ d’un processus à tout programme de la même session.
- `ReScopeRestoreHost` : aucune variable d’environnement ni option ne doit choisir le moteur ; le moteur est résolu depuis l’exécutable réel du helper, pas depuis `argv[0]`. Les requêtes restent à usage unique (`O_EXCL`) et les arguments canoniques.
- IPSW : `/usr/bin/unzip` interprète `*`, `?`, `[` et `]` dans le nom de l’archive. Passer par `FileFingerprint.read`, qui refuse ces chemins, avant tout appel à `unzip`.
- Réseau : téléchargements en HTTPS uniquement vers des hôtes Apple, redirections comprises ; les catalogues tiers ne fournissent que des métadonnées.
- Données personnelles : numéros de série, UDID, ECID, IMEI et adresses réseau sont masqués par défaut dans les exports et absents des rapports d’incident. L’écran Informations de l’appareil et la vue d’ensemble les affichent en clair : choix produit validé, ne pas les masquer. Fichiers privés en 0600, dossiers en 0700.

## Langue

Documentation, commentaires de doc et interface en français ; traduction anglaise dans `EnglishStrings.swift`.
