// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CoreGlance",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "CoreGlance",
            path: "Sources/CoreGlance",
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("AppKit"), .linkedFramework("ServiceManagement")]
        )
    ]
)
