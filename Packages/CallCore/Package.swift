// swift-tools-version:5.9
import PackageDescription

// CallCore holds everything that doesn't need UIKit, CallKit or AVFoundation:
// the call state machine, the CallManager, domain models and the simulated
// signaling layer. Keeping it Foundation-only means `swift test` can exercise
// the interesting logic without a simulator.
//
// The Xcode project (project.yml) compiles the same sources into an embedded
// CallCore.framework, so there is a single source of truth for both builds.
let package = Package(
    name: "CallCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "CallCore", targets: ["CallCore"])
    ],
    targets: [
        .target(name: "CallCore"),
        .testTarget(name: "CallCoreTests", dependencies: ["CallCore"])
    ]
)
