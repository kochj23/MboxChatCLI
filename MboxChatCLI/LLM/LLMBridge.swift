//
//  LLMBridge.swift
//  MboxChatCLI
//
//  The command-line surface for the multi-model LLM load balancer. A CLI has no
//  settings UI, so the three balancing modes are exposed through flags, a JSON
//  config file, and environment variables instead. This @objc bridge is called
//  from the Objective-C `main.m` entry point.
//
//  Modes (composable — any combination is valid):
//    --all-local      LoadBalancer over ALL local models (Ollama /api/tags + MLX)
//    --frontier       All OpenRouter frontier models (needs OPENROUTER_API_KEY or Keychain)
//    --nova-gateway   Add the OPTIONAL Nova Gateway (127.0.0.1:18792). NEVER required.
//
//  With no mode flag the historical single-backend behavior is kept (auto/Ollama).
//
//  Copyright © 2026 Jordan Koch. All rights reserved.
//

import Foundation

@objc(LLMBridge)
public final class LLMBridge: NSObject {

    /// True when `args` request an LLM action, so `main.m` should hand off to the
    /// bridge instead of running the interactive MBOX REPL.
    @objc public static func isLLMInvocation(_ args: [String]) -> Bool {
        let triggers: Set<String> = ["--all-local", "--frontier", "--nova-gateway", "--llm-status", "--llm-help", "--ask"]
        return args.contains { triggers.contains($0) }
    }

    /// Entry point: resolve config (defaults → file → env → flags), then run the
    /// requested action. Returns a process exit code.
    @objc public static func run(_ args: [String]) -> Int32 {
        if args.contains("--llm-help") {
            printUsage()
            return 0
        }

        var config = LLMConfig()
        var systemPrompt: String? = nil
        var askPrompt: String? = nil
        var wantStatus = false

        // 1. Config file (flag --llm-config, else env MBOX_LLM_CONFIG).
        let env = ProcessInfo.processInfo.environment
        let configPath = value(after: "--llm-config", in: args) ?? env["MBOX_LLM_CONFIG"]
        if let path = configPath, let loaded = loadConfig(path: path) {
            config = loaded
        }

        // 2. Environment.
        if let v = env["OLLAMA_URL"], !v.isEmpty { config.ollamaURL = v }
        if let v = env["NOVA_GATEWAY_URL"], !v.isEmpty { config.novaGatewayURL = v }
        if let v = env["OPENROUTER_API_KEY"], !v.isEmpty { config.openRouterAPIKey = v }
        if isTruthy(env["MBOX_LLM_ALL_LOCAL"]) { config.useAllLocalModels = true }
        if isTruthy(env["MBOX_LLM_FRONTIER"]) { config.enableAllFrontierModels = true }
        if isTruthy(env["MBOX_LLM_NOVA"]) { config.useNovaGateway = true }

        // 3. Flags (highest precedence).
        var i = 0
        while i < args.count {
            let arg = args[i]
            switch arg {
            case "--all-local": config.useAllLocalModels = true
            case "--frontier": config.enableAllFrontierModels = true
            case "--nova-gateway": config.useNovaGateway = true
            case "--llm-status": wantStatus = true
            case "--policy":
                if let v = next(&i, args) { config.balancerPolicy = v }
            case "--ollama-url":
                if let v = next(&i, args) { config.ollamaURL = v }
            case "--nova-url":
                if let v = next(&i, args) { config.novaGatewayURL = v }
            case "--ollama-model":
                if let v = next(&i, args) { config.selectedOllamaModel = v }
            case "--openrouter-model":
                if let v = next(&i, args) { config.selectedOpenRouterModel = v }
            case "--system":
                if let v = next(&i, args) { systemPrompt = v }
            case "--ask":
                if let v = next(&i, args) { askPrompt = v }
            case "--llm-config":
                _ = next(&i, args) // already consumed above
            default:
                break
            }
            i += 1
        }

        let manager = LLMBackendManager(config: config)

        if wantStatus {
            return runStatus(manager: manager, config: config)
        }

        guard let prompt = askPrompt, !prompt.isEmpty else {
            // A mode was selected but nothing to do — show status so the user sees
            // the resolved pool, then explain how to ask a question.
            _ = runStatus(manager: manager, config: config)
            FileHandle.standardError.write(Data("\nNo prompt given. Use --ask \"your question\" to run a generation.\n".utf8))
            return 0
        }

        return runAsk(manager: manager, prompt: prompt, systemPrompt: systemPrompt)
    }

    // MARK: - Actions

    private static func runStatus(manager: LLMBackendManager, config: LLMConfig) -> Int32 {
        print("MboxChatCLI — LLM backend status")
        print("  mode: all-local=\(config.useAllLocalModels)  frontier=\(config.enableAllFrontierModels)  nova-gateway=\(config.useNovaGateway)")
        print("  balancer policy: \(manager.balancerPolicy)")
        print("  ollama:  \(config.ollamaURL)")
        print("  nova:    \(config.novaGatewayURL) (optional — never required)")
        print("  openrouter key: \(manager.hasOpenRouterKey ? "present" : "absent")")

        let pool = waitFor { await manager.discoverEnabledPool() }
        if pool.isEmpty {
            print("  balancer pool: (empty — no balancing toggle set, or no models discovered)")
        } else {
            print("  balancer pool (\(pool.count) model(s)):")
            for m in pool {
                print("    - [\(m.backend.rawValue)] \(m.displayName)")
            }
        }
        return 0
    }

    private static func runAsk(manager: LLMBackendManager, prompt: String, systemPrompt: String?) -> Int32 {
        do {
            let answer = try waitForThrowing {
                try await manager.generate(prompt: prompt, systemPrompt: systemPrompt)
            }
            print(answer)
            return 0
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            FileHandle.standardError.write(Data("LLM error: \(message)\n".utf8))
            return 1
        }
    }

    // MARK: - Usage

    private static func printUsage() {
        let usage = """
        MboxChatCLI — multi-model LLM load balancer

        USAGE:
          MboxChatCLI [--all-local] [--frontier] [--nova-gateway] [options] --ask "prompt"
          MboxChatCLI --llm-status [modes...]

        MODES (composable; default = single-backend auto/Ollama):
          --all-local          Balance across ALL local models (Ollama + MLX)
          --frontier           Add all OpenRouter frontier models
          --nova-gateway       Add the OPTIONAL Nova Gateway (never required)

        ACTIONS:
          --ask "prompt"       Run one generation and print the answer
          --llm-status         Print resolved backends and the balancer pool
          --llm-help           Show this help

        OPTIONS:
          --system "text"      System prompt
          --policy P           Balancer policy: leastBusy (default) | roundRobin
          --ollama-url URL     Override Ollama base URL
          --nova-url URL       Override Nova Gateway base URL
          --ollama-model M     Ollama model name (single-backend mode)
          --openrouter-model M OpenRouter model id (single-backend frontier)
          --llm-config PATH    Load an LLMConfig JSON file

        ENVIRONMENT:
          OPENROUTER_API_KEY   OpenRouter key (else the macOS Keychain is used)
          OLLAMA_URL           Ollama base URL
          NOVA_GATEWAY_URL     Nova Gateway base URL
          MBOX_LLM_ALL_LOCAL   Truthy → --all-local
          MBOX_LLM_FRONTIER    Truthy → --frontier
          MBOX_LLM_NOVA        Truthy → --nova-gateway
          MBOX_LLM_CONFIG      Path to an LLMConfig JSON file

        Note: Nova Gateway is entirely optional. If its health check fails it is
        simply dropped from the pool — the tool never hard-depends on Nova.
        """
        print(usage)
    }

    // MARK: - Arg / config helpers

    private static func next(_ i: inout Int, _ args: [String]) -> String? {
        guard i + 1 < args.count else { return nil }
        i += 1
        return args[i]
    }

    private static func value(after flag: String, in args: [String]) -> String? {
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    private static func isTruthy(_ s: String?) -> Bool {
        guard let s = s?.lowercased() else { return false }
        return ["1", "true", "yes", "on"].contains(s)
    }

    private static func loadConfig(path: String) -> LLMConfig? {
        let expanded = (path as NSString).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: expanded) else {
            FileHandle.standardError.write(Data("Could not read config file: \(expanded)\n".utf8))
            return nil
        }
        do {
            return try JSONDecoder().decode(LLMConfig.self, from: data)
        } catch {
            FileHandle.standardError.write(Data("Invalid config JSON (\(expanded)): \(error)\n".utf8))
            return nil
        }
    }

    // MARK: - Sync bridge over async work (CLI is synchronous)

    private static func waitFor<T>(_ operation: @escaping () async -> T) -> T {
        let semaphore = DispatchSemaphore(value: 0)
        // Using an unchecked box keeps this Swift-5-mode friendly.
        let box = MutableBox<T>()
        Task {
            box.value = await operation()
            semaphore.signal()
        }
        semaphore.wait()
        return box.value!
    }

    private static func waitForThrowing<T>(_ operation: @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = MutableBox<Result<T, Error>>()
        Task {
            do { box.value = .success(try await operation()) }
            catch { box.value = .failure(error) }
            semaphore.signal()
        }
        semaphore.wait()
        return try box.value!.get()
    }
}

/// A minimal mutable, unchecked-Sendable box used to ferry an async result back
/// across a `DispatchSemaphore` boundary (the CLI entry point is synchronous).
private final class MutableBox<U>: @unchecked Sendable {
    var value: U?
    init() {}
}
