// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuotaGlass",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "QuotaGlassCore", targets: ["QuotaGlassCore"]),
        .executable(name: "QuotaGlass", targets: ["QuotaGlass"]),
        .executable(name: "QuotaGlassChecks", targets: ["QuotaGlassChecks"])
    ],
    targets: [
        .target(
            name: "QuotaGlassCore"
        ),
        .executableTarget(
            name: "QuotaGlass",
            dependencies: ["QuotaGlassCore"]
        ),
        .executableTarget(
            name: "QuotaGlassChecks",
            dependencies: ["QuotaGlassCore"]
        ),
        .testTarget(
            name: "QuotaGlassCoreTests",
            dependencies: ["QuotaGlassCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [
                .unsafeFlags(["-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"])
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                    "-framework", "Testing"
                ])
            ]
        )
    ]
)
