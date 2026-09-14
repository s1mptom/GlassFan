// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GlassFan",
    platforms: [.macOS("26.0")],
    products: [
        // Declared as a product so Xcode generates a scheme for it, which is what
        // lets the interface previews build without dragging the executable in.
        .library(name: "GlassFanUI", targets: ["GlassFanUI"]),
        .executable(name: "GlassFan", targets: ["GlassFan"]),
        .executable(name: "fanctld", targets: ["fanctld"]),
    ],
    targets: [
        // Thin, policy-free access to the SMC. The only target that talks to hardware.
        .target(name: "CSMC", linkerSettings: [.linkedFramework("IOKit")]),

        // Pure logic: curves, aggregation, config, wire protocol. No I/O, fully testable.
        .target(name: "FanKit"),

        // Privileged daemon: owns the control loop and the socket server.
        .executableTarget(name: "fanctld", dependencies: ["CSMC", "FanKit"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),

        // The interface. A library rather than part of the executable, because Xcode
        // will not render SwiftUI previews inside an executable target.
        .target(name: "GlassFanUI", dependencies: ["FanKit"],
                // The glass lens shader. Needs the Metal toolchain to build
                // (xcodebuild -downloadComponent MetalToolchain).
                resources: [.process("Shaders")],
                swiftSettings: [.swiftLanguageMode(.v5)]),

        // Unprivileged SwiftUI app: an entry point and nothing else.
        .executableTarget(name: "GlassFan", dependencies: ["GlassFanUI"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),

        .testTarget(name: "FanKitTests", dependencies: ["FanKit"]),

        .testTarget(name: "GlassFanUITests", dependencies: ["GlassFanUI"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
