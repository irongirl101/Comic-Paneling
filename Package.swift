// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ComicPanelReader",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ComicPanelReader", targets: ["ComicPanelReader"])
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19")
    ],
    targets: [
        .executableTarget(
            name: "ComicPanelReader",
            dependencies: [
                .product(name: "ZIPFoundation", package: "ZIPFoundation")
            ],
            path: "Sources",
            resources: [
                .copy("Resources")
            ]
        )
    ]
)
