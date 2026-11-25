// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SpanningTheStars",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "StarsCore", targets: ["StarsCore"]),
        .executable(name: "SpanningTheStars", targets: ["SpanningTheStars"]),
    ],
    targets: [
        .target(name: "StarsCore"),
        .executableTarget(
            name: "SpanningTheStars",
            dependencies: ["StarsCore"],
            resources: [.copy("Resources/Art"), .copy("Resources/RULES.md"), .copy("Resources/AppIcon.svg")]
        ),
        .executableTarget(name: "Tournament", dependencies: ["StarsCore"]),
        .testTarget(name: "StarsCoreTests", dependencies: ["StarsCore"]),
        .testTarget(name: "SpanningTheStarsTests", dependencies: ["SpanningTheStars", "StarsCore"]),
    ],
    swiftLanguageModes: [.v6]
)
