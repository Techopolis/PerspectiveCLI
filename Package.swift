// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PerspectiveCLI",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "2.30.3"),
    ],
    targets: [
        .executableTarget(
            name: "PerspectiveCLI",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ]
        )
    ]
)
