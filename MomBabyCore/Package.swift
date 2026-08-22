// swift-tools-version: 6.2

import PackageDescription

let nonisolatedSwiftSettings: [SwiftSetting] = [
    .defaultIsolation(nil),
]

let package = Package(
    name: "MomBabyCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "MediaProcessing", targets: ["MediaProcessing"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/groue/GRDB.swift.git",
            exact: "7.11.1"
        ),
    ],
    targets: [
        .target(
            name: "Domain",
            swiftSettings: nonisolatedSwiftSettings
        ),
        .target(
            name: "Persistence",
            dependencies: [
                "Domain",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            resources: [
                .process("Resources"),
            ],
            swiftSettings: nonisolatedSwiftSettings
        ),
        .target(
            name: "MediaProcessing",
            dependencies: ["Domain"],
            swiftSettings: nonisolatedSwiftSettings
        ),
        .testTarget(
            name: "DomainTests",
            dependencies: ["Domain"],
            swiftSettings: nonisolatedSwiftSettings
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: [
                "Domain",
                "Persistence",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: nonisolatedSwiftSettings
        ),
        .testTarget(
            name: "MediaProcessingTests",
            dependencies: ["Domain", "MediaProcessing"],
            swiftSettings: nonisolatedSwiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
