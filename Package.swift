// swift-tools-version: 5.9
import PackageDescription
import Foundation

let hasSharedFramework = FileManager.default.fileExists(
    atPath: "shared/build/XCFrameworks/release/SharedPaneling.xcframework"
)

var appDependencies: [Target.Dependency] = [
    .product(name: "ZIPFoundation", package: "ZIPFoundation")
]

var targets: [Target] = []

if hasSharedFramework {
    appDependencies.append("SharedPaneling")
    targets.append(
        .binaryTarget(
            name: "SharedPaneling",
            path: "shared/build/XCFrameworks/release/SharedPaneling.xcframework"
        )
    )
}

targets.append(
    .executableTarget(
        name: "Panels",
        dependencies: appDependencies,
        path: "Sources",
        resources: [
            .copy("Resources")
        ]
    )
)

let package = Package(
    name: "Panels",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Panels", targets: ["Panels"])
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19")
    ],
    targets: targets
)
