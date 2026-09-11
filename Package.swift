// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacFans",
    platforms: [.macOS("26.0")],
    targets: [
        // Thin, policy-free access to the SMC. The only target that talks to hardware.
        .target(name: "CSMC", linkerSettings: [.linkedFramework("IOKit")]),

        // Pure logic: curves, aggregation, config, wire protocol. No I/O, fully testable.
        .target(name: "FanKit"),

        // Privileged daemon: owns the control loop and the socket server.
        .executableTarget(name: "fanctld", dependencies: ["CSMC", "FanKit"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),

        // Unprivileged SwiftUI app.
        .executableTarget(name: "MacFans", dependencies: ["FanKit"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),

        .testTarget(name: "FanKitTests", dependencies: ["FanKit"]),
    ]
)
