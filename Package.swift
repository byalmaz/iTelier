// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReScope",
    defaultLocalization: "fr",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ReScopeCore", targets: ["ReScopeCore"]),
        .executable(name: "iTelier", targets: ["ReScope"]),
        .executable(name: "ReScopeRestoreHost", targets: ["ReScopeRestoreHost"]),
        .executable(name: "ReScopeWallpaperHost", targets: ["ReScopeWallpaperHost"])
    ],
    targets: [
        .target(name: "ReScopeCore"),
        .executableTarget(name: "ReScope", dependencies: ["ReScopeCore"], exclude: ["Resources/CheckIcon.png", "Resources/RestoreIcon.png", "Resources/DeviceHero.png"], resources: [.process("Resources")]),
        .executableTarget(name: "ReScopeRestoreHost", dependencies: ["ReScopeCore"]),
        .executableTarget(name: "ReScopeWallpaperHost"),
        .testTarget(name: "ReScopeCoreTests", dependencies: ["ReScopeCore"])
    ],
    swiftLanguageModes: [.v5]
)
