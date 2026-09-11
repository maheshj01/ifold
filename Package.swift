// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "iFold",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "iFold",
            path: "Sources/iFold",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
    ]
)
