# Architecture de iTelier

iTelier est une application macOS native. SwiftUI porte la présentation ; un module de cœur indépendant représente les appareils, interprète les données et appelle les utilitaires USB. Swift Package Manager construit l’exécutable et lance les tests du cœur.

## Frontières

```text
SwiftUI / état observable
        │
        ▼
iTelierCore
 ├─ détection des appareils et modes USB
 ├─ collecte et interprétation des valeurs du Check
 ├─ catalogue des modèles et versions iOS/iPadOS
 ├─ téléchargement HTTPS des IPSW Apple
 ├─ validation du manifeste IPSW
 ├─ préparation et suivi de la restauration
 └─ exécution de processus avec arguments structurés
        │
        ▼
idevice_id · ideviceinfo · idevicediagnostics · irecovery · idevicerestore
        │
        ▼
iPhone / iPad connecté par USB
```

Le cœur ne lie pas directement les bibliothèques C. Il utilise les exécutables inclus dans le bundle (ou une installation externe de repli) et interprète leurs résultats. Cette frontière permet d’utiliser des résultats simulés dans les tests. Elle exige néanmoins de suivre les changements de leurs formats et options.

`Models.swift` définit les instantanés, les états du Check et l’approbation de restauration. `ProcessRunner.swift` résout les outils, lance les processus sans shell, lit leurs deux sorties en parallèle et limite la mémoire du journal. `AppModel.swift` gère l’état observable de l’interface, les confirmations, le mode de démonstration et l’export.

`FirmwareCatalog` lit les métadonnées de versions sur IPSW.me et AppleDB et `FirmwareDownloader` transfère le fichier depuis une source Apple. Ces deux services réseau sont distincts des utilitaires USB ; consulter le catalogue ou télécharger un fichier ne nécessite pas les bibliothèques externes iOS.

## Check

La lecture d’un appareil en mode normal passe par les services exposés par libimobiledevice. L’appareil doit être déverrouillé et approuvé par le Mac. Un résultat conserve sa disponibilité ; l’absence d’une clé ne devient pas une preuve de panne. Les résultats automatiques ne certifient pas l’origine des pièces et les contrôles manuels restent identifiés comme tels.

Le mode démonstration donne un jeu de valeurs synthétiques à l’interface. Il doit rester visible dans l’état de l’app et isolé du parcours réel de restauration.

L’export JSON indique la version de schéma, la date, le caractère fictif ou réel du rapport et l’inclusion éventuelle d’identifiants. Il ne publie ni le dictionnaire brut des valeurs de l’appareil ni les journaux. Le journal d’activité reste en mémoire pendant la session.

## Catalogue et téléchargement

Le catalogue interroge `https://api.ipsw.me/v4/devices?type=ipsw`, filtre les familles iPhone et iPad, puis lit `https://api.ipsw.me/v4/device/{identifier}?type=ipsw` pour le modèle choisi. Cette dernière route, vérifiée en direct, donne les mêmes données que la route `https://api.ipsw.me/v4/ipsw/device/{identifier}` décrite dans le [schéma Swagger officiel](https://api.ipsw.me/v4/docs/swagger.json). Le service demande un usage raisonnable et applique des limites de débit ; l’app charge les données sur demande et permet leur actualisation explicite.

Un résultat contient notamment `version`, `buildid`, `filesize`, `url`, `signed`, les dates et les empreintes `sha256sum`, `sha1sum` ou `md5sum`. Ces valeurs constituent des métadonnées tierces. L’interface associe le statut de signature à la date de chargement ; elle ne le présente pas comme un ticket de restauration Apple.

La requête de versions porte uniquement sur l’identifiant générique du modèle. Le catalogue n’envoie ni UDID, ECID, numéro de série ni données du Check. Le téléchargement utilise ensuite directement l’URL de l’IPSW : HTTPS et domaine `apple.com` ou `cdn-apple.com`, y compris leurs sous-domaines, sont exigés ainsi que pour toute redirection. Les entrées en HTTP ou hors de ces domaines sont filtrées. Les hôtes de téléchargement Apple sont décrits dans [la documentation réseau Apple](https://support.apple.com/fr-fr/101555).

L’application crée `~/Downloads/iTelier` au premier téléchargement, sans panneau de choix. Une préférence permet de changer ce dossier dans Configuration. `URLSession` suit la progression et permet l’annulation. Le transfert vérifie l’espace disque disponible, utilise un emplacement intermédiaire et ne remplace pas un fichier existant. Seul un résultat HTTP 200 de la taille attendue est accepté. Après transfert, le SHA-256 attendu, lorsqu’il existe dans le catalogue, est comparé. L’inspection calcule ensuite le SHA-256 local et lit `BuildManifest.plist` ; la version, le build et le modèle attendus doivent correspondre. Si le catalogue ne fournit pas de SHA-256, l’empreinte locale identifie le fichier sans constituer une comparaison avec une référence distante. La reprise d’un téléchargement interrompu n’est pas encore implémentée. La restauration reste une opération séparée, avec ses propres préconditions et confirmation du mode choisi.

Les versions publiques, bêtas et non signées sont affichées par défaut, avec filtres explicites. Les non signées peuvent être téléchargées pour archivage ; la provenance du fichier conserve cette information et bloque le lancement d’une restauration standard dans l’interface. L’import local ne déduit pas un état de signature du nom du fichier ; son état reste inconnu et contrôlé par le moteur. Apple reste l’autorité finale pour la signature du firmware au moment de l’opération.

Lors de la recherche du 1er octobre 2026, les catalogues `iPhone16,1` et `iPad14,3` ont fourni des URLs HTTPS sur `updates.cdn-apple.com`. Une requête HEAD sur une URL iPhone a répondu HTTP 200, avec une taille et une empreinte SHA-256 identiques aux métadonnées. Cet essai n’a pas téléchargé le corps du firmware et ne valide pas une restauration. Les exemples publics sont accessibles via [le catalogue iPhone](https://api.ipsw.me/v4/device/iPhone16,1?type=ipsw) et [le catalogue iPad](https://api.ipsw.me/v4/device/iPad14,3?type=ipsw).

## Restauration

Le fichier local est lu comme une archive IPSW. Son `BuildManifest.plist` fournit les identifiants de produit et les variantes prises en charge. Cette validation locale ne confirme pas la disponibilité d’un ticket de signature Apple.

`/usr/bin/unzip` interprète `*`, `?`, `[` et `]` dans le nom de l’archive comme un motif : avec `a[b].ipsw`, il lirait le manifeste de `ab.ipsw` alors que l’empreinte et la restauration porteraient sur le fichier choisi. `FileFingerprint` refuse donc ces caractères, ainsi que la barre oblique inverse, dans le nom du fichier ; les noms de dossiers sont lus littéralement par `unzip` et restent acceptés. Les fichiers téléchargés par l’app ont toujours un nom assaini.

La cible est identifiée avant le lancement et doit être désignée à `idevicerestore` avec son ECID. L’app présente le mode choisi, exige une confirmation liée à ce mode, puis suit le processus externe et son journal. L’outil gère les étapes de communication avec l’appareil et le service de signature. Les transitions USB peuvent faire disparaître temporairement l’appareil de la liste du mode normal.

## Distribution

`scripts/build-app.sh` compile l’exécutable pour l’architecture locale, ajoute un `Info.plist`, copie les bundles de ressources SwiftPM dans Contents/Resources et signe le bundle en ad hoc. Les icônes de fonction sont dessinées par GlassIcon. ConnectedDeviceArtwork résout le modèle et la finition avec DeviceArtworkCatalog, puis charge le visuel système macOS via NSWorkspace ; le résultat est mis en cache par type d’appareil. Une finition absente n’est pas déduite de la façade. Le dossier de sortie est `dist/iTelier.app`. L’icône originale se trouve dans `assets/AppIcon.icns`. Les illustrations et leurs prompts sont documentés dans [visual-assets.md](visual-assets.md).

Le workflow GitHub Actions vérifie les tests sans matériel puis archive ce bundle de développement. La distribution notarée, les exécutables universels, les mises à jour automatiques sont des travaux distincts.

## Validation matérielle encore nécessaire

Les tests unitaires doivent couvrir les parseurs, la compatibilité IPSW et la construction des arguments. Ils ne couvrent pas le câble, la confiance accordée au Mac, les services présents sur une version d’iOS, la signature Apple ni la réussite d’une restauration physique.

Avant une release, enregistrer pour chaque essai le modèle, la version d’iOS/iPadOS, le macOS hôte, les versions d’outils et le résultat, sans publier d’identifiants complets. Tester notamment la perte de confiance, deux appareils branchés, une déconnexion, un IPSW incompatible, une erreur de signature et un passage normal → récupération.

## Distribution du module USB

`prepare-runtime.py` récupère les bouteilles Homebrew ciblées Sonoma pour l’architecture courante, vérifiées par Homebrew, ainsi que les archives sources correspondant aux formules embarquées (SHA-256 vérifié). `bundle-runtime.py` copie les cinq outils de lecture/récupération/restauration dans `Contents/Helpers`, résout la fermeture transitive des dylibs dans `Contents/Frameworks`, remplace les chemins Homebrew par des chemins `@loader_path`, puis signe chaque exécutable. Licences, formules de construction, versions et archives sources sont conservées dans `Contents/Resources/ThirdParty`. Le build refuse de produire une app sans ces composants. Les outils intégrés ont priorité sur les installations externes. La distribution demande macOS 14 ou plus récent ; la bibliothèque Swift seule conserve sa cible macOS 13. `build-restore-engine.py` compile les sources amont non modifiées du commit `60192e97f87d1bbab5c493684e0a245b0966363f`, dont l’archive est épinglée par SHA-256. La configuration Darwin, la commande de compilation, l’archive et les licences sont fournies. Aucun outil de compilation n’est requis chez l’utilisateur du bundle.

## Bêtas et conservation des données (0.1.2)

AppleDB est lu depuis son dépôt officiel `littlebyteorg/appledb`, branche `gh-pages`, route `ios/iOS/main.json` (qui inclut iPadOS). La réponse est bornée à 48 Mio et les builds décodés sont gardés en mémoire cinq minutes. Seules les sources IPSW du modèle exact avec taille connue et lien Apple HTTPS actif sont retenues. Le champ `signed` est interprété selon la documentation AppleDB (liste de modèles, booléen ou absence = non signé), indépendamment du champ `active` des liens. Les doublons de build donnent priorité à IPSW.me. Une panne d’une source produit un avertissement et conserve l’autre catalogue. La version du manifeste reste numérique (`27.2`) ; le libellé de présentation conserve `bêta 2`.

`RestoreMode` traverse le modèle, la confirmation et le moteur. Le mode conservation exige `RestoreBehavior=Update`, une variante exacte `Customer Upgrade Install (IPSW)` ou `Developer Upgrade Install (IPSW)` et les composants OS/iBSS/iBEC/RestoreRamDisk. Les versions et builds sont comparés pour refuser les rétrogradations. Le mode normal et une version connue sont exigés avant lancement ; les informations sont relues après confirmation. Le moteur doit annoncer `--variant`, argument qui impose une correspondance exacte et supprime son repli usuel sur une identité d’effacement. Les modes ont des consentements distincts et le changement de mode invalide les confirmations. Aucun échec ne déclenche de deuxième tentative avec `--erase`.

Le bundle déclare `fr` comme langue de développement et localisation principale, avec `fr.lproj/InfoPlist.strings`, pour localiser les menus AppKit et les sélecteurs de fichiers. Le changement de dossier dans Configuration utilise un panneau asynchrone ; les actions du catalogue utilisent directement la destination mémorisée.

## Isolation de la restauration et incidents (0.1.3)

Après validation du manifeste, de la cible et de la confirmation, `DeviceService` écrit une requête atomique dans un répertoire UUID privé, puis détache `iTelierRestoreHost`. Ce helper ne dépend pas des pipes de l’interface. Il acquiert un verrou `flock`, marque la requête comme consommée avec `O_EXCL`, valide une liste stricte d’arguments et recalcule le SHA-256 avant d’exécuter le moteur inclus. Il possède les pipes et tient un journal JSON atomique borné, consulté par l’interface. Le moteur est résolu à côté de l’exécutable réel du helper (`Bundle.main.executableURL`, liens symboliques résolus), jamais depuis `argv[0]`, que le lanceur choisit librement ; aucune variable d’environnement ni option ne le modifie. Le point d’injection interne utilisé par les tests n’est pas exposé dans le helper distribué. Ce n’est pas une frontière de sécurité : un programme de la même session peut toujours exécuter son propre code ; une vérification de signature du moteur deviendra possible avec une signature Developer ID.

Le processus de l’interface observe le journal sans pouvoir annuler implicitement le moteur. Au redémarrage, il retrouve les opérations actives via leurs verrous et suit chaque journal. Une interruption non résolue reste inscrite à travers les redémarrages ; une nouvelle restauration de cet appareil exige une lecture explicite de son état. Aucun événement de récupération ne lance de restauration. Les modes de conservation et d’effacement restent soumis à leurs validations initiales et au ciblage ECID du moteur.

Depuis le build 40, chaque session possède un verrou exclusif et chaque ECID normalisé possède son verrou exclusif dans `Restores/Devices`. Deux sessions visant le même ECID ne peuvent jamais écrire ensemble, même avec deux interfaces ou deux notations de l’identifiant. Les verrous globaux `Restores` et `USBOperation` sont partagés entre restaurations : ils conservent l’exclusion avec les sauvegardes, la migration et les anciens workers exclusifs. Les descripteurs ne sont pas hérités par le moteur. Chaque processus garde son répertoire UUID, ses arguments canoniques, sa consommation `O_EXCL`, son recalcul SHA-256 et sa confirmation terminale ; l’échec d’une cible ne peut ni terminer ni annuler une autre session.

`RestoreTarget` conserve l’identité et les choix approuvés dans les seuls fichiers privés. Le helper compare l’ECID et le mode aux arguments avant de démarrer. `AppModel+Restores` gère les tâches et leurs observations séparément, permet la préparation locale d’un autre appareil et bloque la cible active ou restant à vérifier. Il reprend tous les suivis, y compris les échecs non résolus au-delà des vingt dernières sessions, sans rejouer de requête. Le Dock liste les phases par appareil ; plusieurs pourcentages de phases ne sont pas agrégés en une progression globale inventée.

La détection exclut les appareils en cours d’écriture des lectures USB et d’écran verrouillé. L’inventaire IOKit du Mac fournit les ECID de récupération ; `irecovery -i ECID -q` interroge chaque cible séparément, y compris à côté d’un appareil en mode normal. Le repli sans ECID reste limité à une recherche sans restauration active. Vision Pro conserve le parcours Apple Configurator. Les opérations de sauvegarde restent exclusives pendant une restauration.

`SafetyJournal` enregistre l’opération et les champs autorisés dans des fichiers 0600, dans un dossier 0700. Une fermeture normale marque la session ; une session non fermée produit un rapport au prochain lancement. Aucun gestionnaire de signal n’exécute du code Foundation au moment d’un crash. Les fichiers lus sont bornés. Un stockage inaccessible bloque les nouvelles restaurations. Le rapport partageable utilise un schéma explicite sans journaux ni identifiants ; le partage requiert une action de l’utilisateur via le système macOS.

Le journal de l’hôte de restauration est local et peut contenir des identifiants issus du moteur. Ses 150 dernières lignes sont bornées, mais les répertoires de travail et fichiers intermédiaires des restaurations ne sont pas purgés automatiquement. Le téléchargement interrompu ne reprend pas automatiquement. Une extinction du Mac ou un crash du moteur lui-même ne sont pas rendus inoffensifs par l’isolation du processus.

## Lecture ciblée des composants (0.1.4)

`DeviceService.diagnose` sérialise les requêtes USB. Après relecture de l’identité, il interroge les domaines batterie/stockage, GasGauge, AppleSmartBattery, l’entrée product, MobileGestalt puis l’inventaire IOService (limité à 4 Mio). Les noms de pilotes caméra sont issus de cet inventaire et filtrés par `^AppleH[0-9]{1,3}CamIn$`, dédupliqués et limités à quatre. Si l’inventaire ne donne aucun nom, seuls AppleH16CamIn et AppleH13CamIn sont essayés. Aucun nom arbitraire n’est exécuté dans un shell.

`DiagnosticReading` conserve le statut réel de chaque réponse. `MobileGestaltDeprecated` et les statuts explicites de non-prise en charge ne sont pas assimilés à une lecture réussie. Les erreurs, timeouts et réponses mal formées restent visibles dans le rapport partiel. Les résumés d’erreur n’incluent pas la sortie brute des outils, qui peut contenir un UDID. Les séries sont recherchées par source et chemin exact : `IORegistry.Serial` dans AppleSmartBattery ne peut pas être remplacé par un numéro de chargeur dans AdapterDetails. Les octets binaires non textuels et les valeurs vides/factices ne sont pas convertis en séries hexadécimales. Des séries contradictoires sont signalées sans choix automatique.

Les clés caméra observées sont FrontCameraModuleSerialNumString, BackCameraModuleSerialNumString, BackSuperWideCameraModuleSerialNumString, BackTeleCameraModuleSerialNumString, FrontIRCameraModuleSerialNumString, FrontIRStructuredLightProjectorSerialNumString et JasperSNUM. L’entrée product fournit raw-panel-serial-number, coverglass-serial-number et ambient-light-sensor-serial-num. Les identifiants composites contenant des séparateurs `+` sont conservés en entier et explicitement qualifiés de données brutes. Leur lecture ne constitue aucune comparaison avec des valeurs d’usine.

Sources de protocole : [manuel idevicediagnostics](https://github.com/libimobiledevice/libimobiledevice/blob/master/docs/idevicediagnostics.1), [implémentation diagnostics_relay](https://github.com/libimobiledevice/libimobiledevice/blob/master/src/diagnostics_relay.c), [gestion de MobileGestaltDeprecated dans pymobiledevice3](https://github.com/doronz88/pymobiledevice3/blob/master/pymobiledevice3/services/diagnostics.py). Les clés ajoutées pour l’iPhone18,1 ont aussi été vérifiées par des lectures locales sur l’appareil connecté ; aucune de ses séries n’est incluse dans le dépôt.

## Comparaison avec un relevé enregistré (0.1.6)

`CheckReference` conserve un ensemble borné de valeurs lues, l’ECID normalisé, le modèle, la date et une origine locale/importée. Il ne représente jamais une certification usine. L’application conserve le rapport brut séparément et applique la référence uniquement pour la présentation et l’export. `referenceMatch` (same/different/unreadable/initial) reste distinct du statut de lecture. Une absence ou un échec ne devient pas un écart ; les mesures évolutives et contrôles manuels sont exclus.

`CheckReferenceStore` utilise un nom SHA-256 dérivé de la cible, avec séparation des exemples, répertoire 0700 et fichiers 0600. Les écritures sont atomiques et une référence remplacée est conservée en `.previous.json`. L’import est limité à 1 Mio, 200 lignes, aux schémas iTelier 2/3 et aux valeurs réellement lues (pas aux anciennes valeurs attendues). Le masquage ou une cible différente provoque un refus. Les exports Check 3 ajoutent les IDs stables, la provenance datée et le résultat de comparaison ; les valeurs sensibles attendues respectent le même masquage que les valeurs actuelles.


## Sauvegardes locales

`LocalBackup` lit les métadonnées Apple de manière bornée, rejette les liens symboliques et distingue les copies complètes des dossiers interrompus. `BackupLibrary` parcourt seulement deux niveaux connus, sans analyse récursive du contenu personnel. La compatibilité source/cible est vérifiée avant la confirmation puis juste avant le lancement.

`BackupHost` réutilise l’exécutable signé `iTelierRestoreHost` avec l’entrée `--backup`. Le worker possède le processus `idevicebackup2`, ses pipes et un journal de phases françaises sans contenu personnel. Le mot de passe n’est jamais persisté et ne transite ni par l’environnement ni par les arguments : `ps eww` montre l’environnement initial d’un processus à tout programme de la même session, même après `unsetenv`. L’interface l’écrit dans un pipe branché sur l’entrée standard du worker, qui le lit une fois (1 Kio au plus, jamais depuis un terminal). Le worker le transmet à `idevicebackup2 -i` sur l’entrée standard uniquement pour `encryption on` (mot de passe et confirmation) et pour la restauration d’une copie chiffrée ; la création d’une sauvegarde n’en a pas besoin. Une ligne vide supplémentaire fait échouer une demande inattendue au lieu de bloquer le moteur en fin d’entrée. Comme `-i` ne garde que l’ASCII imprimable et 255 octets, les autres mots de passe sont refusés plutôt que modifiés en silence. Le verrou commun `USBOperation` exclut une écriture IPSW simultanée. Les requêtes sont consommées une seule fois.

Une création utilise un nouveau dossier privé avec marqueur d’incomplétude jusqu’à la confirmation du moteur et de l’état Apple. Une restauration relit la cible et l’empreinte des métadonnées, exige le mot de passe d’une copie chiffrée et n’utilise pas `--remove`. Le manifeste des fichiers est exigé, mais le contenu complet de chaque fichier n’est pas prévalidé. La perte du worker est signalée, les copies interrompues restent non restaurables et une restauration interrompue impose une vérification de l’appareil.
