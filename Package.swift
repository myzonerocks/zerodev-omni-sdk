// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ZeroDevAA",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "ZeroDevAA", targets: ["ZeroDevAA"]),
    ],
    targets: [
        .binaryTarget(
            name: "CZeroDevAA",
            url: "https://github.com/zerodevapp/zerodev-omni-sdk/releases/download/v0.0.1-alpha.3/ZeroDevAA.xcframework.zip",
            checksum: "d14d462dc11a5d8091d5b993904c407e9617e7ec6fb003b34fac39ff60d2e6a9"
        ),
        .target(
            name: "ZeroDevAA",
            dependencies: ["CZeroDevAA"],
            path: "bindings/swift/Sources/ZeroDevAA"
        ),
    ]
)
