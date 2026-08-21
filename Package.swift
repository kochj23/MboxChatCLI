// swift-tools-version:5.9
//
//  Package.swift
//  MboxChatCLI
//
//  A thin SwiftPM wrapper around the LLM load-balancer sources so the pure,
//  network-free logic (model discovery parsing, pool composition, the load
//  balancer) can be unit-tested with `swift test` in CI without dragging in the
//  Objective-C command-line tool. The same Swift sources are compiled into the
//  Xcode command-line tool target via its file-system-synchronized group.
//
//  The @objc CLI bridge (LLMBridge.swift) is excluded here — it belongs to the
//  Objective-C tool target, not the testable library.
//

import PackageDescription

let package = Package(
    name: "MboxLLM",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "MboxLLM",
            path: "MboxChatCLI/LLM",
            exclude: ["LLMBridge.swift"]
        ),
        .testTarget(
            name: "MboxLLMTests",
            dependencies: ["MboxLLM"],
            path: "MboxLLMTests"
        )
    ]
)
