---
name: rescope-glass-ui
description: Maintenir le style SwiftUI en verre validé de ReScope, ou le réutiliser quand l’utilisateur demande ce style pour une autre interface. Icônes droites à reflets irisés et menu gris qui se colore au survol. Ne pas imposer ce thème à des projets sans lien avec cette demande.
---

# UI en verre ReScope

Ce style a été validé par l’utilisateur le 1er octobre 2026. Conserver ses choix lors des retouches, sauf nouvelle demande explicite.

## Signature visuelle

- Fond indigo sombre, cartes translucides arrondies, texte blanc et secondaire lavande, accents cyan/violet/menthe, actions principales jaunes.
- Icônes sous forme de tuiles de verre aux coins arrondis continus : tranche irisée, reflets doux, symbole blanc net et léger relief. Toutes les tailles sont **droites, vues de face**, sans rotation 2D ni perspective latérale. Le reflet interne peut être diagonal.
- Garder des silhouettes simples et cohérentes. Utiliser des SF Symbols natifs dans SwiftUI, avec une taille de symbole proche de 51 % du côté de la tuile et un rayon proche de 25,5 %.
- Pour les icônes internes à l’app, privilégier le dessin vectoriel natif. Préserver le style des actions compactes Copier, Fermer, Actualiser et des badges : elles restent simples, sans grosse tuile décorative.
- Ne pas ajouter de chevrons décoratifs en fin des lignes du Check. Les détails restent accessibles par un vrai bouton avec libellé d’accessibilité. Les chevrons fonctionnels des menus et sections dépliables restent pertinents.

## Menu latéral

- Icônes de navigation et Configuration **grises au repos**, sauf celle de la page sélectionnée qui reste colorée.
- Colorer l’icône au survol du bouton entier ; revenir au gris lorsque le pointeur quitte un bouton non sélectionné. La sélection conserve son icône colorée, son fond et son texte distinctifs, indépendamment du survol.
- Couleurs ReScope : violet pour Vue d’ensemble, Restaurer et Configuration ; cyan pour Vérification ; menthe pour Activité.
- Désaturer tout le rendu, y compris la tranche et les ombres (`compositingGroup` puis `saturation`), pour éviter des liserés colorés au repos.
- Transition discrète d’environ 180 ms. Respecter Réduire les animations ; conserver un symbole lisible et une navigation utilisable au clavier sans dépendre de la couleur.
- Le logo et les illustrations des cartes gardent leur couleur : ce comportement concerne les boutons du menu.

## Réutilisation et vérification

Dans ReScope, modifier le composant partagé `GlassIcon` de `Sources/ReScope/DesignSystem.swift` et les états de survol de `WorkspaceView.swift`. Ne pas créer un deuxième composant concurrent.

Pour réutiliser le style ailleurs, partir de [assets/GlassIcon.swift](assets/GlassIcon.swift), composant SwiftUI autonome avec sa palette de référence. Adapter les noms à l’architecture du projet ; cet exemple n’impose pas SwiftUI à une application web. Les proportions, matières et interactions constituent la référence visuelle.

Préserver les adaptations Réduire la transparence et Augmenter le contraste du composant. Après compilation, inspecter au moins une icône de carte et le menu : gris au repos, couleur au survol, retour au gris pour une rubrique non sélectionnée. Vérifier aussi qu’une page sélectionnée garde un repère visible. Une retouche visuelle seule ne nécessite pas de relancer des tests de restauration sur un appareil.
