// swift-tools-version:5.9

import PackageDescription

let package = Package(
    name: "TweetNaCl",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v17)
    ],
    products: [
        .library(name: "CTweetNaCl", targets: ["CTweetNaCl"])
    ],
    targets: [
        .target(
            name: "CTweetNaCl",
            // Five narrowing conversions in the Curve25519 and SHA-512 code,
            // which secretbox doesn't use; see VENDOR.md.
            cSettings: [.unsafeFlags(["-Wno-shorten-64-to-32"])]
        )
    ]
)
