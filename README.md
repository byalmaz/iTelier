# iTelier

**The free, open-source alternative to 3uTools and iMazing on Mac.** iTelier is a native macOS app to inspect an iPhone or iPad, make local backups, browse firmware versions, download Apple-hosted IPSWs and restore them. It presents the data it can actually read, with explicit limits rather than an invented authenticity score.

**L’alternative libre et gratuite à 3uTools et iMazing sur Mac.** iTelier est une première version d’application macOS en SwiftUI. Elle propose un **Check** de l’appareil, des **sauvegardes locales** et une **restauration IPSW**, depuis un fichier local ou une version téléchargée avec son catalogue. Son interface associe un fond indigo continu, des cartes translucides, des halos cyan, des icônes vectorielles en verre irisé et des boutons jaunes. Le projet utilise sa propre identité visuelle et ne reprend aucun logo ni asset d’un autre logiciel.

- **Libre et gratuit** : code ouvert sous licence MIT, que chacun peut lire, vérifier et améliorer.
- **Natif sur Mac** : écrit en Swift et SwiftUI, avec les outils USB intégrés au bundle.
- **Sans compte** : vos sauvegardes et rapports restent sur votre Mac. Seuls les catalogues de versions et les firmwares d’Apple transitent par le réseau.
- **Honnête** : une donnée illisible reste indiquée comme telle, sans note d’authenticité inventée.

## Télécharger

[Télécharger iTelier pour Mac Apple Silicon (.dmg)](https://github.com/byalmaz/iTelier/releases/download/v0.2.0-beta.1/iTelier-macOS-arm64.dmg) · [Notes de la préversion](https://github.com/byalmaz/iTelier/releases/tag/v0.2.0-beta.1)

Préversion 0.2.0 (build 39), pour macOS 14 ou plus récent. Ouvrir le DMG et faire glisser iTelier dans Applications. Cette distribution de développement utilise une signature ad hoc et n’est pas notariée.

## État du projet

Version de développement 0.2.0 (build 39), macOS 14 ou plus récent. Les outils USB embarqués sont issus des paquets officiels Homebrew ciblés Sonoma.

- Application native, avec mode de démonstration pour explorer l’interface sans appareil.
- Outils de détection USB, de diagnostic et de restauration libimobiledevice/libirecovery/idevicerestore inclus dans l’app, avec leurs bibliothèques.
- Lecture des informations disponibles, validation locale de l’IPSW et parcours de restauration avec choix du mode et confirmation explicite.
- Catalogue iOS/iPadOS par modèle, avec versions publiques, bêtas, signées et non signées, et téléchargement direct depuis les serveurs Apple.
- Export JSON du rapport, avec identifiants masqués par défaut, et journal d’activité conservé pendant la session.
- Dossier de téléchargement automatique et actions Télécharger / Restaurer distinctes.
- Suivi persistant des interruptions, moteur indépendant de l’interface et rapport d’incident consultable, exportable ou partageable par macOS.
- Tests automatisés du cœur sans iPhone ou iPad connecté.
- Aperçu personnel de l’écran verrouillé lorsqu’il est disponible, dans une coque adaptée au modèle connecté. L’heure reçue dans l’aperçu peut être figée ; ce n’est pas un écran en direct.
- Illustrations de repli pour les appareils et le mode de démonstration, avec provenance documentée dans [les assets visuels](docs/visual-assets.md).
- Sauvegardes locales datées, chiffrement optionnel, ajout de sauvegardes Finder et restauration confirmée.
- Style UI réutilisable : [itelier-glass-ui](skills/itelier-glass-ui/SKILL.md).

Les tests sur de vrais appareils restent nécessaires avant une version stable, en particulier pour les changements de mode USB et les restaurations complètes. Un build réussi ne prouve pas qu’une restauration a été testée.

Validation locale du 2 octobre 2026 : **122 tests du cœur réussis** et helper de restauration validé avec un moteur inerte. Le bundle release `arm64` du build 39, son ZIP et son DMG ont été vérifiés, dont la signature ad hoc stricte et la migration des données locales. Le choix du chiffrement reste sur OFF après migration. Les versions précédentes ont validé la lecture USB des informations et de l’aperçu personnel de l’écran verrouillé. Une restauration avec conservation entreprise par l’utilisateur a échoué malgré un code moteur 0 : l’app refuse désormais cette fausse réussite et exige une confirmation terminale sans erreur fatale. Ce correctif ne résout pas l’échec de signature du composant et aucune restauration complète réussie sur appareil physique n’est confirmée. Voir [la portée de cette validation](docs/testing.md).

## Compiler et lancer

Prérequis de compilation : un Mac, Python 3 et une toolchain Swift 6 ou plus récente compatible avec le SDK macOS. Le script récupère les paquets officiels Homebrew ciblés Sonoma directement depuis leur registre public, aux versions et empreintes épinglées dans [`scripts/runtime-bottles.json`](scripts/runtime-bottles.json). Homebrew n’a pas besoin d’être installé, sur la machine de compilation comme sur le Mac qui exécute le bundle. Les outils en ligne de commande Apple suffisent lorsqu’ils incluent cette toolchain ; le projet ne nécessite pas de fichier `.xcodeproj` ni d’abonnement Apple Developer.

Depuis le dossier du projet :

```sh
python3 scripts/prepare-runtime.py
bash scripts/build-app.sh
open dist/iTelier.app
```

Pour les tests, utiliser `swift test` avec Xcode complet. Si les Command Line Tools ne fournissent pas XCTest, lancer les mêmes méthodes de test avec le runner autonome :

```sh
bash scripts/test-core.sh
python3 scripts/test-restore-host.py
python3 scripts/test-runtime-bottles.py
```

Le runner nécessite Swift 6 ou plus récent et Python 3 ; il n’utilise aucun appareil connecté. Voir [les détails des tests](docs/testing.md).

Pour une compilation de développement :

```sh
bash scripts/build-app.sh --debug
```

Pour découvrir l’interface avec des données fictives :

```sh
open dist/iTelier.app --args --demo
```

Le script produit `dist/iTelier.app` pour l’architecture du Mac qui compile. Il ne crée pas de binaire universel et n’installe rien. Une signature ad hoc est appliquée avec `codesign` lorsqu’il est disponible. L’app n’est pas signée avec Developer ID et n’est pas notariée. L’identifiant du bundle est `com.itelier.app`, pour cette distribution de développement `0.2.0`.

Au premier lancement du build 39, iTelier déplace les anciens dossiers de données et de téléchargements vers `iTelier`, puis reprend les réglages existants. Les sauvegardes, références et rapports restent accessibles. La migration refuse de remplacer un dossier déjà présent ou de déplacer les données pendant une opération active.

Dans un environnement qui empêche SwiftPM de créer son sandbox imbriqué, le script accepte l’option explicite `ITELIER_SWIFT_DISABLE_SANDBOX=1 bash scripts/build-app.sh`. Le sandbox SwiftPM reste actif par défaut, notamment dans la CI.

Pour créer une image d’installation depuis le bundle déjà compilé :

```sh
bash scripts/build-dmg.sh
```

Le fichier `dist/iTelier-macOS-arm64.dmg` (ou `x86_64` sur Intel) contient l’app et un raccourci vers Applications. Ouvrir le DMG, puis faire glisser iTelier dans Applications. Le script vérifie la signature du bundle et l’intégrité de l’image avant de remplacer un DMG précédent.

Le workflow [macOS build](.github/workflows/macos.yml) exécute les tests, compile l’app et dépose une archive ZIP et un DMG de développement en artifact GitHub Actions. Il ne publie pas de release automatiquement.

## Connecter un appareil réel

Le Check utilise `idevice_id`, `ideviceinfo` et `idevicediagnostics`. Le mode récupération utilise `irecovery`, et la restauration utilise `idevicerestore`. Les sauvegardes utilisent `idevicebackup2`. Les six outils et leurs bibliothèques sont inclus dans le bundle iTelier. Aucune installation séparée n’est nécessaire pour le bundle distribué.

L’app recherche d’abord ses exécutables intégrés dans `Contents/Helpers`, puis dans `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, `/bin`, puis dans les dossiers absolus du `PATH` hérité. Un outil installé dans un emplacement personnalisé doit être accessible depuis ce contexte ; le `PATH` d’une app lancée par le Finder peut différer de celui du terminal.

Pour une exécution directe via SwiftPM, ou pour développer avec des outils installés sur le Mac, utiliser les deux formules Homebrew officielles :

```sh
brew install libimobiledevice libirecovery
```

Sources : [libimobiledevice dans Homebrew](https://formulae.brew.sh/formula/libimobiledevice) et [libirecovery dans Homebrew](https://formulae.brew.sh/formula/libirecovery).

La restauration réelle nécessite le bundle complet, qui contient le module indépendant `iTelierRestoreHost`. Pour étudier ou compiler un moteur externe, suivre les [instructions macOS du projet amont](https://github.com/libimobiledevice/idevicerestore#macos). Elles décrivent l’installation des outils de compilation via Homebrew et la construction de `idevicerestore` avec ses dépendances. La documentation iTelier ne suppose pas l’existence d’une formule `idevicerestore` dans Homebrew core. Les taps tiers sont sous la responsabilité de leur mainteneur.

Pour le Check, brancher l’appareil par USB, le déverrouiller et accepter **Faire confiance à cet ordinateur** sur l’iPhone ou l’iPad. Une restauration peut utiliser un appareil en mode normal, récupération ou DFU selon l’état détecté ; l’app exige l’identification précise de la cible avant le lancement.

## Ce que signifie le Check

Le Check indique les valeurs lisibles et leur disponibilité. Les champs et services accessibles varient selon le modèle, la version d’iOS ou d’iPadOS et l’état de l’appareil. Une information absente devient **Indisponible**, pas une anomalie.

Depuis la version 0.1.4, le Check lit aussi les entrées ciblées `AppleSmartBattery`, `product` et les pilotes caméra réellement annoncés dans IOService. Il récupère, lorsqu’ils sont exposés, les identifiants de batterie, carte logique, caméras avant/arrière/ultra grand-angle/téléobjectif, infrarouge, projecteur de points, LiDAR, dalle, vitre et capteur de lumière. Les valeurs brutes de dalle et de vitre restent entières et sont nommées comme telles. Chaque ligne indique la source et la clé utilisées dans son détail.

Les états **Non exposé**, **Non pris en charge** et **Lecture échouée** sont distincts. Le panneau Sources consultées conserve le résultat de chaque requête, y compris une réponse `MobileGestaltDeprecated` malgré un processus terminé sans erreur. Les demandes de diagnostic sont sérialisées ; aucun test ne redémarre ou ne modifie l’appareil. Le schéma d’export Check passe à la version 3 et conserve le masquage par défaut, y compris pour les nouveaux identifiants.

iTelier ne dispose pas d’une base Apple des valeurs de sortie d’usine. Il ne peut donc pas certifier qu’un écran, une caméra ou une batterie est d’origine en comparant des numéros de série. Il n’attribue pas de note sur 100 et ne présente pas des données de démonstration comme des mesures réelles. Les contrôles nécessitant une observation, par exemple Face ID ou le tactile, doivent être réalisés sur l’appareil.

## Références de comparaison

Depuis 0.1.6, **Vérification → Enregistrer ce Check** remplit la colonne Référence avec un relevé daté. Une nouvelle lecture indique **Identique**, **Écart** ou **Non comparable**. Le premier relevé porte explicitement **Relevé initial** : enregistrer la lecture actuelle ne constitue pas une vérification indépendante. La charge, les cycles, la santé estimée, la version système et les tests manuels restent hors de cette comparaison des composants.

**Importer un rapport…** accepte les exports JSON iTelier de schéma 2 ou 3, ainsi que les rapports des versions précédentes, du même appareil, avec les numéros de série visibles. Les exports masqués, les modèles/ECID différents, les doublons et les fichiers trop volumineux sont refusés. Les valeurs comparées viennent de la colonne Valeur lue de l’ancien rapport, jamais d’une prétendue référence usine importée. Un rapport importé reste non certifié.

Les références sont enregistrées en local dans `~/Library/Application Support/iTelier/References`, avec des fichiers privés (0600), séparés pour chaque appareil et pour les exemples. Elles sont rechargées à chaque Check. **Remplacer par ce Check** conserve aussi la référence précédente dans un fichier `.previous.json`. L’export inclut les valeurs comparées et la provenance de la référence ; les valeurs sensibles restent masquées tant que l’affichage des numéros de série est désactivé.

## Restauration IPSW

Dans **Restaurer**, ouvrir le catalogue pour choisir une version. Le modèle connecté est présélectionné lorsqu’il est connu ; une recherche permet aussi de choisir un iPhone ou un iPad sans appareil branché. Le catalogue affiche par défaut toutes les versions disponibles, y compris les bêtas et les versions non signées. Les filtres Toutes / Publiques / Bêtas et Signées uniquement affinent la liste. Les versions non signées peuvent être téléchargées pour archivage, mais une restauration standard ne peut pas les installer et leur lancement reste désactivé dans l’app. Pour un fichier importé localement, la signature reste inconnue jusqu’au contrôle du moteur.

Après le choix d’une version, **Télécharger** démarre directement dans **Téléchargements/iTelier**. Ce dossier est créé automatiquement ; **Configuration → Dossier des fichiers IPSW** permet de le modifier ou de l’ouvrir. **Restaurer…** télécharge aussi l’IPSW, puis ouvre la préparation avec le choix de conserver ou d’effacer les données et une confirmation finale. Un firmware déjà chargé dans la session est réutilisé, avec revalidation avant écriture. Le transfert affiche sa progression et peut être annulé ; il ne reprend pas encore un téléchargement interrompu. Une fois le fichier téléchargé, l’app contrôle la taille annoncée, compare l’empreinte SHA-256 lorsqu’elle est fournie par le catalogue, puis calcule son empreinte locale et vérifie le manifeste avant de le proposer pour le parcours de restauration. Le téléchargement ne lance jamais une restauration et n’exige pas les outils USB externes. Le téléchargement reste disponible en mode aperçu ; les opérations sur l’appareil y restent désactivées.

Les métadonnées proviennent des catalogues tiers [IPSW.me](https://ipsw.me/api/) et [AppleDB](https://github.com/littlebyteorg/appledb/blob/main/API.md), dont la publication officielle GitHub complète les bêtas et les archives. L’indice AppleDB est gardé en mémoire cinq minutes ; une source indisponible est signalée sans masquer les résultats de l’autre. L’app lui demande le catalogue et l’identifiant générique du modèle, par exemple `iPhone16,1` ; elle ne lui transmet pas de numéro de série, UDID, ECID ni rapport de diagnostic. Les octets de l’IPSW sont téléchargés directement sur une URL Apple autorisée en HTTPS, avec redirections restreintes. Les entrées dont le lien n’est pas un IPSW Apple en HTTPS sont écartées ; le catalogue affiché peut donc omettre des liens historiques en HTTP. Apple documente ses hôtes de téléchargement dans [sa liste de domaines réseau](https://support.apple.com/fr-fr/101555).

L’état « signé » correspond aux métadonnées récupérées à la date de consultation du catalogue. Il peut évoluer ; seul le moteur de restauration obtient la réponse de signature Apple pour l’opération en cours. Un fichier téléchargé avec succès ne constitue pas une garantie d’installation. Pour la validation du catalogue, les réponses JSON publiques et les en-têtes d’une URL Apple ont été consultés ; aucun IPSW de plusieurs gigaoctets n’a été téléchargé intégralement pour ces essais.

Avant tout téléchargement depuis le catalogue, iTelier recherche les IPSW complets dans le dossier configuré, même après redémarrage. Le nom du fichier ne suffit pas : modèle, version, build, taille et intégrité doivent correspondre. L’empreinte du catalogue est vérifiée lorsqu’elle existe ; sinon, toutes les entrées ZIP sont contrôlées. Un fichier valide est réutilisé sans transfert réseau. Les copies invalides et partielles restent intactes et ne sont pas proposées pour la restauration.

Pendant le téléchargement d’un IPSW, une carte unique affiche la progression et les commandes **Pause / Reprendre / Annuler**. La pause garde les données reçues tant qu’iTelier reste ouvert ; la reprise après fermeture de l’app n’est pas prise en charge. Après réception, la carte affiche la vérification avant de proposer le fichier pour la restauration.

Le réglage **Configuration → Restauration par défaut** mémorise si la case **Conserver les données** doit être cochée au lancement. Sans préférence enregistrée, la conservation est proposée. Une modification dans Restaurer vaut pour la session et ne remplace pas cette préférence. Changer le mode remet les confirmations à zéro. La case **Conserver les données** sélectionne une réinstallation en mode mise à jour. Elle exige une identité `Customer Upgrade Install (IPSW)` ou `Developer Upgrade Install (IPSW)` complète pour la carte de l’appareil, un iPhone/iPad en mode normal avec version lisible, et la même version ou une version plus récente. Les retours vers une ancienne bêta sont également bloqués. Le moteur reçoit `--variant` avec cette identité exacte, sans `--erase` : l’absence de cette variante provoque un échec, sans repli automatique sur l’effacement. La confirmation du mode est liée à l’appareil et au SHA-256 ; une case confirme la réinstallation et le risque de perte de données. Une sauvegarde récente reste nécessaire : une erreur de restauration peut entraîner une perte de données.

Décocher cette case sélectionne **Tout effacer**. Ce mode demande une confirmation explicite de l’effacement de l’appareil sélectionné, puis lance le moteur avec `--erase`. Dans les deux modes, Apple vérifie la signature du firmware et les conditions d’activation. Aucune restauration réussie n’est encore confirmée de bout en bout sur un appareil physique. [Comportement du moteur amont](https://github.com/libimobiledevice/idevicerestore#usage).

iTelier ne contourne ni le verrouillage d’activation, ni un code de déverrouillage, ni les restrictions de signature Apple. Une restauration peut échouer avec un IPSW non signé, un appareil incompatible ou une interruption USB. Ne débrancher l’appareil que lorsque le parcours indique que l’opération est terminée ou qu’il fournit une étape de récupération.

## Erreurs et interruptions

iTelier conserve un journal privé dans `~/Library/Application Support/iTelier/Support`. Une fermeture inattendue est détectée au prochain démarrage. Si elle concernait une restauration, aucune opération n’est relancée : l’interface retrouve le suivi du moteur encore actif, ou bloque une nouvelle tentative jusqu’à une vérification explicite de l’appareil. Ce blocage persiste même si l’utilisateur ferme puis rouvre l’app.

Le module indépendant `iTelierRestoreHost` possède le processus de restauration et ses canaux de sortie. Il conserve son état dans `~/Library/Application Support/iTelier/Restores`, empêche deux écritures simultanées et refuse de rejouer une requête consommée. Il demande à macOS d’éviter la veille automatique pendant l’opération. Une panne du Mac, un arrêt forcé du moteur ou une déconnexion USB restent susceptibles d’interrompre une restauration : ce dispositif ne garantit pas la récupération d’un appareil ni la conservation des données.

**Configuration → Signaler un problème**, l’écran Activité et les erreurs ouvrent le rapport d’incident. L’utilisateur peut ajouter une description, relire le JSON exact, le copier, l’exporter ou choisir **Envoyer…**. Le partage macOS lui laisse choisir le destinataire et valider l’envoi. Aucun rapport n’est envoyé automatiquement et aucun dépôt ou destinataire de support n’est préconfiguré. Les champs automatiques excluent numéros de série, UDID, ECID, noms d’appareils, chemins et journaux bruts ; le texte saisi par l’utilisateur doit être relu avant partage. Les journaux locaux du moteur peuvent contenir ces informations et ne sont pas joints au rapport.

## Contribuer et publier

Lire [CONTRIBUTING.md](CONTRIBUTING.md), [l’architecture](docs/architecture.md) et [l’analyse UI/UX](docs/ui-ux.md) avant une modification importante. Ne pas inclure de firmware, de rapport contenant des identifiants personnels, de captures avec un numéro de série complet ou de logs non expurgés dans un ticket public.

Voir [le guide GitHub](docs/github-publication.md) pour le contenu du dépôt et les prochains envois.

Le nom définitif de l’app est **iTelier**. Le [fichier de licence](LICENSE) couvre le code du projet sous licence MIT ; les outils externes conservent leurs licences respectives.

Projet indépendant, sans affiliation avec Apple ni avec les éditeurs de 3uTools et d’iMazing. iPhone, iPad et macOS sont des marques d’Apple ; 3uTools et iMazing appartiennent à leurs propriétaires respectifs.

## Sauvegardes locales

La rubrique **Sauvegardes** crée une copie complète avec `idevicebackup2 backup --full`, dans `~/Library/Application Support/iTelier/Backups` par défaut. L’emplacement peut être changé. Chaque opération utilise un nouveau dossier privé et conserve les copies précédentes. **Ajouter un dossier…** référence une sauvegarde Apple/Finder existante sans la déplacer ni la copier.

Contrairement au dossier de sauvegarde du Finder, que macOS protège, ce dossier est lisible par tout programme lancé dans la session de l’utilisateur. **Chiffrer la sauvegarde** est désactivé au premier lancement, puis mémorise le dernier choix. Le chiffrement protège le contenu des sauvegardes ; l’interface le rappelle lorsqu’il est désactivé.

Le chiffrement peut être activé avec un mot de passe confirmé dans l’interface. Cette activation concerne les futures sauvegardes de l’appareil ; un chiffrement déjà actif n’est jamais désactivé et son mot de passe reste inchangé. Aucun mot de passe n’est conservé sur disque. Il est transmis par un pipe sur l’entrée standard, au module de sauvegarde puis à `idevicebackup2 -i`, et jamais par les arguments, les variables d’environnement, les journaux ou les rapports : `ps eww` montre l’environnement d’un processus à tout programme de la même session. Ce mode n’accepte que 255 caractères ASCII imprimables au plus (lettres sans accents, chiffres, espaces, ponctuation) ; une sauvegarde protégée par un autre mot de passe se restaure avec le Finder. Consulter les [explications Apple sur le chiffrement](https://support.apple.com/fr-be/108353) et les [données prises en charge](https://support.apple.com/fr-be/108771).

**Restaurer…** affiche la copie source, la cible et une confirmation du remplacement des données. Le moteur restaure les données et réglages sans installer d’IPSW, sans option `--remove`. Cette première version limite les transferts à la même famille iPhone/iPad et refuse une sauvegarde provenant d’une version du système plus récente. Les apps peuvent devoir être téléchargées à nouveau. Le mot de passe d’une copie chiffrée est demandé.

Le helper indépendant poursuit l’opération si l’interface plante et permet de retrouver son suivi au lancement suivant. Une création peut être annulée ; une restauration de données ne propose pas d’arrêt en cours d’écriture. Quitter normalement est bloqué pendant ces opérations. Une sauvegarde interrompue n’est jamais proposée comme restaurable : il faut la confirmation du moteur, `SnapshotState=finished`, les métadonnées et le manifeste de fichiers. Ce contrôle ne constitue pas une vérification exhaustive de chaque fichier du contenu. La bibliothèque conserve l’état des copies incomplètes lisibles ; les dossiers interrompus avant la création des métadonnées restent accessibles via **Ouvrir le dossier**.

Les sauvegardes et restaurations réelles sur appareil physique restent à valider. Les tests utilisent uniquement des plists et moteurs fictifs.

### Personnalisation et prise en main

iTelier propose une visite guidée au premier lancement, accessible ensuite dans Configuration. Les réglages permettent de choisir le thème sombre (par défaut), clair ou système, ainsi que le français ou l’anglais. La rubrique Infos présente le projet, conçu en Belgique 🇧🇪.

Le Dock affiche la progression des opérations. Son menu donne accès aux appareils et aux rubriques, ainsi qu’à Pause/Reprendre pour un téléchargement. Une restauration ne peut pas être mise en pause pendant l’écriture du firmware.

Les firmwares visionOS sont disponibles dans le catalogue. Pour restaurer un Apple Vision Pro, iTelier propose un guide vers Apple Configurator et un Developer Strap compatible ; la restauration directe et les sauvegardes locales Vision Pro ne sont pas prises en charge.
