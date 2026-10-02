# Assets visuels ReScope

Depuis le build 17, la carte de l’appareil affiche son illustration sans anneau lumineux cyan.

## Fonds iOS et iPadOS embarqués (0.1.9)

Le build 18 complète la sélection avec iOS/iPadOS 16, 17 et 18, y compris en mode aperçu (18.7 → iOS 18). Les fonds 16/17 proviennent des [assets Apple archivés par SniperGER](https://github.com/SniperGER/iOS-Wallpapers), à une révision fixe ; les fonds 18 proviennent des extractions iClarified pour [iPhone](https://www.iclarified.com/93874/download-the-official-ios-18-wallpaper-for-iphone) et [iPad](https://www.iclarified.com/93901/download-the-official-ipados-18-wallpaper-for-ipad). Les fichiers HEIC/JPEG originaux sont conservés avec leurs sources et SHA-256 dans le manifeste. Seule la coque est désaturée quand la finition est inconnue : le fond reste en couleur.

Les fonds clairs iOS 26, iOS 27, iPadOS 26 et iPadOS 27 sont inclus dans `Resources/Wallpapers` et choisis selon la famille et la version majeure réellement lues sur l’appareil. Une version inconnue conserve le visuel système. Ils fonctionnent hors ligne ; aucun téléchargement ne se produit pour afficher la carte. La zone bleue connexe de l’icône système sert de masque : bordure, boutons et découpe de caméra restent visibles. Si ce masque n’est pas détectable, l’icône système est conservée.

Les fichiers sont les créations Apple publiées par [9to5Mac pour iOS 26](https://9to5mac.com/2025/06/09/download-the-new-ios-26-wallpapers-now/), [iPadOS 26](https://9to5mac.com/2025/06/10/ipados-26-light-and-dark-wallpapers/) et [iOS/iPadOS 27](https://9to5mac.com/2026/06/10/download-the-new-ios-27-and-ipados-27-wallpapers-here/). Le manifeste `WallpaperSources.json` conserve les URL et SHA-256. Ces œuvres tierces sont **exclues de la licence MIT du code ReScope** ; ReScope ne leur accorde aucune licence de redistribution.


Depuis la version 0.1.7, les icônes de fonction sont vectorielles et dessinées dans `Sources/ReScope/DesignSystem.swift`. `GlassIcon` associe une tuile translucide arrondie, une tranche irisée, des reflets et un SF Symbol blanc. Il est commun à la navigation, aux cartes, aux états vides et aux feuilles. Depuis le build 11, toutes les icônes sont droites et vues de face, quelle que soit leur taille ; les reflets et la tranche sont conservés. Depuis le build 12, les icônes du menu sont grises au repos et colorées au survol du bouton, avec une transition de 180 ms désactivée lorsque Réduire les animations est actif. La rubrique sélectionnée conserve son icône colorée, ainsi que son fond, même hors survol. Le style réutilisable est conservé dans [le skill rescope-glass-ui](../skills/rescope-glass-ui/SKILL.md). Les préférences d’accessibilité de réduction de transparence et d’augmentation du contraste sont prises en compte. Les symboles fonctionnels compacts (copier, fermer, actualiser, statuts) conservent leur dessin simple.

Depuis la version 0.1.8, `ConnectedDeviceArtwork` utilise les représentations d’appareils installées par Apple dans macOS, via `NSWorkspace.icon(for:)`. Le catalogue système MobileDevices associe exactement le ProductType et le code DeviceEnclosureColor à une variante. La couleur de façade DeviceColor ne sert pas de remplacement. Une lecture USB ciblée complète la couleur de boîtier absente de la réponse générale. Si la finition manque, la représentation du modèle est désaturée ; si le modèle ou le visuel système manque, un symbole générique est utilisé. L’écran est illustratif, sans capture des apps ou données de l’iPhone. Aucun artwork Apple n’est copié dans le dépôt ou redistribué dans le bundle. Les trois PNG ci-dessous sont conservés comme archives de conception, exclus de la cible SwiftPM et ne sont plus chargés dans l’app. Leur provenance est conservée ci-dessous. L’icône du Dock reste inchangée.

Les trois anciennes illustrations PNG de l’interface sombre mesurent chacune 1254 × 1254 pixels. Leurs quatre coins ont un alpha nul et leur sujet contient des pixels opaques : la transparence réelle a été vérifiée avec le décodeur natif AppKit, puis conservée lors de la copie dans le projet. L’utilisation dans le bundle est locale ; l’app n’a pas besoin de l’outil de génération pour afficher ces fichiers.

| Fichier du dossier `Sources/ReScope/Resources/` | Usage |
| --- | --- |
| `DeviceHero.png` | Illustration de l’appareil dans la vue d’ensemble. |
| `RestoreIcon.png` | Illustration du parcours de restauration. |
| `CheckIcon.png` | Illustration du parcours de vérification. |

L’icône d’application `assets/AppIcon.icns` et son aperçu `assets/AppIcon.png` sont des dessins vectoriels originaux rendus avec AppKit par `scripts/generate-icon.swift`. Ils sont distincts des illustrations générées décrites ci-dessous. L’ICNS contient les tailles de 16 à 1024 pixels et a été vérifié avec les décodeurs natifs macOS.

## DeviceHero.png

Illustration originale créée le 1er octobre 2026 avec l’outil intégré `image_gen.imagegen`, en mode génération sans image de référence, avec `transparent_background: true`. Aucun CLI ni appel API séparé n’a été utilisé.

Fichier destiné à l’interface : `Sources/ReScope/Resources/DeviceHero.png`. La transparence alpha du PNG généré est conservée ; le fichier original reste également dans le dossier de génération Codex. L’image représente un seul smartphone en vue trois quarts avec un cadre argent-violet et un écran abstrait cyan, bleu et lavande, sans logo, texte ou interface.

Prompt final :

```text
Use case: stylized-concept
Asset type: a single transparent 3D product illustration for the overview hero of a premium native macOS iPhone/iPad utility called ReScope.
Primary request: render one original modern iPhone-like smartphone in a subtle three-quarter front view, standing vertically with a slight elegant isometric tilt. The full front display and softly polished silver-violet metal edges are visible. The screen contains only an abstract luminous cyan, baby-blue and lavender-purple gradient, with no UI, no widgets and no text.
Style/medium: high-quality polished 3D product rendering, soft glossy materials, premium but calm, refined native macOS utility aesthetic.
Composition/framing: square canvas; center the complete device with approximately 20 percent breathing room around it on all sides; isolated device, simple silhouette, no cropped corners. Keep the device large enough to be clear at 250 pixels tall in an app.
Lighting/mood: soft studio lighting, restrained reflections, subtle purple rim light and soft contact-free shadow suitable for compositing over a dark indigo app background.
Materials/textures: smooth metal frame with silver-lavender tint, glass screen, precise softly rounded edges.
Scene/backdrop: genuinely transparent background with real alpha transparency. No solid backdrop, no floor, no scenery, no background rectangle; preserve soft translucent edge shadow only.
Constraints: exactly one smartphone, no Apple logo, no brand logo, no camera brand detail, no lettering, no watermark, no cable, no extra objects. Do not generate an application interface or entire UI.
```

L’illustration illustre l’appareil dans la vue d’ensemble et ne constitue pas une photographie du matériel connecté. Elle a été produite pour ce projet et ne reprend aucun artwork d’un autre logiciel.

## RestoreIcon.png et CheckIcon.png

Deux illustrations créées le 1er octobre 2026 avec deux appels indépendants à l’outil intégré `image_gen.imagegen`, chacun en génération sans référence et avec `transparent_background: true`. Les PNG conservent leur alpha réel et sont copiés dans `Sources/ReScope/Resources/`. Les originaux restent dans le dossier de génération Codex.

`RestoreIcon.png` représente les deux flèches d’un cycle de restauration en verre lavande perlé. `CheckIcon.png` associe un petit appareil argent-violet et une loupe lavande. Ils partagent les matières brillantes douces et les reflets cyan du hero.

### Prompt RestoreIcon.png

```text
Use case: stylized-concept
Asset type: a single isolated 3D illustration icon for the Restore card in the premium native macOS utility ReScope, matching a silver-violet smartphone hero with a cyan/lavender screen.
Primary request: exactly two thick rounded sculpted arrows forming one complete circular restore cycle. Both rounded arrowheads and the two curved arrow bodies are clearly visible and form one coherent circular symbol.
Style/medium: polished soft 3D utility icon with substantial gentle volume, slightly isometric perspective, premium calm native Mac aesthetic. The arrows look like pearlescent lavender glass with soft violet sculpted depth and restrained cyan highlights, smoothly rounded edges and subtle reflections.
Composition/framing: square canvas; center the whole circular arrow icon; its complete silhouette occupies about 70 percent of both the canvas width and height, leaving 15 percent clear breathing room on every edge. No cropping. One coherent symbol, no extra objects.
Lighting/mood: diffuse studio light, soft glossy surfaces, subtle translucent diffuse shadow which composites beautifully over dark indigo.
Scene/backdrop: genuinely transparent PNG background with real alpha. No floor, no scenery, no solid background, no background rectangle.
Constraints: only the two circular arrows, no letters, no numbers, no text, no logo, no watermark, no device, no interface. This is an icon illustration, never a UI mockup.
```

### Prompt CheckIcon.png

```text
Use case: stylized-concept
Asset type: a single isolated 3D illustration icon for the Check card in the premium native macOS utility ReScope, matching a silver-violet smartphone hero with a cyan/lavender screen and a pearlescent lavender restore icon.
Primary request: one coherent inspection symbol formed by a small upright rounded rectangular smartphone-like device behind a glossy lavender magnifying glass. The small grey-violet device is simple and its dark softly reflective front has a tiny restrained cyan accent; the substantial lavender magnifying glass lens and rounded handle cross in front, clearly expressing inspection.
Style/medium: premium polished soft 3D utility icon with substantial gentle sculpted volume, slightly isometric perspective. Rounded grey-violet metal device, glossy pearlescent lavender glass magnifying lens/frame, very restrained cyan highlights. Calm refined native Mac aesthetic.
Composition/framing: square canvas; center the complete combined phone-and-magnifier icon as one compact object. Its silhouette occupies approximately 70 percent of canvas width and height, leaving 15 percent clear breathing room on every edge; no cropping, no extra objects.
Lighting/mood: diffuse studio lighting, soft reflections and translucent diffuse shadow for compositing over dark indigo.
Scene/backdrop: genuinely transparent PNG background with real alpha. No floor, no scenery, no solid background, no background rectangle.
Constraints: exactly one small device and one magnifying glass combined into one icon, no text, no letters, no numbers, no logo, no Apple mark, no watermark, no UI elements or app screen. This is an icon illustration, never a UI mockup.
```
