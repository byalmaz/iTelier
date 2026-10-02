# Analyse UI/UX de ReScope

Direction UX et visuelle retenue au 1er octobre 2026.

ReScope est une application native macOS 13 et versions suivantes, réalisée avec SwiftUI. Sa première fonction est la restauration d’un iPhone ou d’un iPad à partir d’un fichier IPSW. Sa seconde fonction est un contrôle de l’appareil inspiré du rapport fourni dans la capture utilisateur. Le projet est destiné à GitHub, avec une licence MIT retenue provisoirement.

L’objectif de l’interface est de rendre une opération technique compréhensible, de réduire les erreurs de sélection et de montrer précisément ce que l’application a pu contrôler. Les fonctions de 3uTools servent de référence fonctionnelle. CleanMyMac sert de référence pour la hiérarchie et la qualité de présentation. ReScope conserve son propre nom, ses propres composants et ses propres illustrations.

## Hiérarchie et navigation

La navigation principale reste courte :

- **Vue d’ensemble** : identité et mode de l’appareil connecté, version du système, état de la connexion et résumé du dernier contrôle.
- **Restaurer** : parcours principal pour importer et vérifier un IPSW, puis préparer et lancer la restauration.
- **Vérification** : valeurs disponibles, contrôles comparatifs et vérifications manuelles.
- **Activité** : progression des opérations et journal local exportable.

Le sélecteur d’appareil reste identifiable dans la fenêtre. Une restauration affiche également l’identité de la cible dans son récapitulatif. Le nom commercial seul ne suffit pas lorsque plusieurs appareils du même modèle sont présents : afficher aussi un identifiant tronqué et le mode de connexion.

La vue d’ensemble s’organise en une grille avec une grande carte appareil et deux cartes d’action : **Restaurer depuis un IPSW** et **Vérifier l’appareil**. La carte appareil associe une illustration originale en volume, un halo cyan, l’identité de la cible et son mode de connexion. Les cartes de données sous cette grille présentent la batterie et les informations disponibles. Les données techniques complètes restent accessibles dans les détails.

Chaque écran possède une action dominante. Un écran de contrôle ne lance pas automatiquement une restauration. Le contenu descriptif, le résultat des vérifications et les boutons d’action doivent être visuellement séparés.

La documentation de Smart Care décrit un parcours analyse, présentation des résultats en tuiles, consultation des détails et exécution des actions choisies. Ce principe de dévoilement progressif convient à ReScope, avec des précautions supplémentaires pour une opération qui efface des données. Source : [MacPaw — Smart Care](https://macpaw.com/support/cleanmymac/knowledgebase/smart-care).

## Analyse de la capture du rapport de vérification

La capture du rapport 3uTools est une référence de besoins. Ses informations ne sont pas des données de test que ReScope doit présenter comme provenant d’un appareil réel.

| Observation | Effet sur la compréhension | Décision pour ReScope |
| --- | --- | --- |
| Score de 97 et étoiles | Le résultat paraît précis alors que la méthode et la couverture ne sont pas visibles. | Afficher une couverture des contrôles plutôt qu’une note globale. |
| Bandeau « No issues found » avec contrôles inconnus ou en attente | Le message général est plus affirmatif que les résultats détaillés. | Écrire « Aucune anomalie parmi les contrôles disponibles » uniquement si les données le justifient. |
| Valeur usine « Empty » ou « Unknown » avec résultat « Normal » | Une simple lecture paraît certifier une correspondance. | Distinguer une valeur lue d’une valeur réellement comparée. |
| « Battery Life 0% » | Santé de batterie, charge actuelle et donnée absente se confondent. | Utiliser un libellé précis et conserver « Indisponible » lorsque la valeur manque. |
| « ID Lock On » en rouge | Un état de sécurité peut être interprété comme une panne. | Expliquer ce qui a été observé et son éventuel impact sur l’activation après restauration. |
| Table très dense de numéros de série | L’utilisateur doit interpréter beaucoup de données avant de comprendre ce qui demande son attention. | Présenter un résumé puis des catégories détaillées. |
| « Unknown », « Pending Inspection » et liens de contrôle | Le niveau de certitude et l’action suivante sont mélangés. | Expliquer pourquoi un contrôle manque et proposer une action lorsqu’elle existe. |
| Date numérique sans convention explicite | Le jour et le mois peuvent être confondus. | Utiliser une date localisée, par exemple « 30 sept. 2026, 14:25 ». |
| Identifiants visibles dans le rapport | Un partage peut révéler des données inutiles au destinataire. | Masquer les identifiants dans les exports par défaut. |

3uTools décrit son rapport comme une comparaison entre les valeurs actuelles et les valeurs d’usine, puis attribue un score selon les correspondances. La liste de fonctions publiée par 3uTools ne prouve pas que notre moteur open source puisse accéder aux mêmes données. Source : [3uTools — iDevice Verification](https://www.3u.com/tutorial/articles/7614/3utools-idevice-verification-let-you-check-if-your-idevice-is-original).

## Décision : couverture et états explicites

ReScope n’utilise pas de score de santé arbitraire. Le résumé annonce la portée du rapport, par exemple : **« Contrôle partiel · 8 contrôles disponibles · 3 vérifications manuelles »**. Ces nombres sont calculés à partir du rapport effectivement produit.

Les états du rapport sont distincts :

| État | Signification | Présentation |
| --- | --- | --- |
| **Lu** | La valeur a été récupérée, sans référence comparative. | Icône informative et libellé neutre. |
| **Correspondance** | Une référence disponible a été comparée à la valeur actuelle et les valeurs correspondent. | Icône de validation et libellé explicite. |
| **Différence** | Les valeurs comparées diffèrent; la cause reste à interpréter. | Icône d’attention, deux valeurs et méthode. |
| **À vérifier** | Un test manuel ou une autre source est nécessaire. | Action ou instruction correspondante. |
| **Indisponible** | Le modèle, le système, le mode de connexion ou le moteur ne permet pas cette lecture. | Motif de l’indisponibilité. |
| **Erreur de lecture** | Une lecture attendue a échoué. | Erreur compréhensible et possibilité de réessayer lorsque cela est pertinent. |

Une donnée absente reste absente. Elle ne devient ni zéro, ni une valeur normale, ni un contrôle réussi. Une différence de numéro de série ne suffit pas à certifier qu’une pièce est contrefaite. Une simple égalité avec une référence saisie par l’utilisateur ne devient pas une validation d’origine usine.

Le rapport est organisé par **Identité**, **Batterie**, **Composants**, **Connectivité** et **Sécurité**. La table détaillée contient **Élément**, **Valeur lue**, **Référence disponible** et **Résultat**. Le détail d’une ligne expose la source, la méthode, l’horodatage et les limites éventuelles.

La santé de batterie et le niveau de charge sont deux mesures distinctes. Les tests Face ID, caméra, écran ou capteurs peuvent être manuels lorsque le moteur ne fournit pas de diagnostic exploitable. L’interface explique alors ce qu’il reste à vérifier.

Les exports masquent les identifiants par défaut. Leur inclusion exige une action explicite. Un rapport enregistré indique qu’il s’agit d’un instantané; il ne donne pas l’impression de suivre en direct un appareil déconnecté.

## Parcours de restauration IPSW

### 1. Sélectionner l’appareil

Identifier clairement la cible et son mode : normal, confiance requise, récupération ou DFU. Si aucune cible n’est disponible, afficher des instructions de connexion. Lorsque plusieurs cibles existent, demander la sélection dans l’application avant toute préparation de restauration.

### 2. Choisir le fichier

Proposer le glisser-déposer et le sélecteur de fichiers natif. Après inspection, afficher le nom du fichier, la version système, le numéro de build et les modèles compatibles extraits du manifest. Le choix d’un fichier ne déclenche aucune écriture sur l’appareil.

### 3. Vérifier la préparation

Présenter séparément la validité du fichier, la compatibilité avec la cible et la disponibilité du moteur de restauration. La compatibilité locale ne prouve pas que le firmware est encore accepté par Apple. L’état de signature reste « Non vérifié » tant qu’un contrôle effectif ne l’a pas établi; une impossibilité de contact réseau ne doit pas être présentée comme un refus de signature.

### 4. Préparer l’opération

Expliquer les prérequis qui s’appliquent à la cible : sauvegarde, connexion USB et passage éventuel dans un mode approprié. Les instructions de boutons doivent correspondre au modèle détecté. Rappeler que les identifiants du compte Apple peuvent être nécessaires à l’activation après la restauration. Un état inconnu du verrouillage ne doit pas être transformé en état désactivé.

### 5. Confirmer l’effacement

Un récapitulatif présente l’appareil cible, le fichier et la version. Le message **« Toutes les données de cet appareil seront effacées »** précède une confirmation explicite, non cochée au départ. Le bouton final porte le libellé **Effacer et restaurer** et une apparence destructive native. Le choix du fichier et la confirmation finale restent deux étapes différentes.

### 6. Suivre la restauration

Afficher la phase actuelle, une progression réelle lorsqu’elle existe et un journal consultable. Lorsque le moteur ne fournit pas de pourcentage fiable, une progression indéterminée avec le nom de la phase est préférable. Ne pas annoncer une durée précise sans mesure.

L’annulation est disponible avant le lancement. Pendant une écriture, l’interface ne promet pas une annulation sans conséquence. Les changements de mode et les reconnexions attendues ne sont pas automatiquement présentés comme des pannes.

### 7. Terminer ou récupérer

Le succès correspond au résultat réel du moteur. Présenter ensuite les actions nécessaires sur l’appareil. En cas d’échec, conserver le journal, expliquer la phase concernée et proposer une prochaine action adaptée. Le bouton de reprise ne doit pas déclencher silencieusement une nouvelle opération destructive.

Les tutoriels de 3uTools distinguent l’import du firmware, les modes de restauration et la recherche de versions signées. Leurs conseils de préparation incluent la sauvegarde, la connexion USB et les identifiants iCloud. Sources : [3uTools — Pro Flash](https://www.3u.com/tutorial/details/8806/everything-you-need-to-know-about-pro-flash-on-3utools), [3uTools — préparation à la restauration](https://www.3u.com/tutorial/articles/7/3utools-flashes-ios-in-pro-mode-tutorial).

## Originalité visuelle

La direction retenue s’appuie sur la capture CleanMyMac fournie : un **fond indigo continu**, une **sidebar intégrée**, des **cartes de verre gris violet**, une **typographie grande et légère**, des **halos cyan** et des **boutons principaux jaunes**. La représentation de l’appareil et les icônes en volume sont des créations originales pour ReScope. Le nom, le logo et les illustrations appartiennent à sa propre identité.

Le fond principal et la sidebar partagent l’indigo `#1C1533`. Leur séparation repose sur l’espacement et la hiérarchie de navigation. L’état sélectionné utilise une surface lumineuse discrète et un libellé lisible. Les cartes superposent un gradient blanc translucide d’environ 8 à 13 %, un contour clair fin et des angles arrondis. Ces surfaces restent dans la même gamme sombre que la fenêtre.

Le texte principal est presque blanc; les descriptions utilisent un lavande clair `#C6C1D8`. Le cyan `#43D6F1` éclaire les halos, les symboles et certaines informations. Le jaune `#FFD731`, associé à un texte indigo, attire l’attention sur l’action principale. Les boutons secondaires reprennent le verre lavande et son contour clair. La confirmation finale d’effacement conserve un traitement corail distinct et un libellé destructif explicite.

L’inspiration porte sur les principes : contenu aéré, titre lisible, action centrale, résultats répartis en cartes et détails accessibles progressivement. Le site officiel de [CleanMyMac](https://cleanmymac.com/) et la documentation de [Smart Care](https://macpaw.com/support/cleanmymac/knowledgebase/smart-care) constituent les références visuelles et de parcours.

La grille d’accueil donne un poids visuel fort à l’appareil et rend immédiatement visibles les deux fonctions initiales. L’illustration de l’iPhone ou de l’iPad utilise un volume métallique sombre, des reflets lavande et un éclairage cyan. Les symboles de navigation et de fonctions suivent le même langage de volume et de lumière. L’illustration est décorative; les valeurs de batterie, les états et les résultats proviennent des données réellement lues.

Les cartes regroupent des informations utiles. Les effets de verre, les halos et les animations ne portent pas à eux seuls la signification d’un état. Les badges de contrôle conservent un texte et une icône, avec des couleurs suffisamment claires sur les surfaces sombres.

La typographie est celle du système macOS. Les grands titres de fenêtre utilisent une graisse légère et une taille d’environ 40 à 44 points; les titres de cartes restent entre 22 et 28 points. La navigation et les actions gardent une taille plus compacte et une graisse lisible. Les contrôles, menus, sélecteurs de fichier et confirmations utilisent les conventions natives. Le corail signale l’effacement et les erreurs pertinentes; un champ inconnu reste neutre et expliqué.

## Accessibilité

- Toutes les actions sont accessibles au clavier, avec un ordre de focus cohérent.
- Les boutons, icônes et états ont des libellés exploitables par VoiceOver.
- Les états combinent texte, icône et couleur; la couleur seule ne transmet aucune information nécessaire.
- Les textes secondaires et les badges conservent un contraste suffisant sur l’indigo et les cartes translucides. Les petites tailles de texte ne reprennent pas les couleurs les plus atténuées des reflets décoratifs.
- La fenêtre peut être redimensionnée et les données longues restent accessibles sans masquer l’action principale.
- Les animations respectent la préférence de réduction des mouvements.
- Une progression ne déclenche pas une succession d’annonces VoiceOver pour chaque ligne de journal.
- Les messages d’erreur expliquent ce qui s’est produit, son effet et l’action possible.

## États d’erreur et contraintes

| Situation | Réponse de l’interface |
| --- | --- |
| Aucun appareil | Instructions courtes de connexion et attente explicite. |
| Confiance non accordée | Expliquer la validation à effectuer sur l’appareil, puis proposer une nouvelle lecture. |
| Mode récupération ou DFU | Afficher le mode et les fonctions effectivement disponibles; certaines données du rapport seront absentes. |
| Moteur ou dépendance absent | Afficher le composant manquant et désactiver le lancement de l’opération concernée. |
| IPSW illisible ou manifest absent | Expliquer le problème du fichier et permettre d’en choisir un autre. |
| Modèle incompatible | Montrer la cible et les modèles du firmware; empêcher le lancement. |
| Signature inconnue ou réseau indisponible | Conserver cet état séparé de la compatibilité locale et d’un refus Apple. |
| Signature refusée | Expliquer que ce firmware n’a pas été accepté et permettre de sélectionner une autre version. |
| Perte USB inattendue | Conserver les informations et le journal, puis expliquer la reconnexion adaptée à la phase. |
| Données diagnostiques partielles | Produire un rapport partiel avec la couverture et les motifs d’indisponibilité. |
| Échec de restauration | Montrer la phase, un message utile et les détails exportables. |

La première version doit documenter les possibilités de son moteur plutôt que reproduire toutes les cases de la capture. L’accès aux valeurs de composants, aux références usine et à certains états de sécurité dépend de la cible et des outils utilisés. Un mode de démonstration éventuel doit être identifié en permanence et séparé d’un appareil réellement connecté.

Les lectures et les journaux restent locaux par défaut. Les erreurs techniques peuvent être consultées dans les détails sans encombrer le parcours principal. Toute future collecte ou transmission de diagnostics doit être visible et volontaire.

## Sources primaires

- [MacPaw — Smart Care : analyse, résultats, détails et actions](https://macpaw.com/support/cleanmymac/knowledgebase/smart-care)
- [CleanMyMac — site officiel](https://cleanmymac.com/)
- [3uTools — fonctionnement du rapport de vérification](https://www.3u.com/tutorial/articles/7614/3utools-idevice-verification-let-you-check-if-your-idevice-is-original)
- [3uTools — Pro Flash, import du firmware et versions signées](https://www.3u.com/tutorial/details/8806/everything-you-need-to-know-about-pro-flash-on-3utools)
- [3uTools — préparation à la restauration](https://www.3u.com/tutorial/articles/7/3utools-flashes-ios-in-pro-mode-tutorial)

Les tutoriels de 3uTools expliquent leurs propres fonctions et incluent des procédures anciennes. Ils servent ici à comprendre les besoins et les étapes d’un utilisateur, sans être repris comme instructions universelles pour chaque iPhone ou iPad moderne.

## Évolution 0.1.2

Le catalogue affiche toutes les versions par défaut : filtres Toutes / Publiques / Bêtas et case Signées uniquement. Une version visible est sélectionnée pour rendre Télécharger immédiatement disponible ; le panneau de destination reste l’étape explicite suivante. Les téléchargements sont permis dans l’aperçu, car ils ne modifient aucun appareil. Les menus et panneaux macOS suivent la localisation française du bundle.

Dans Restaurer, la case Conserver les données est cochée par défaut. La désactiver affiche Tout effacer et son avertissement explicite. Les prérequis et la confirmation s’adaptent au mode : sauvegarde récente et mot CONSERVER pour une mise à jour, avertissement destructif et mot EFFACER pour l’effacement. Une incompatibilité du mode conservation est expliquée sans changer automatiquement le choix.
