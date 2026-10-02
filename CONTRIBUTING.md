# Contribuer à iTelier

Les contributions doivent préserver trois propriétés : une interface compréhensible, une mesure dont la source est explicite et une restauration déclenchée sur une cible identifiée.

## Développement

Utiliser macOS 14 ou plus récent et Swift 6 ou plus récent. iTelier emploie Swift Package Manager et le mode de langage Swift 5 pour cette première version.

```sh
swift test
python3 scripts/prepare-runtime.py
bash scripts/build-app.sh --debug
open dist/iTelier.app
```

Avec les Command Line Tools sans XCTest, utiliser `bash scripts/test-core.sh`. Le helper se teste séparément avec `python3 scripts/test-restore-host.py`, sans appareil. Voir [les validations et leurs limites](docs/testing.md).

Le mode de démonstration suffit pour travailler sur l’interface. Il doit rester clairement identifiable et ne peut jamais lancer de commande destructive.

## Une pull request utile

Décrire le problème rencontré, le comportement après modification et la validation effectuée. Pour une évolution de l’interface, ajouter une capture sans identifiants personnels. Pour une évolution USB, indiquer le modèle, la version du système de l’appareil et la version des outils externes. Préciser si l’essai portait sur une lecture, une transition de mode ou une restauration complète.

Ajouter des tests pour les parseurs, validations et décisions qui protègent la restauration. Les données de test doivent être synthétiques ou anonymisées et avoir une origine réutilisable. Ne pas ajouter un test qui lance `idevicerestore` sur un appareil réel dans la CI.

## Contraintes produit

- Afficher **Indisponible** lorsqu’une donnée ne peut pas être lue ; ne pas la remplacer par une valeur plausible.
- Conserver la distinction entre une mesure, une hypothèse et un contrôle manuel.
- Ne pas annoncer une authenticité des pièces ou une référence usine sans une source vérifiable.
- Ne pas contourner le verrouillage d’activation ou les exigences de signature Apple.
- Invoquer les outils avec des arguments structurés, sans passer un chemin IPSW dans une commande shell interpolée.
- Préserver la confirmation explicite propre à chaque mode, l’identification de la cible et l’absence de repli du mode conservation vers l’effacement.
- Masquer ou supprimer les numéros de série, UDID, ECID et adresses réseau avant un partage public.

Les dépendances externes ne doivent pas être téléchargées ou installées en silence. Les outils USB inclus dans le bundle doivent conserver leurs versions, licences et origines documentées, ainsi que les étapes de signature.

## Avant la première release

Tester plusieurs appareils physiques et confirmer les parcours de sauvegarde et de restauration de bout en bout avant une release stable. La distribution à des utilisateurs nécessite un parcours de signature et de notarisation adapté ; le script actuel produit une app de développement avec signature ad hoc. Publier le code sur GitHub ne constitue pas une validation de ces opérations.
