# Tests du cœur

## Build 39 — renommage complet et migration

Les dossiers, modules SwiftPM, helpers, ressources, identifiant du bundle (`com.itelier.app`), variables d’environnement et documentation portent désormais le nom iTelier. Les ressources des fonds d’écran sont sous `Sources/iTelier/Resources/Wallpapers`. Le script d’assemblage choisit uniquement le bundle de ressources actuel, même si un ancien cache SwiftPM existe.

La migration conserve les préférences, sauvegardes, références et téléchargements. Elle refuse les conflits de dossiers, les liens symboliques et les opérations encore actives ; elle conserve le choix actuel d’une préférence déjà renseignée. Les chemins des préférences et requêtes archivées sont adaptés, les sauvegardes incomplètes restent identifiées et les rapports des versions précédentes restent importables. La migration démarre après l’ouverture de la fenêtre, sans bloquer son thread principal. Elle ne parcourt ni tout Téléchargements ni le contenu des sauvegardes.

Validation locale : **122 tests du cœur réussis**, dont sept tests de migration et deux tests d’import des noms historiques. Le helper de restauration passe ses tests avec un moteur inerte et les six tests d’intégrité des dépendances réussissent. `scripts/check-branding.py` vérifie les noms et contenus des fichiers livrés ; GitHub Actions l’exécute sur les sources et le bundle. Les anciennes réservations privées, exclues de Git et des distributions, restent intactes.

Bundle release arm64 build 39 compilé et signé, sans occurrence de l’ancienne marque dans ses 93 fichiers. ZIP vérifié par CRC et comparaison de contenu ; DMG monté en lecture seule avec 93 fichiers/liens et permissions identiques au bundle, signature stricte valide, raccourci Applications et icône de volume présents. Contrôle natif dans une copie identique : fenêtre iTelier en français, chemin de sauvegarde sous `Application Support/iTelier`, chiffrement conservé sur OFF. Le dossier historique de données locales a été déplacé ; aucune commande de sauvegarde ou restauration réelle lancée.

## DMG d’installation — build 38

`scripts/build-dmg.sh` crée une image HFS+ compressée en lecture seule depuis le bundle existant, avec un raccourci vers Applications et l’icône de volume de l’app. Le script refuse un bundle dont la signature stricte échoue, travaille dans un dossier temporaire et ne remplace l’image finale qu’après vérification de son intégrité. GitHub Actions produit désormais le ZIP et le DMG dans le même artifact, sans publier de Release automatiquement.

Validation locale arm64 : image 0.2.0 build 38 créée, somme de contrôle vérifiée, puis montée en lecture seule sans ouvrir l’app. Signature `codesign --verify --deep --strict` valide ; **93 fichiers et liens du bundle identiques**, y compris leurs permissions ; raccourci `/Applications`, version et icône de volume vérifiés. Image démontée après contrôle. Aucun changement de code applicatif ni commande sur un appareil.

## Première exécution GitHub Actions — compatibilité XCTest

Le champ de fixture `hash`, de type String, entrait en conflit avec la propriété `NSObject.hash` héritée par le véritable XCTestCase. La compilation `swift test` sur GitHub échouait avant d’exécuter les tests. Le champ s’appelle désormais `firmwareHash`. Le substitut utilisé par `test-core.sh` hérite lui aussi de NSObject pour détecter ce type de conflit sur les installations sans XCTest.

Validation locale après correction : **115 tests réussis**, sans appareil, avec le substitut héritant de NSObject. Sur GitHub, le [run 37013333359](https://github.com/byalmaz/iTelier/actions/runs/37013333359) a ensuite réussi `swift test` et le test du helper inerte ; il s’est arrêté à la préparation des dépendances.

## GitHub Actions — dépendances Sonoma épinglées

La préparation interrogeait les formules Homebrew courantes, dont certains paquets Sonoma ne sont plus proposés. `brew fetch` ne fournissait pas les archives et le script essayait d’ouvrir un chemin vide. Le manifeste `scripts/runtime-bottles.json` épingle désormais les références, tailles et SHA-256 des paquets officiels Sonoma pour Apple Silicon et Intel. Le téléchargement passe directement par le registre public Homebrew, sans installation de Homebrew. La taille et l’empreinte sont vérifiées avant extraction ; les protections contre les chemins et liens sortant de l’archive restent actives. Les sources amont et leurs licences restent récupérées depuis les formules incluses dans chaque paquet.

Validation locale : **24 paquets officiels téléchargés et vérifiés**, douze par architecture ; **six tests d’intégrité réussis**, dont cache corrompu, taille incorrecte, interruption réseau et lien symbolique. Préparation complète des sources et compilation du moteur arm64 réussies dans un dossier temporaire isolé, sans Homebrew ni commande sur un appareil. Les versions Intel OpenSSL 3.6.3 et lz4 1.10.0 (rebuild 1) sont distinctes des versions arm64 ; le téléchargement Intel est vérifié, sa compilation complète reste à valider sur un Mac Intel. Le workflow exécute également les six tests sans accès réseau.

## Build 38 — boutons d’information de la vue d’ensemble

Les icônes **i** des cartes Restaurer et Vérifier sont désormais des boutons avec une zone de clic de 28 points, un libellé d’accessibilité distinct et une aide intégrée à la fenêtre. L’aide reste disponible sans appareil connecté et se ferme avec **X**, **Compris** ou la commande d’annulation. Les textes sont traduits en anglais. Les descriptions des cartes gardent leur hauteur complète pour éviter une troncature.

Compilation release arm64 réussie et signature stricte vérifiée. Contrôle natif en français, apparence claire et sans appareil : ouverture des deux aides, fermeture par X et Compris, retour à la vue d’ensemble et descriptions entièrement lisibles. Couverture des traductions et absence de doublons vérifiées. Archive contrôlée : CRC, version 38, permissions exécutables et identité du binaire. Aucun test de sauvegarde ou de restauration réelle ; la logique du cœur est inchangée.

## Build 37 — choix du chiffrement mémorisé

Le bouton **Chiffrer la sauvegarde** utilise une préférence persistante, avec **OFF** comme choix initial. La navigation et la relance ne réactivent plus le choix automatiquement. Seule cette préférence est enregistrée ; les mots de passe restent temporaires. Le chiffrement déjà actif sur l’appareil n’est pas désactivé par ce bouton.

Compilation release réussie et signature stricte vérifiée. Contrôle natif sans appareil connecté : choix initial OFF, passage ON puis navigation conservant ON, retour OFF, fermeture complète et relance conservant OFF. Le build 37 est laissé ouvert sur Sauvegardes avec OFF. Archive reconstruite et identité du binaire, métadonnées et CRC vérifiées. Aucune sauvegarde ni commande de modification du chiffrement sur un appareil.

## Build 36 — iTelier et résultat réel de la restauration

Le nom visible devient **iTelier** dans ce build : produit SwiftPM, bundle, exécutable, menus et textes français/anglais, exports, documentation de lancement et archive CI. À cette étape, les identifiants internes et dossiers historiques étaient encore conservés. Leur migration complète est ajoutée au build 39. Les rapports de schéma 2/3 des versions précédentes restent acceptés avec les mêmes contrôles d’identité et de masquage.

Le journal de l’incident signalé contenait `Unable to fetch Yonkers ticket`, `Unable to successfully restore device`, puis `DONE`, avec un code de sortie 0. Ce résultat était présenté à tort comme une réussite. Le suivi exige désormais le message terminal de l’appareil `Status: Restore Finished`, un code 0 et aucune erreur fatale. `DONE` ou une progression de 100 % ne suffisent plus. Le verdict persiste même lorsque les dernières lignes remplacent le message terminal dans le journal borné ; les anciens états sont réévalués à la lecture. Une fin confirmée s’appelle **Installation du système terminée** et rappelle que le démarrage de l’appareil peut encore continuer. Ce correctif ne résout pas l’échec de signature du composant Yonkers et ne garantit pas la récupération de l’appareil.

Une aide facultative explique les autorisations d’accessoires macOS avant restauration et renvoie vers Réglages Système et [l’aide Apple](https://support.apple.com/fr-fr/102282). L’app ne change aucun réglage de sécurité. La préparation défile en gardant les boutons accessibles ; le conseil générique de débrancher est retiré pendant la restauration et sa fin. Rendu français clair contrôlé dans un aperçu natif isolé, sans modèle d’opération USB. Couverture des nouvelles traductions et absence de doublons vérifiées ; le contrôle visuel anglais/sombre de cette aide n’a pas été terminé, car le Mac s’est verrouillé.

Validation : **115 tests du cœur réussis**, dont cinq régressions sur le résultat moteur et deux sur les trois noms de rapports. Le helper inerte passe les cas de fausse réussite exit 0, de confirmation conservée après troncature, de sortie/SIGKILL du parent, de concurrence, de rejeu et de fichier IPSW modifié. Compilation release arm64 du build 36 réussie ; bundle et archive iTelier vérifiés avec signature stricte. Aucun moteur USB réel exécuté par l’agent pour cette validation. La récupération entreprise ensuite par l’utilisateur dans le Finder reste distincte et son résultat doit être confirmé sur l’appareil.

## Build 33 — écran verrouillé et test Face ID

Le helper demande désormais `getWallpaperPreviewImage` avec `wallpaperName=lockscreen` : l’ancienne API ne lisait que le fond d’accueil et renvoyait ici un ancien fond Apple. L’aperçu personnel reçu contient déjà sa date, son heure et ses indicateurs ; ReWork n’ajoute plus d’horloge par-dessus. Une actualisation manuelle force une nouvelle lecture, les lectures automatiques restent espacées et une lecture échouée retire l’ancienne image. Si le masque de coque n’est pas disponible, l’aperçu reçu reste affiché seul. L’image reste en mémoire dans l’app, sans export ni cache persistant.

Lecture USB réelle validée sur une seule cible : PNG personnel de l’écran verrouillé reçu, puis rendu vérifié dans la carte de l’app. **Limite observée : la date et l’heure de l’aperçu SpringBoard sont figées, sans correspondre à l’heure actuelle.** `getWallpaperInfo` a été essayé en lecture seule pour obtenir le fond brut ; il renvoie sur cet appareil l’ancien fond Apple, donc n’est pas utilisé comme repli. Le service `com.apple.mobile.screenshotr` est indisponible sur cette cible (code -27) ; aucune capture ni activation du mode développeur n’a été effectuée. Aucune promesse d’écran verrouillé en direct. Les fichiers privés temporaires de vérification sont retirés après contrôle.

Vérification propose **Test Face ID** : lecture du rapport disponible ou nouveau Check, instructions de déverrouillage sur l’appareil, résultat confirmé explicitement par l’utilisateur et informations IR/projecteur lues dans le rapport. Les identifiants ne produisent jamais un verdict de fonctionnement « Normal » ; le capteur de proximité reste non évalué. La session est locale et invalidée à la déconnexion ou au changement d’identité/mode. Aucune commande ne déclenche Face ID à distance, aucune donnée biométrique recueillie et aucun résultat ajouté automatiquement au rapport.

Validation : **108 tests du cœur réussis**, dont quatre nouveaux tests de session Face ID et les deux tests Batterie ajoutés par Claude ; compilation release, signature stricte et archive du build 33 vérifiées. Contrôle natif du déroulement et du résultat sur appareil fictif, en français/clair et en anglais/sombre. Langue française et apparence claire initiales rétablies, aperçu quitté et app laissée sur l’appareil connecté. Aucun déverrouillage réel confirmé par l’agent, aucune sauvegarde ni restauration réelle. Le build inclut les évolutions Batterie de Claude après libération de ses réservations.

Protocole de lecture : [implémentation SpringBoard de pymobiledevice3](https://raw.githubusercontent.com/doronz88/pymobiledevice3/master/pymobiledevice3/services/springboard.py) et [aperçu verrouillé dans idevice](https://docs.rs/idevice/latest/src/idevice/services/springboardservices.rs.html).

## Build 32 — audit des bugs

- Catalogue : changer de famille annule la sélection incompatible et son chargement ; le firmware affiché et les actions correspondent à la famille choisie. Les filtres Toutes/Publiques/Bêtas utilisent des valeurs stables lors d’un changement de langue. Les titres de bêtas en mémoire sont traduits à l’affichage ; les cartes IPSW indiquent le bon système, dont visionOS.
- Téléchargements : l’empreinte SHA-1 est vérifiée lorsque SHA-256 est absent ; sans empreinte publiée, tous les membres ZIP sont contrôlés avant publication du fichier. Une archive corrompue reste refusée même si son manifeste est lisible. L’annulation dispose d’un état indépendant du texte traduit, y compris dans le Dock.
- Sauvegardes : une modification du dossier ou des imports pendant une lecture relance le scan sur les bonnes sources. Une session illisible ne masque pas les autres sauvegardes ; une bibliothèque inaccessible continue de produire une erreur. Les indications de chiffrement et de cible suivent la langue choisie.

Validation automatique : 102 tests du cœur réussis, dont douze nouveaux cas avec transport URLProtocol, archives ZIP réelles, permissions de dossiers et titres traduits ; helper de restauration validé avec un moteur inerte. Compilation release réussie. Aucun moteur USB réel n’est lancé par ces tests. Le bug de changement iPhone → Vision Pro a été reproduit dans le build 31 avant correction.

Validation dans l’app : iPhone sélectionné puis changement vers iPad/Vision Pro vide les versions et désactive Télécharger ; sélectionner Vision Pro charge visionOS et propose Apple Configurator. Les filtres Public/Betas fonctionnent en anglais. Des versions chargées en anglais repassent en français sans actualisation du catalogue. Langue française et apparence claire initiales rétablies ; aucune sauvegarde ni restauration réelle lancée.

## Build 24 — réutilisation des IPSW après relance

Avant tout téléchargement ou préparation depuis le catalogue, FirmwareLibrary recherche les fichiers IPSW complets dans le dossier configuré. Elle compare taille, version, build et modèle, puis l’empreinte SHA-256 ou SHA-1 publiée. Sans empreinte, elle contrôle tous les membres ZIP. L’identité du fichier est recontrôlée après lecture. Les noms modifiés et doublons sont acceptés si le contenu correspond ; les fichiers partiels, liens symboliques, fichiers endommagés et incompatibles sont ignorés sans suppression. La recherche est annulable et ne dépend d’aucune mémoire de session.

Les 70 tests du cœur réussissent, dont quatre nouveaux scénarios couvrant redécouverte, noms différents, métadonnées et empreintes incorrectes, CRC d’un membre endommagé malgré un manifeste valide, liens, fichiers partiels et annulation. Compilation release et signature stricte réussies.

Essai natif réel après fermeture et relance : sélection d’iOS 27.2 bêta 2, build 24B5089g pour iPhone17,1, puis action Restaurer dans le catalogue. L’app valide et sélectionne le fichier original de 12,37 Go, ouvre la préparation, et consigne « IPSW existant réutilisé » / « Aucun nouveau téléchargement ». Aucun troisième IPSW créé et aucune restauration lancée. L’écran Restaurer a été laissé avec le fichier original sélectionné ; les deux copies téléchargées précédemment restent intactes. Ce lancement charge également le correctif du build 23.

## Build 23 — choix du mode pendant le téléchargement

La case Conserver les données, dans Restaurer et Configuration, utilise désormais une disponibilité propre au choix du mode. Elle reste modifiable pendant un téléchargement, sa pause et l’analyse de l’IPSW ; elle est verrouillée pendant une restauration ou une opération de sauvegarde. Le setter des préférences respecte cette même règle. Changer de mode réinitialise toujours les confirmations, et la compatibilité est revalidée avant le lancement.

L’état natif du build 22 a confirmé la régression : un téléchargement à 22 % rendait la case indisponible. La correction est vérifiée par compilation et lecture des gardes de lancement. Aucun essai de restauration ni interruption du téléchargement réel pour relancer l’app ; le build corrigé sera chargé au prochain lancement.

## Build 22 — carte IPSW unique et pause du téléchargement

Pendant le transfert, une seule carte présente version, progression, pourcentage et actions Pause/Reprendre/Annuler. Elle remplace la carte de sélection vide, puis passe à la vérification ; les étapes reflètent la phase en cours. La commande de restauration n’est affichée à nouveau qu’après le transfert et sa validation. La pause conserve la tâche URLSession et son fichier partiel dans la session ouverte ; elle ne constitue pas une reprise après fermeture de l’app.

Les 66 tests du cœur réussissent. Trois nouveaux tests couvrent la suspension/reprise de la même tâche sans suspension imbriquée, une pause avant démarrage suivie d’une reprise avec validation du contenu et du SHA-256, et l’annulation en pause avec suppression des fichiers temporaires. Le réseau est remplacé par URLProtocol, avec le véritable téléchargement et les délégués URLSession. Une pause longue sur le CDN Apple n’a pas été éprouvée.

Compilation release réussie. Le composant natif partagé a été inspecté dans une app d’aperçu indépendante, sans appareil ni transfert : états téléchargement et vérification, puis clic Pause/Reprendre avec conservation des valeurs affichées. Le téléchargement réel déjà lancé dans le build précédent a été laissé intact jusqu’à son terme. L’app principale n’a pas été redémarrée ensuite, car l’IPSW est sélectionné et l’utilisateur a déjà rempli ses prérequis de restauration ; le build 22 sera chargé à la prochaine ouverture.

## Build 21 — préférence de conservation des données

Configuration propose un mode de restauration par défaut mémorisé dans les préférences. Sa modification applique le mode à la session courante et réinitialise les confirmations existantes. Les changements effectués dans Restaurer restent propres à la session. Au démarrage, la préférence est chargée avant le suivi éventuel d’une opération interrompue, qui garde son propre mode.

Compilation release réussie. Essais natifs : décocher la préférence décoche l’option dans Restaurer ; après fermeture et relance, la case reste décochée. La préférence initiale de conservation a été rétablie après cet essai. Aucun firmware sélectionné, aucune sauvegarde ni restauration lancée.

## Build 20 — actualisation dans Configuration

Le bouton Actualiser revérifie les outils et lance la détection USB, ou attend la détection automatique déjà en cours. Il affiche une progression puis un résultat horodaté avec le nombre d’outils et l’état de connexion. En aperçu, il explique que la détection nécessite de quitter ce mode ; pendant une opération, il est désactivé.

Compilation release réussie. Dans l’app relancée, clic natif sur Actualiser : affichage de « 6/6 outils disponibles. 1 appareil détecté. » avec l’heure. La confirmation sous le bouton est lisible dans la configuration. Vérification limitée à la détection en lecture seule, sans sauvegarde ni restauration.

## Build 19 — stabilité du Check et tuile Configuration

L’actualisation USB ne désactive plus les boutons de lancement du Check. Un clic pendant une détection réserve le Check, attend la fin de la lecture en cours puis revalide l’identité de l’appareil avant le diagnostic. La tuile Configuration reprend la zone cliquable arrondie du menu, avec une marge extérieure de 3 points et une zone de survol couvrant son intérieur.

Compilation release réussie. Après relance native, un clic dans l’espace vide à droite de Configuration ouvre les réglages. Retour au tableau de bord et actualisation manuelle effectués : le bouton Check est actif et conserve son rendu jaune. Le chemin de mise en attente est vérifié dans le code, sans simulation d’un changement physique d’appareil pendant l’attente. Aucun moteur de sauvegarde ou de restauration n’a été exécuté.

## Build 18 — fonds des versions précédentes

Sélection étendue aux fonds iOS/iPadOS 16, 17 et 18, en plus de 26 et 27. Les 63 tests du cœur réussissent, dont les cas 18.7, 17.7.2, 16.7.12 et les variantes iPad. Décodage des quatre assets HEIC vérifié. Compilation release et signature stricte réussies. Le rendu natif de l’iPhone 15 Pro de démonstration sous iOS 18.7 affiche le fond Apple iOS 18 en couleur avec la découpe caméra conservée.

## Build 16 — zone cliquable du menu

Les tuiles de navigation ont une zone arrondie continue couvrant leur intérieur, avec une marge inactive de 3 points sous le contour. Compilation release réussie. Vérification native : clic dans l’espace vide à droite de Restaurer puis de Vue d’ensemble sélectionne la rubrique ; clic dans la marge droite conserve la sélection. Aucun test d’opération USB nécessaire pour cette retouche.

## Version 0.1.9, build 15 — sauvegardes et fonds d’écran

- 63 méthodes du cœur réussies, sans échec, avec le runner autonome. Les nouveaux scénarios utilisent des métadonnées et moteurs fictifs : sauvegarde terminée, exit 0 sans confirmation de succès, cible USB différente, restauration d’une copie complète, refus du chiffrement sans mot de passe, annulation laissant une copie non restaurable, rejet de métadonnées liées par symlink, versions/familles incompatibles, mots de passe absents des arguments et rapports, interruption de restauration nécessitant une vérification.
- Le test de processus indépendant IPSW réussit après l’ajout du verrou commun aux opérations USB : sortie du parent, SIGKILL du parent, concurrence, rejeu et firmware modifié. Ce test utilise un moteur inerte et ne restaure aucun appareil.
- App compilée en release, six outils USB inclus. Page Sauvegardes inspectée visuellement sur l’app native : navigation, cartes en verre, dossier, état vide, champs et actions. Lecture réelle en USB de `WillEncrypt` réussie sur l’iPhone connecté, sans activation du chiffrement.
- Fonds embarqués iOS/iPadOS 26 et 27 : sélection automatique couverte par les tests ; masque testé avec découpe caméra et reflet extérieur ; rendu iOS 27 observé sur l’icône système de l’iPhone 16 Pro. Aucun téléchargement nécessaire à l’affichage.
- **Aucune sauvegarde ni restauration réelle n’a été exécutée sur l’iPhone.** La réussite des fixtures ne garantit pas la compatibilité de bout en bout avec toutes les versions d’iOS.


## Validation locale du 1er octobre 2026

| Vérification | Résultat et portée |
| --- | --- |
| Compilation de l’app | Bundle release `dist/iTelier.app` construit pour `arm64`. Le bundle avec outils USB embarqués demande macOS 14 ; la bibliothèque Swift seule conserve sa cible macOS 13. Cette cible est une cible de compilation, sans essai sur tous les systèmes ou architectures pris en charge. |
| Signature | Signature ad hoc et vérification stricte `codesign --verify --strict` réussies. Aucun certificat Developer ID ni notarisation. |
| Tests du cœur | Les 39 méthodes existantes ont réussi via `bash scripts/test-core.sh`, sans échec. Ce Mac dispose des Command Line Tools ; XCTest n’y est pas disponible et `swift test` n’a pas été exécuté avec succès localement. |
| Interface sombre | Tableau de bord observé dans une instance neuve du bundle : cartes, halo cyan et trois PNG transparents chargés. Après déverrouillage du Mac, les écrans natifs Check et Restaurer ont été vérifiés visuellement : table, badges et commandes d’export du Check ; prérequis et bouton Continuer désactivé en démonstration dans Restaurer. |
| Export de démonstration | Le rapport JSON démo exporté avec les identifiants masqués a été vérifié. Cela valide cet export, sans valider des mesures sur appareil physique. |
| Appareils physiques | Version 0.1.2 : détection et lecture réelles réussies sur un iPhone18,1 sous iOS 27.2. Le tableau de bord natif affiche l’appareil connecté. Les outils et leurs dylibs sont chargés depuis le bundle, sans installation Homebrew des outils. Aucune restauration physique exécutée. |
| Sources du catalogue | Documentation Swagger et réponses JSON publiques IPSW.me lues pour un iPhone et un iPad. Une requête HEAD sur une URL Apple a répondu HTTP 200 avec taille et SHA-256 concordant avec les métadonnées. Aucun IPSW de plusieurs gigaoctets n’a été téléchargé intégralement pour cet essai. |

La CI est configurée pour utiliser XCTest sur un runner macOS ; sa configuration ne constitue pas la preuve d’un run GitHub réussi. Les essais matériels et une exécution XCTest dans cet environnement restent à réaliser.

## Exécuter la suite

Avec Xcode complet et une toolchain Swift 6 ou plus récente, utiliser XCTest :

```sh
swift test
```

Certains paquets Apple Command Line Tools incluent Swift et le SDK macOS, mais omettent le module XCTest. Dans ce cas, lancer depuis le dossier du projet :

```sh
bash scripts/test-core.sh
```

Ce script compile les sources réelles de `iTelierCore` et les méthodes du fichier `Tests/iTelierCoreTests/CoreValidationTests.swift`. Il conserve les corps des tests et leurs assertions, remplace seulement les imports XCTest et ajoute des assertions compatibles ainsi qu’un point d’entrée temporaire. Il découvre chaque méthode `test…()` et refuse les signatures qu’il ne sait pas exécuter. Toute assertion échouée ou exception imprévue produit un code de sortie non nul. Swift 6 ou plus récent et Python 3 sont nécessaires ; aucun paquet ni outil iOS n’est installé.

Le dossier temporaire contient le binaire et le cache de compilation, puis est supprimé à la fin. Le runner n’a pas les fonctions avancées de XCTest, telles que les fixtures `setUp`, les expectations, les tests de performance ou la découverte de plusieurs classes. Une évolution de la suite qui utilise ces fonctions doit adapter le runner ; la CI conserve XCTest comme exécution de référence.

Les tests couvrent l’approbation liée à l’appareil et au SHA-256, les ECID décimaux et hexadécimaux, la reconnexion et les appareils ambigus, les modèles et cartes incompatibles, les identités Erase du manifeste, les chemins relatifs de composants, le SHA-256 streaming, la lecture d’une archive IPSW synthétique, la progression, les sorties de processus bornées, le timeout, l’annulation des lectures et les arguments traités littéralement. Ils distinguent une charge à 0 % d’une capacité maximale indisponible et vérifient le seuil indicatif d’attention sous 80 % avec un rapport partiel.

Les scénarios du catalogue et du téléchargement utilisent des métadonnées contrôlées et un `URLProtocol` de test qui intercepte les requêtes d’un véritable `URLSessionDownloadTask`. Un transfert de trois octets exerce la progression et le delegate ; les autres cas vérifient les erreurs HTTP, une taille ou un SHA-256 incorrect, une redirection hors Apple, l’annulation avec nettoyage du staging et la conservation d’un fichier déjà présent. Ces essais ne téléchargent pas de firmware Apple réel. Le téléchargement de fichiers de plusieurs gigaoctets, les interruptions longues et l’interaction avec les configurations réseau des utilisateurs restent à éprouver.

Ces tests n’appellent aucun outil de communication avec un appareil et ne déclenchent aucune restauration. La fixture IPSW contient un manifeste synthétique, sans firmware réel. La suite lance des outils système (`zip`, `unzip`, `printf`, `sleep`, `sh`) et des scripts de moteurs fictifs dans un dossier temporaire. Les scénarios USB et les restaurations complètes sur de vrais appareils restent à valider séparément avant une release publique.

Le test de résolution des outils vérifie la priorité du répertoire `Contents/Helpers` avec un PATH sans Homebrew, ainsi que le rejet de noms inconnus ou de chemins remontant un répertoire. Le module USB est livré avec six exécutables et onze dylibs dont tous les liens non système ont été relocalisés ; la signature stricte du bundle est vérifiée après assemblage.

## Vérifications de la version 0.1.2

- Menus natifs : « À propos de iTelier », « Masquer iTelier », « Quitter iTelier », Édition, Présentation, Fenêtre et Aide observés en français.
- AppleDB réel : 63 versions compatibles avec iPhone18,1 dont 44 bêtas/RC ; iOS 27.2 bêta 2 (24B5089g), 13 029 948 451 octets, figure dans la liste native. Versions non signées visibles par défaut.
- Panne d’une source, déduplication, association stricte au modèle, exclusion des OTA et liens non Apple, état de signature et version numérique des bêtas couverts par les tests.
- Téléchargement natif : choix d’un dossier temporaire via le panneau français, plus de 140 Mo reçus directement de updates.cdn-apple.com, progression visible, annulation volontaire et dossier de test redevenu vide. Le bouton Télécharger reste actif en aperçu. Aucun firmware de plusieurs Go téléchargé intégralement lors de cette validation.
- Case Conserver les données : cochée par défaut, textes de préparation changent avec le mode. Les tests imposent une identité Update complète et des consentements distincts, refusent les rétrogradations (y compris bêta antérieure), le mode récupération et une version inconnue. Les arguments de conservation contiennent la variante exacte et aucun `-e`.
- Moteur intégré : `idevicerestore --version` indique 1.1.0-git-60192e97 ; `--help` expose `--variant`. Exécution des commandes informatives et signature stricte réussies. Le moteur n’a reçu aucune commande de restauration.

Les deux modes de restauration, la conservation effective des données, les changements de mode USB pendant une restauration et la validation complète d’un IPSW téléchargé restent à éprouver sur un appareil de test sauvegardé avant une release publique.

Le manifeste réel de l’IPSW 27.2 bêta 2 pour iPhone18,1 a été lu par requêtes HTTP Range (57 971 octets transférés). Il contient les variantes `Developer Erase Install (IPSW)` et `Developer Upgrade Install (IPSW)` pour v53ap. Le parseur et les arguments prennent en charge cette variante Developer en plus de Customer ; un test dédié empêche une régression vers une variante d’effacement.

## Vérifications de la version 0.1.3

- Cinq tests supplémentaires vérifient la détection des sorties inattendues, le maintien du blocage après plusieurs redémarrages, son acquittement explicite, la persistance d’un incident, les permissions du journal, le rejet d’un fichier corrompu, le filtrage des champs exportés, la liste stricte d’arguments et l’exclusion mutuelle du moteur.
- `python3 scripts/test-restore-host.py` compile les sources réelles du cœur avec un point d’entrée de test dans un répertoire temporaire. Le moteur est un script inerte qui écrit deux messages et attend deux secondes. Le parent lance le helper avec la même fonction de détachement que l’app puis quitte immédiatement. Le test observe sa réussite après la sortie normale du parent et après un SIGKILL du parent, le refus d’un deuxième worker simultané, le refus de rejouer une requête et le refus d’un IPSW dont le SHA-256 a changé. Aucun outil USB n’est exécuté.
- Ces vérifications valident le suivi et la séparation des processus, pas la réussite d’une restauration iOS. La conservation réelle des données et une interruption matérielle restent hors de cette validation.

Essais natifs effectués sur le build 0.1.3 :

- La configuration affiche `Téléchargements/iTelier`, avec Modifier et Ouvrir. Le dossier a été créé au clic Télécharger et ouvert dans le Finder après annulation ; le Finder affiche zéro élément.
- Le catalogue iPhone18,1 affiche iOS 27.2 bêta 2 et les deux actions Télécharger / Restaurer. Le téléchargement démarre directement, sans sélecteur de destination ; 2 Mo étaient déjà reçus depuis Apple lors de la première observation, puis l’essai a été annulé. Aucun appareil n’était détecté pendant cet essai ; Restaurer est donc correctement désactivé.
- Le rapport s’ouvre depuis Configuration et Activité ; son export natif dans un dossier temporaire produit un JSON valide. La description saisie apparaît dans l’aperçu. Le bouton Envoyer ouvre le partage natif (Mail, Messages, etc.) ; le menu a été refermé sans transmission.
- Un SIGKILL de l’interface au repos, après annulation du téléchargement, produit au lancement suivant la bannière d’interruption et un rapport `unexpectedExit`. Une fermeture normale ultérieure ne produit pas une nouvelle alerte au redémarrage.
- Les écrans de configuration, catalogue et rapport ont été observés. Le parcours de préparation après téléchargement intégral et une restauration physique restent non validés de bout en bout.

## Vérifications de la version 0.1.4

Les 39 tests du cœur passent. Six tests supplémentaires couvrent les clés réelles de composants avec des valeurs synthétiques : provenance exacte, masquage déclaré, identifiant brut conservé entier, exclusion des séries du chargeur, distinction entre service retiré/lecture échouée/champ absent, rejet de données binaires et placeholders, contradictions entre sources, filtrage des noms de pilotes et absence d’identifiants dans les résumés d’erreur.

Des lectures USB en mode normal sur l’iPhone18,1 sous iOS 27.2 ont fourni les réponses réelles d’AppleSmartBattery, product, AppleH16CamIn et MobileGestalt. Un exécutable temporaire utilisant les sources réelles de iTelierCore a vérifié la récupération de douze identifiants : carte logique, batterie, avant, arrière, ultra grand-angle, téléobjectif, infrarouge, projecteur, LiDAR, dalle, vitre, lumière ambiante. Seuls les états et longueurs ont été imprimés. MobileGestaltDeprecated est reconnu comme non pris en charge. Les données privées restent hors du dépôt et les tests versionnés utilisent uniquement des séries synthétiques.

Le bundle 0.1.4 a reconnu l’iPhone au lancement. Lors du premier essai natif du Check, l’appareil a disparu d’USB avant la relecture initiale ; l’erreur de connexion a été affichée, sans produire de rapport vide présenté comme réussi. Cette interruption ne constitue pas une validation du parcours natif complet.

Après le rebranchement signalé par l’utilisateur, le moteur intégré `idevice_id -l`, exécuté hors du sandbox de développement, retourne encore zéro appareil (code 0). L’inventaire USB de macOS ne fournit pas non plus d’iPhone/iPad. L’app 0.1.4 reste ouverte sur Vérification, sans lancer d’opération sur l’appareil. Le parcours natif complet et l’export de ce nouveau rapport restent à vérifier lorsque la connexion est rétablie. La signature du bundle et l’intégrité de l’archive de distribution ont été vérifiées.

## Vérifications de la version 0.1.5

Les 41 tests du cœur passent. Deux nouveaux tests distinguent un iPhone d’un autre accessoire Apple dans l’inventaire USB et couvrent les états absence USB, autorisation en attente, appareil verrouillé, moteur absent, service indisponible et diagnostic inconnu, sans fuite des sorties brutes.

La détection automatique et manuelle reste active pendant un téléchargement ou l’analyse locale d’un IPSW. Elle reste suspendue pendant une restauration ou un Check pour éviter des clients USB concurrents. Un panneau de connexion commun aux pages indique désormais l’état matériel IOKit et les actions utiles ; une absence USB ne permet pas de conclure si la cause est un câble, un port ou une autorisation macOS.

Au diagnostic initial de ce build, le service macOS usbmuxd était actif, mais les inventaires IOUSBHostDevice et IOUSBDevice et les listes USB/réseau de libimobiledevice étaient vides. Le moteur Recovery ne détectait pas non plus d’appareil. Aucune réinitialisation, restauration ou modification des autorisations système n’a été exécutée.

Le bundle 0.1.5 a été relancé et son numéro de version observé dans l’interface. Sur la page Vérification, le panneau « Aucune liaison USB détectée », son explication, Réessayer et Aide Apple sont visibles. Aucun appareil n’est encore disponible pour valider une reconnexion physique. La compilation release, les 41 tests et la vérification stricte de signature réussissent.

Vérification complémentaire du build 7 : le libellé du commutateur est « Afficher les numéros de série » dans le Check et la configuration, avec la même terminologie dans l’aide d’export. Après relance, l’app a reconnu un iPhone17,1 sous iOS 27.2. Le Check natif s’est terminé avec 30 données disponibles et 9 sources consultées ; les lignes batterie, carte logique et composants ciblés affichent des valeurs lues masquées. Le parcours natif de lecture est donc désormais observé sur cet appareil. L’export de ce rapport réel n’a pas été exécuté.

Build 8 : des boutons Copier ont été ajoutés au tableau et aux fiches pour le numéro de série, l’ECID, l’IMEI et les séries de composants disponibles. Les boutons de numéro de série et d’IMEI ont été actionnés dans l’app avec les valeurs visuellement masquées ; ils ont affiché « Copié » après succès de l’écriture de la valeur source complète dans le presse-papiers. Le clic n’ouvre pas le détail du contrôle. Les contrôles sans valeur et les lignes Wi-Fi/Bluetooth ne proposent pas cette action. La fiche IMEI et le tableau ont été inspectés visuellement.

## Vérifications de la version 0.1.6

Les 47 tests du cœur passent. Six nouveaux tests couvrent le relevé initial sans fausse validation, les égalités/écarts, la conservation des erreurs de lecture, l’exclusion des mesures évolutives, l’identité ECID/modèle et la séparation démo/réel, l’import des schémas 2 et 3 depuis les valeurs lues uniquement, le rejet des rapports masqués/dupliqués/trop volumineux/incompatibles, les permissions des fichiers et la sauvegarde de la référence précédente. La comparaison conserve séparément le statut de diagnostic et le résultat de comparaison. Aucune valeur d’origine usine n’est inventée.

Essais natifs 0.1.6 : en aperçu, l’enregistrement produit quatre lignes « Relevé initial », puis une nouvelle lecture produit quatre valeurs identiques. L’import d’un rapport synthétique daté du 30 septembre avec un autre numéro de série produit trois égalités et un écart. L’import d’un rapport marqué masqué est refusé en français sans remplacer la référence précédente. Après sortie du mode aperçu, un Check réel de l’iPhone17,1 sous iOS 27.2 a été enregistré comme référence datée, puis relu : 23 valeurs identiques, zéro écart. Il s’agit de l’observation actuelle, sans certification usine. L’export natif masqué a été relu : schéma 3, provenance non certifiée, 23 comparaisons et toutes les valeurs/références sensibles masquées. Aucun identifiant réel n’a été ajouté au dépôt.

Après redémarrage du build 9, la référence enregistrée a été rechargée avec sa date d’origine. Un nouveau Check retrouve 23 valeurs identiques et zéro écart. Le tableau a été inspecté : les références sont renseignées et les numéros de série restent masqués. La signature du bundle et l’intégrité de l’archive de distribution ont été vérifiées.

## Vérifications de la version 0.1.7

Retouche visuelle uniquement : suppression des chevrons des lignes du Check et de leur espace dans l’en-tête ; remplacement des illustrations par GlassIcon et PhoneIllustration en SwiftUI. La compilation release et la vérification stricte de signature réussissent. Inspection native de la vue d’ensemble, des petites icônes de navigation, du tableau et de la carte IPSW : icônes lisibles, reflets visibles, colonnes alignées et absence de chevrons à droite des lignes. Un Check réel s’est terminé et le clic sur Modèle ouvre toujours la fiche détaillée. Les anciens PNG sont absents des ressources distribuées. Aucun changement du moteur de restauration et aucune restauration lancée. Les 47 tests du cœur précédemment validés n’ont pas été relancés pour cette retouche visuelle.

Build 11 : les rotations 2D et 3D de GlassIcon ont été supprimées pour toutes les tailles. Compilation release réussie ; après relance, l’icône IPSW a été inspectée dans l’app et apparaît droite, de face, avec ses reflets conservés.

## Vérifications de la version 0.1.8

Les 50 tests du cœur passent. Les trois nouveaux tests couvrent la distinction couleur de façade/boîtier, la correspondance exacte du modèle et du code de finition dans le catalogue, le repli neutre pour une finition absente ou inconnue, et la validation de la lecture ciblée sans écraser une valeur déjà présente.

Sur l’iPhone17,1 connecté, la réponse générale expose DeviceColor mais omet DeviceEnclosureColor ; la requête ciblée fournit le code 4. Le catalogue MobileDevices de macOS le résout en com.apple.iphone-16-pro-4. Dans l’app relancée, la carte affiche « iPhone 16 Pro » et la représentation système avec son cadre doré, de face. L’écran reste l’illustration système ; aucune capture du contenu de l’appareil n’a été demandée. Les images Apple sont chargées depuis macOS, sans copie dans le dépôt ou dans la distribution.

Le menu garde les icônes grises pour les rubriques inactives, colorées au survol et pour la rubrique sélectionnée ; la sélection colorée hors survol a été observée dans la vue d’ensemble. Le skill itelier-glass-ui est installé dans le dossier personnel Codex et conservé dans le projet, avec un exemple SwiftUI autonome. Son validateur passe et l’exemple a été vérifié par swiftc -typecheck.

## 0.2.0 · build 25 · Guided tour, appearance, language and Dock

- First-launch tour: six steps, previous/next, skip/close persisted, replay in Configuration. Does not start device operations or replace existing device selection. Safety recovery takes precedence.
- Dark (default), light and system appearance persisted; semantic palette for every page and sheet. French and English source-copy catalogue, interpolated arguments kept literal, selected language propagated to detached workers. Native system menus follow on next launch.
- Configuration / Infos: Designed in Belgium, MIT project, independent/open-source positioning and dependency attribution. No invented public repository URL.
- visionOS catalogues: IPSW.me + separate AppleDB visionOS index; original Vision Pro and M5 displayed. Apple-only downloads and existing-file verification unchanged. Direct restore explicitly rejected by the core validator; local backup disabled for Vision Pro. Guide links to Apple's Configurator + Developer Strap procedure.
- Removed typed CONSERVER/EFFACER confirmation; existing target, hash, mode and acknowledgment validation remains. Active restore mode captured separately for the progress badge.
- Device selector rendered inside the app bounds; sidebar includes device name, OS and serial copy. Close buttons share the same grey circular background in both themes.
- Dock tile: determinate progress, indeterminate ring, paused state, reduced-motion support, resets when idle. Dock menu exposes devices/navigation, download pause/resume/cancel and restore status. No restoration pause: firmware writing continues without suspension.

Validation: 72 core tests passing, including localization argument preservation/translation placeholders and Vision Pro catalogue/native-restore boundary. Native UI checked in French/dark and English/light: six tour pages, About, settings, contained device selector, visionOS catalogue. Standalone AppKit Dock integration check verifies progress/pause/indeterminate/reset, without touching a device. No real restore or backup launched by this validation.

Official Vision Pro reference: https://support.apple.com/guide/apple-configurator-mac/apd819aacb61/mac

## Build 26 · Device information sheet

The sidebar info button and Overview / Show all open a contained device information sheet with model artwork, identity, copyable serial/IMEIs, expandable technical information, storage and current battery charge. Quick actions navigate to existing pages without starting an operation. A lightweight read requests only lockdown identity, battery and disk domains; it reserves USB access against concurrent device operations and checks device identity. Opening while an operation is active shows available information without a new USB read. Data never comes from the reference screenshots; unavailable account/carrier/phone fields remain marked as not exposed.

Storage uses matching data-partition total and available-byte fields, never mixes data-partition free space with whole-disk size. Charge accepts only finite percentages from 0 to 100, without estimating battery health. Added a test for missing, invalid, full-disk and mismatched-partition values. 73 core tests pass.

## Build 29 · ReWork, fiches Batterie et Stockage

- Nom visible et produit distribuable : **ReWork**. Identifiant de bundle, préférences et dossiers historiques conservés ; import de références compatible avec les exports iTelier et ReWork.
- Cartes Batterie et Stockage de même hauteur et entièrement cliquables. Batterie : jauge native, capacités en mAh, cycles, tension, intensité, puissance calculée et série copiables ; rafraîchissement facultatif toutes les 15 secondes et export texte sans identifiants. Les capacités imbriquées dans `IORegistry.BatteryData` sont lues. Le champ `GasGauge.FullChargeCapacity` peut être un pourcentage et n’est jamais présenté comme des mAh.
- Stockage : sections Répartition, Mémoire flash et Caractéristiques techniques. `com.apple.disk_usage.factory` fournit les catégories supplémentaires ; `installation_proxy` fournit les tailles agrégées des applications et de leurs documents. Les noms des applications restent dans le helper et ne sont ni retournés ni enregistrés. PhotoUsage et CameraUsage ne sont jamais additionnés. Les compteurs incohérents ne produisent pas une répartition inventée.
- Espace utilisable : priorité à `AmountDataAvailable`, car `TotalDataAvailable` surestimait l’espace disponible sur l’appareil de validation. Les volumes système et données sont additionnés uniquement lorsque les deux couples capacité/disponible sont valides. L’espace purgeable n’est pas déduit d’une différence entre compteurs.
- Contrôleur NAND découvert dans l’inventaire IOService avec validation stricte du nom. Fournisseur, type annoncé dans le nom NAND, modèle, firmware, série et limites d’entrée/sortie proviennent de propriétés exactes du contrôleur.
- Opérateur : lecture des profils CarrierBundleInfoArray, y compris identifiant et version. Compte Apple : affichage explicitement masqué de la valeur `NonVolatileRAM.fm-account-masked` transmise par iOS.
- Fond personnel : lecture USB SpringBoardServices par un helper isolé, durée et sortie bornées ; image gardée en mémoire seulement pour les appareils connectés. L’horloge utilise l’heure et le fuseau communiqués par l’iPhone. La disposition est illustrative, pas une capture de l’écran verrouillé. Le fond iOS 27 de remplacement contesté n’est plus sélectionné.

Validation : compilation et signature du bundle ReWork ; **89 tests du cœur réussis**, y compris les tests de sécurité ajoutés par Claude. Lectures USB réelles validées pour la batterie, les catégories Photos et Applications, le contrôleur Hynix/TLC et le fond personnel. Vérification visuelle des fiches Batterie et Stockage, du compte masqué, de l’opérateur et du fond personnel avec horloge. Aucune restauration ni sauvegarde réelle lancée.

API du fond personnel : [libimobiledevice, sbservices_get_home_screen_wallpaper_pngdata](https://libimobiledevice.org/docs/libimobiledevice/latest/sbservices_8h_a750e1b69e7ddf098b8039ad5eb8993b6.html).
