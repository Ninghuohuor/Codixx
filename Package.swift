// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Codixx",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Codixx", targets: ["CodixxApp"]),
        .library(name: "CodixxCore", targets: ["CodixxCore"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "CodixxApp",
            dependencies: ["CodixxCore"]
        ),
        .target(
            name: "CodixxCore",
            dependencies: []
        ),
        .testTarget(
            name: "CodixxCoreTests",
            dependencies: ["CodixxCore"]
        ),
        .testTarget(
            name: "CodixxCorePublicAPITests",
            dependencies: ["CodixxCore"]
        )
    ]
)
