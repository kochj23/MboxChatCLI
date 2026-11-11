//
//  AppAI.swift
//  MboxChatCLI
//
//  The tool's one AI object (NovaAIKit). Settings persist in UserDefaults (no secrets); keys live only in the
//  Keychain under com.jkoch.mboxchatcli.<backend>.
//
//  Copyright © 2026 Jordan Koch. All rights reserved.
//

import Foundation
import NovaAIKit

@MainActor
enum AppAI {
    nonisolated static let appID = "mboxchatcli"
    nonisolated static let appName = "MboxChatCLI"

    nonisolated static let configuration = NovaAIConfiguration(appID: appID, appName: appName)

    /// The persistent instance: settings changes made through it are saved.
    static let shared: NovaAI = {
        let ai = NovaAI(configuration: configuration)
        migrateLegacy(ai)
        return ai
    }()

    /// A throwaway instance for one invocation: starts from the saved settings plus `overrides`, saves nothing.
    /// Keys still come from the Keychain.
    static func transient(_ settings: NovaAISettings) -> NovaAI {
        NovaAI(configuration: configuration, storage: NovaAIMemoryStorage(settings))
    }
}

extension AppAI {
    /// The old balancer read the OpenRouter key from AIStudio's Keychain item (and from `OPENROUTER_API_KEY`).
    nonisolated static let legacyOpenRouterService = "com.jkoch.aistudio.openrouter"

    /// Set once the OpenRouter key copy has run (so the old item is read only once).
    nonisolated static let keyMigrationMarker = "MboxChatCLI.legacyOpenRouterKeyMigrated"

    /// Once, at first launch: import the old shared AI-backend defaults (moving any plaintext OpenAI key into the
    /// Keychain and deleting obsolete Google/Azure/AWS/IBM secrets), then copy the shared OpenRouter key.

    static func migrateLegacy(_ ai: NovaAI, defaults: UserDefaults = .standard) {
        ai.migrateFromLegacyAIBackendManager(defaults: defaults)
        guard !defaults.bool(forKey: keyMigrationMarker) else { return }
        // AIStudio still owns this item: copy it, never delete it.
        let result = ai.migrateLegacyKey(service: legacyOpenRouterService, account: NovaAIConfiguration.keychainAccount,
                                         to: .openRouter, deleteLegacy: false)
        if result != .writeFailed { defaults.set(true, forKey: keyMigrationMarker) }
    }
}
