# Le projet sur GitHub

Le dépôt iTelier contient le code Swift, les tests, les scripts de compilation, les assets de l’interface, la documentation et le workflow GitHub Actions. Le code du projet est sous licence MIT ; les assets et outils tiers conservent les conditions indiquées dans `LICENSE` et leur documentation.

Les firmwares IPSW, sauvegardes, rapports privés, journaux, préférences locales, dépendances téléchargées et builds restent hors du dépôt. Les fichiers vidéo encore en cours de travail ne font pas partie du premier envoi. Vérifier la liste des fichiers avant chaque commit et ajouter les fichiers voulus explicitement.

## Envoyer une modification

Depuis le dossier du projet, vérifier les changements, ajouter les fichiers concernés, puis envoyer le commit :

```sh
git status --short
git diff
git add -- chemin/du/fichier
git diff --cached
git commit -m "Décrire la modification"
git push origin main
```

Remplacer `chemin/du/fichier` et le message par les valeurs réelles. Si Git signale des changements distants, les examiner et les intégrer avant de pousser ; ne pas utiliser un envoi forcé.

## Compiler et distribuer

Le workflow [macOS build](../.github/workflows/macos.yml) lance les tests et compile une archive de développement, téléchargeable depuis son exécution dans l’onglet **Actions**. Une archive de CI n’est pas une release stable. La signature ad hoc et les limites des essais sur appareil physique sont décrites dans [le README](../README.md) et [les validations](testing.md).

Une release GitHub pourra ensuite regrouper une version testée, ses notes et l’app correspondante. Les firmwares et données d’appareils ne doivent jamais être joints à cette release.
