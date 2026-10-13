// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DashMeshView",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .iOSApplication(
            name: "DashMeshView",
            targets: ["AppModule"],
            bundleIdentifier: "com.meshview.dashmeshview",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .video),
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [
                .phone,
                .pad
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft
            ],
            capabilities: [
                .outgoingNetworkConnections()
            ]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/kingslay/KSPlayer.git", exact: "2.3.4")
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            dependencies: [
                .product(name: "KSPlayer", package: "KSPlayer")
            ],
            path: "Sources"
        )
    ]
)
