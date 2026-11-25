// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HealthcheckClaimKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9)
    ],
    products: [
        .library(name: "HealthcheckClaimKit", targets: ["HealthcheckClaimKit"]),
        .executable(name: "HealthcheckClaimDemo", targets: ["HealthcheckClaimDemo"])
    ],
    targets: [
        .target(name: "HealthcheckClaimKit"),
        .executableTarget(name: "HealthcheckClaimDemo", dependencies: ["HealthcheckClaimKit"]),
        .testTarget(name: "HealthcheckClaimKitTests", dependencies: ["HealthcheckClaimKit"])
    ],
    swiftLanguageModes: [.v6]
)
