// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift_qrcodejs",
    platforms: [
        .macOS(.v10_13),
        .iOS(.v12),
        .tvOS(.v12),
        .watchOS(.v6)
    ],
    products: [
        .library(name: "QRCodeSwift", targets: ["QRCodeSwift"])
    ],
    targets: [
        .target(
            name: "QRCodeSwift",
            path: "Sources",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "QRCodeSwiftTests",
            dependencies: ["QRCodeSwift"],
            path: "Tests/QRCodeSwiftTests",
            exclude: ["Info.plist"]
        )
    ],
    swiftLanguageVersions: [.v5]
)
