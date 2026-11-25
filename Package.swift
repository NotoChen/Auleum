// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Auleum",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "auleumd", targets: ["auleumd"]),
        .executable(name: "auleumctl", targets: ["auleumctl"]),
        .library(name: "AuleumKit", targets: ["AuleumKit"]),
    ],
    targets: [
        .target(
            name: "AuleumKit",
            linkerSettings: [
                .linkedFramework("LocalAuthenticationEmbeddedUI"),
            ]
        ),
        .executableTarget(name: "auleumd", dependencies: ["AuleumKit"]),
        .executableTarget(name: "auleumctl", dependencies: ["AuleumKit"]),
        .testTarget(name: "AuleumKitTests", dependencies: ["AuleumKit"]),
    ],
    swiftLanguageVersions: [.v5]
)
