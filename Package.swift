// swift-tools-version:5.9
//
//  Package.swift
//  MboxChatCLI
//
//  A thin SwiftPM wrapper around the tool's Swift AI layer (MboxChatCLI/LLM) so its NovaAIKit integration
//  (option parsing, the ask feature's prompt/fallback/validator, legacy migration, status report) can be
//  unit-tested with `swift test` — no network, no real Keychain. The same sources are compiled into the Xcode
//  command-line tool target via its file-system-synchronized group.
//

import PackageDescription

let package = Package(
    name: "MboxLLM",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/kochj23/NovaAIKit.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "MboxLLM",
            dependencies: [.product(name: "NovaAIKit", package: "NovaAIKit")],
            path: "MboxChatCLI/LLM"
        ),
        .testTarget(
            name: "MboxLLMTests",
            dependencies: ["MboxLLM", .product(name: "NovaAIKit", package: "NovaAIKit")],
            path: "MboxLLMTests"
        )
    ]
)
