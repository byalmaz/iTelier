// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "iTelier",
    defaultLocalization: "fr",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "iTelierCore", targets: ["iTelierCore"]),
        .executable(name: "iTelier", targets: ["iTelier"]),
        .executable(name: "iTelierRestoreHost", targets: ["iTelierRestoreHost"]),
        .executable(name: "iTelierWallpaperHost", targets: ["iTelierWallpaperHost"])
    ],
    targets: [
        .target(name: "iTelierCore"),
        .executableTarget(name: "iTelier", dependencies: ["iTelierCore"], exclude: ["Resources/CheckIcon.png", "Resources/RestoreIcon.png", "Resources/DeviceHero.png"], resources: [.process("Resources")]),
        .executableTarget(name: "iTelierRestoreHost", dependencies: ["iTelierCore"]),
        .executableTarget(name: "iTelierWallpaperHost"),
        .testTarget(name: "iTelierCoreTests", dependencies: ["iTelierCore"])
    ],
    swiftLanguageModes: [.v5]
)
