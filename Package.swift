// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AppleRemindersMCP",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", .upToNextMinor(from: "0.11.0"))
    ],
    targets: [
        .executableTarget(
            name: "AppleRemindersMCP",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "Sources/AppleRemindersMCP",
            exclude: ["Info.plist"],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/AppleRemindersMCP/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "AppleRemindersMCPTests",
            dependencies: ["AppleRemindersMCP"],
            path: "Tests/AppleRemindersMCPTests"
        )
    ]
)
