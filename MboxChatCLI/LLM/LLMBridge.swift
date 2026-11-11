//
//  LLMBridge.swift
//  MboxChatCLI
//
//  The command-line surface for the tool's AI (NovaAIKit), called from the Objective-C `main.m`.
//  A CLI has no settings window, so the NovaAIKit settings (AI on/off, backend, models, URLs, timeout, keys) are
//  driven by flags; `--save` keeps them. Keys go only into the Keychain (`--set-key`, read from stdin).
//
//  Copyright © 2026 Jordan Koch. All rights reserved.
//

import Foundation
import NovaAIKit

@objc(LLMBridge)
@MainActor
public final class LLMBridge: NSObject {

    /// True when `args` ask for an AI action, so `main.m` hands off here instead of starting the MBOX REPL.
    @objc public static func isLLMInvocation(_ args: [String]) -> Bool {
        MboxAIOptions.isAIInvocation(args)
    }

    /// Non-interactive entry point. Returns the process exit code.
    @discardableResult
    @objc public static func run(_ args: [String]) -> Int32 {
        let options: MboxAIOptions
        do {
            options = try MboxAIOptions.parse(Array(args.dropFirst()), environment: ProcessInfo.processInfo.environment)
        } catch {
            printError((error as? LocalizedError)?.errorDescription ?? "\(error)")
            return 2
        }
        options.notices.forEach { printError("note: \($0)") }

        if options.help { printUsage(); return 0 }
        if options.version { print("MboxChatCLI \(MboxChatCLIVersion.current)"); return 0 }

        let shared = AppAI.shared
        if let b = options.clearKey {
            guard b.acceptsKey else { printError("\(b.displayName) takes no API key."); return 2 }
            shared.setAPIKey(nil, for: b)
            print("\(b.displayName) key removed from the Keychain.")
        }
        if let b = options.setKey {
            guard b.acceptsKey else { printError("\(b.displayName) takes no API key."); return 2 }
            guard let key = readSecretLine(prompt: "\(b.displayName) API key (input hidden): "), !key.isEmpty else {
                printError("No key entered; nothing stored.")
                return 2
            }
            guard shared.setAPIKey(key, for: b) else { printError("Could not store the key in the Keychain."); return 1 }
            print("\(b.displayName) key stored in the Keychain (\(AppAI.configuration.keychainService(for: b))).")
        }

        let ai: NovaAI
        if options.save {
            shared.settings = options.applied(to: shared.settings)
            ai = shared
            if options.changesSettings { print("AI settings saved.") }
        } else {
            ai = options.changesSettings ? AppAI.transient(options.applied(to: shared.settings)) : shared
        }

        if options.listModels {
            let b = ai.settings.backend == .auto ? NovaAIBackend.ollama : ai.settings.backend
            let models = waitFor { await ai.listModels(for: b) }
            print("\(b.displayName) models:")
            (models.isEmpty ? ["(none found)"] : models).forEach { print("  \($0)") }
        }

        if options.status {
            waitFor { await ai.refreshStatus() }
            MboxAIStatusReport.lines(ai).forEach { print($0) }
        }

        if let question = options.ask {
            return ask(question, system: options.system, emails: [], ai: ai)
        }

        let didSomething = options.status || options.listModels || options.setKey != nil || options.clearKey != nil
            || (options.save && options.changesSettings)
        if !didSomething {
            waitFor { await ai.refreshStatus() }
            MboxAIStatusReport.lines(ai).forEach { print($0) }
            printError("\nNo prompt given. Use --ask \"your question\" to run a generation.")
        }
        return 0
    }

    /// The REPL's `ask` command: the question is answered from the loaded emails
    /// (dictionaries with from/subject/date/body).
    @discardableResult
    @objc public static func ask(_ question: String, emails: [[String: String]]) -> Int32 {
        ask(question, system: nil, emails: emails.map(MboxEmail.init(dictionary:)), ai: AppAI.shared)
    }

    // MARK: - Actions

    private static func ask(_ question: String, system: String?, emails: [MboxEmail], ai: NovaAI) -> Int32 {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { printError("Usage: ask <question>"); return 2 }
        let result = waitFor { await MboxAsk.answer(q, system: system, emails: emails, totalLoaded: emails.count, ai: ai) }
        printError("[\(result.source.label)]")
        print(result.value)
        return 0
    }

    // MARK: - Usage

    private static func printUsage() {
        print("""
        MboxChatCLI \(MboxChatCLIVersion.current) — MBOX explorer with optional AI (NovaAIKit)

        USAGE:
          MboxChatCLI [file.mbox ...]                 Interactive REPL (from/subject/count/write/export/summarize/ask)
          MboxChatCLI [settings] --ask "question"     One answer, then exit
          MboxChatCLI [settings] --ai-status          AI status: backend, reachability, keys (stored or not)

        SETTINGS (this run only; add --save to keep them):
          --ai on|off            AI on/off. Off = built-in keyword search, nothing leaves this Mac
          --no-ai                Same as --ai off
          --backend B            auto | ollama | mlx | tinyllm | tinychat | openwebui | novagateway | openrouter | openai
                                 auto fails over local first: \(NovaAIBackend.autoOrder.map(\.rawValue).joined(separator: " → "))
          --model M              Model for the chosen backend (Ollama when auto)
          --url B=URL            Base URL for backend B (e.g. --url ollama=http://localhost:11434)
          --timeout SECONDS      Per-request timeout (2–600)
          --save                 Persist the settings above

        KEYS (macOS Keychain only, service com.jkoch.mboxchatcli.<backend>; https-only for keyed backends):
          --set-key B            Read B's API key from stdin (hidden) and store it
          --clear-key B          Remove B's key

        OTHER:
          --system "text"        System prompt for --ask
          --list-models          Models the chosen backend offers
          --version              Print the version
          --ai-help              This help

        ENVIRONMENT (non-secret overrides): OLLAMA_URL, NOVA_GATEWAY_URL, MBOX_AI_BACKEND.
        Keys are never read from the environment.

        Pre-1.1 flags still work: --all-local (= --backend auto), --frontier (= openrouter),
        --nova-gateway (= novagateway), --ollama-url, --nova-url, --ollama-model, --openrouter-model,
        --llm-status, --llm-help. --policy and --llm-config are ignored.
        """)
    }

    // MARK: - Helpers

    private static func printError(_ s: String) {
        FileHandle.standardError.write(Data((s + "\n").utf8))
    }

    /// Reads one line from stdin with echo off when stdin is a terminal. The value is never printed or logged.
    private static func readSecretLine(prompt: String) -> String? {
        let tty = isatty(STDIN_FILENO) == 1
        var saved = termios()
        if tty {
            FileHandle.standardError.write(Data(prompt.utf8))
            tcgetattr(STDIN_FILENO, &saved)
            var noEcho = saved
            noEcho.c_lflag &= ~tcflag_t(ECHO)
            tcsetattr(STDIN_FILENO, TCSANOW, &noEcho)
        }
        let line = readLine(strippingNewline: true)
        if tty {
            tcsetattr(STDIN_FILENO, TCSANOW, &saved)
            FileHandle.standardError.write(Data("\n".utf8))
        }
        return line?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs async main-actor work from this synchronous entry point by spinning the main run loop
    /// (a semaphore would deadlock: the work needs the main thread).
    private static func waitFor<T>(_ operation: @escaping @MainActor () async -> T) -> T {
        var result: T?
        Task { @MainActor in result = await operation() }
        while result == nil {
            _ = RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        return result!
    }
}
