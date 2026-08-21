//
//  LLMBackendManager.swift
//  MboxChatCLI
//
//  Ported from AIStudio's LLMBackendManager (Jordan Koch) as a plain, UI-free type
//  so it compiles into a command-line tool. This mirrors the AIStudio
//  balanced-dispatch / health-checked-failover logic verbatim in structure, with
//  the SwiftUI/Combine/@MainActor scaffolding replaced by a plain `LLMConfig`
//  value injected by the CLI (flags / env / config file).
//
//  Copyright © 2026 Jordan Koch. All rights reserved.
//

import Foundation

// MARK: - CLI configuration

/// Plain, Codable configuration for the LLM layer. The CLI populates this from
/// flags, environment variables and/or a JSON config file — there is no settings
/// UI in a command-line tool. Defaults preserve the historical "just Ollama"
/// behavior; the three balancing toggles are opt-in.
struct LLMConfig: Codable, Sendable {
    var ollamaURL: String = ModelRegistry.ollamaBaseURL
    var novaGatewayURL: String = ModelRegistry.novaGatewayDefaultURL
    var openWebUIURL: String = "http://localhost:8080"
    var tinyLLMURL: String = "http://localhost:8000"
    var tinyChatURL: String = "http://localhost:8000"

    var selectedOllamaModel: String = "mistral:latest"
    var selectedOpenRouterModel: String = OpenRouterProvider.defaultModel

    var pythonPath: String = "/opt/homebrew/bin/python3"

    /// LoadBalancer over ALL local models (Ollama `/api/tags` + local MLX).
    var useAllLocalModels: Bool = false
    /// Enable all OpenRouter frontier models in the balancer pool.
    var enableAllFrontierModels: Bool = false
    /// Add the (optional) Nova Gateway to the balancer pool. NEVER required.
    var useNovaGateway: Bool = false

    /// Balancer policy: "leastBusy" (default) or "roundRobin".
    var balancerPolicy: String = "leastBusy"

    /// Active single-backend mode when no balancing toggle is set. "auto" runs the
    /// health-checked failover chain; any other value maps to an `LLMBackendType`.
    var activeBackend: String = LLMBackendType.auto.rawValue

    /// OpenRouter API key supplied out-of-band (e.g. `OPENROUTER_API_KEY`). When
    /// nil, the manager falls back to the macOS Keychain.
    var openRouterAPIKey: String? = nil
}

/// Manages all LLM backends: Ollama, MLX, TinyLLM, TinyChat, OpenWebUI,
/// OpenRouter (frontier) and the optional Nova Gateway. Owns backend
/// configurations, runs health checks, and provides a unified generate interface
/// with load-balanced dispatch and health-checked automatic failover.
///
/// This is the plain, UI-free port of AIStudio's `LLMBackendManager`.
final class LLMBackendManager: @unchecked Sendable {
    var config: LLMConfig

    var backends: [LLMBackendType: LLMBackendConfiguration] = [:]
    var activeLLMBackendType: LLMBackendType = .auto
    var resolvedBackend: LLMBackendType? = nil

    // Ollama-specific
    var ollamaModels: [String] = []
    var selectedOllamaModel: String = "mistral:latest"

    // OpenRouter-specific (API key lives in the Keychain / env, never in config on disk)
    var openRouterModels: [String] = OpenRouterProvider.fallbackModels
    var selectedOpenRouterModel: String = OpenRouterProvider.defaultModel

    /// Ordered preference chain used by the "Automatic" failover mode.
    let failoverChain: [LLMBackendType] = FailoverPlanner.defaultChain

    /// Keychain-backed store for the OpenRouter API key.
    let openRouterKeychain = KeychainStore()

    // MARK: - Multi-model load balancing

    /// The models currently discovered on this machine (all sources, unfiltered).
    var discoveredModels: [DiscoveredModel] = []

    /// Pure, network-free balancer that spreads work across the enabled pool.
    let balancer = LoadBalancer()

    /// Balancer policy (least-busy mirrors how Nova's gateway spreads load).
    var balancerPolicy: BalancerPolicy = .leastBusy

    /// True when any load-balancing toggle is on, so a chat should be dispatched
    /// through the balanced path rather than the single-backend path.
    var isBalancingEnabled: Bool {
        config.useAllLocalModels || config.enableAllFrontierModels || config.useNovaGateway
    }

    private let session: URLSession

    init(config: LLMConfig) {
        self.config = config

        let urlConfig = URLSessionConfiguration.default
        urlConfig.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: urlConfig)

        backends[.ollama] = LLMBackendConfiguration(type: .ollama, url: config.ollamaURL)
        backends[.tinyLLM] = LLMBackendConfiguration(type: .tinyLLM, url: config.tinyLLMURL)
        backends[.tinyChat] = LLMBackendConfiguration(type: .tinyChat, url: config.tinyChatURL)
        backends[.openWebUI] = LLMBackendConfiguration(type: .openWebUI, url: config.openWebUIURL)
        backends[.openRouter] = LLMBackendConfiguration(type: .openRouter, url: OpenRouterProvider.baseURL)
        backends[.mlx] = LLMBackendConfiguration(type: .mlx)
        backends[.novaGateway] = LLMBackendConfiguration(type: .novaGateway, url: config.novaGatewayURL)

        if let savedType = LLMBackendType(rawValue: config.activeBackend) {
            activeLLMBackendType = savedType
        }
        selectedOllamaModel = config.selectedOllamaModel
        selectedOpenRouterModel = config.selectedOpenRouterModel
        balancerPolicy = config.balancerPolicy == "roundRobin" ? .roundRobin : .leastBusy
    }

    // MARK: - OpenRouter API key (env override → Keychain)

    /// Read the OpenRouter API key: explicit override (env) first, then Keychain.
    func openRouterAPIKey() -> String? {
        if let key = config.openRouterAPIKey, !key.isEmpty { return key }
        return openRouterKeychain.get()
    }

    /// True when an OpenRouter key has been configured (env or Keychain).
    var hasOpenRouterKey: Bool {
        if let key = config.openRouterAPIKey, !key.isEmpty { return true }
        return openRouterKeychain.hasValue
    }

    // MARK: - Health Checks

    /// Quick availability probe for a single backend, returning a plain Bool.
    /// Reused by the automatic-failover request path.
    func checkAvailability(_ type: LLMBackendType) async -> Bool {
        switch type {
        case .ollama: return await checkOllama().isConnected
        case .tinyLLM: return await checkTinyLLM().isConnected
        case .tinyChat: return await checkTinyChat().isConnected
        case .openWebUI: return await checkOpenWebUI().isConnected
        case .openRouter: return await checkOpenRouter().isConnected
        case .mlx: return await checkMLX().isConnected
        case .novaGateway: return await checkNovaGateway().isConnected
        case .auto: return false
        }
    }

    // MARK: - Health Check Implementations

    private func checkOllama() async -> BackendStatus {
        guard let url = URL(string: "\(backends[.ollama]?.url ?? "http://localhost:11434")/api/tags") else {
            return .disconnected
        }
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return .disconnected }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let models = json["models"] as? [[String: Any]] {
                let modelNames = models.compactMap { $0["name"] as? String }
                ollamaModels = modelNames
                if !modelNames.isEmpty && !modelNames.contains(selectedOllamaModel) {
                    selectedOllamaModel = modelNames[0]
                }
            }
            return .connected
        } catch {
            return .disconnected
        }
    }

    private func checkTinyLLM() async -> BackendStatus {
        guard let url = URL(string: "\(backends[.tinyLLM]?.url ?? "http://localhost:8000")/v1/models") else {
            return .disconnected
        }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200 ? .connected : .disconnected
        } catch {
            return .disconnected
        }
    }

    private func checkTinyChat() async -> BackendStatus {
        guard let url = URL(string: "\(backends[.tinyChat]?.url ?? "http://localhost:8000")/") else {
            return .disconnected
        }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200 ? .connected : .disconnected
        } catch {
            return .disconnected
        }
    }

    private func checkOpenWebUI() async -> BackendStatus {
        let baseURL = backends[.openWebUI]?.url ?? "http://localhost:8080"
        guard let url = URL(string: "\(baseURL)/") else { return .disconnected }
        do {
            let (_, response) = try await session.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200 ? .connected : .disconnected
        } catch {
            return .disconnected
        }
    }

    private func checkMLX() async -> BackendStatus {
        let pythonPath = config.pythonPath
        guard FileManager.default.fileExists(atPath: pythonPath) else { return .disconnected }

        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: pythonPath)
            process.arguments = ["-c", "import mlx.core as mx; print('OK')"]
            process.standardOutput = Pipe()
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                continuation.resume(returning: process.terminationStatus == 0 ? .connected : .disconnected)
            } catch {
                continuation.resume(returning: .disconnected)
            }
        }
    }

    private func checkOpenRouter() async -> BackendStatus {
        // Availability requires a configured key; verify it with a lightweight
        // models fetch (also refreshes the model picker on success).
        guard let key = openRouterAPIKey(), !key.isEmpty else { return .disconnected }
        guard let url = URL(string: OpenRouterProvider.modelsURL) else { return .disconnected }

        var request = URLRequest(url: url)
        for (header, value) in OpenRouterProvider.authHeaders(apiKey: key) {
            request.setValue(value, forHTTPHeaderField: header)
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return .disconnected }
            let models = OpenRouterProvider.parseModels(data)
            if !models.isEmpty {
                openRouterModels = models
                if !models.contains(selectedOpenRouterModel) {
                    selectedOpenRouterModel = models.contains(OpenRouterProvider.defaultModel)
                        ? OpenRouterProvider.defaultModel : models[0]
                }
            }
            return .connected
        } catch {
            return .disconnected
        }
    }

    /// Nova Gateway health probe. NEVER required: an unreachable gateway simply
    /// reports `.disconnected` and drops out of the pool — no hard dependency.
    private func checkNovaGateway() async -> BackendStatus {
        let baseURL = backends[.novaGateway]?.url ?? ModelRegistry.novaGatewayDefaultURL
        // Probe the OpenAI-compatible models listing; fall back to the base URL.
        let candidates = ["\(baseURL)/v1/models", "\(baseURL)/"].compactMap { URL(string: $0) }
        for url in candidates {
            do {
                let (_, response) = try await session.data(from: url)
                if (response as? HTTPURLResponse)?.statusCode == 200 { return .connected }
            } catch {
                continue
            }
        }
        return .disconnected
    }

    // MARK: - Text Generation

    func generate(
        prompt: String,
        systemPrompt: String? = nil,
        messages: [ChatMessage] = [],
        temperature: Float = 0.7,
        maxTokens: Int = 2048
    ) async throws -> String {
        // Load-balanced mode: when any balancing toggle is on, spread work across
        // the healthy enabled pool. Falls back to the failover path when the pool
        // is empty/unreachable.
        if isBalancingEnabled {
            if let result = try await generateBalanced(prompt: prompt, systemPrompt: systemPrompt, messages: messages, temperature: temperature, maxTokens: maxTokens) {
                return result
            }
        }

        // Automatic mode: live health-check the preference chain and try each
        // healthy backend in order, falling through on failure.
        if activeLLMBackendType == .auto {
            return try await generateWithFailover(prompt: prompt, systemPrompt: systemPrompt, messages: messages, temperature: temperature, maxTokens: maxTokens)
        }

        return try await generate(on: activeLLMBackendType, prompt: prompt, systemPrompt: systemPrompt, messages: messages, temperature: temperature, maxTokens: maxTokens)
    }

    /// Dispatch a non-streaming generation to a specific backend.
    private func generate(
        on backend: LLMBackendType,
        prompt: String,
        systemPrompt: String?,
        messages: [ChatMessage],
        temperature: Float,
        maxTokens: Int
    ) async throws -> String {
        switch backend {
        case .ollama:
            return try await generateWithOllama(prompt: prompt, systemPrompt: systemPrompt, messages: messages, temperature: temperature, maxTokens: maxTokens)
        case .tinyLLM:
            return try await generateWithOpenAICompatible(baseURL: backends[.tinyLLM]?.url ?? "http://localhost:8000", model: selectedOllamaModel, prompt: prompt, systemPrompt: systemPrompt, messages: messages, temperature: temperature, maxTokens: maxTokens)
        case .tinyChat:
            return try await generateWithTinyChat(prompt: prompt, systemPrompt: systemPrompt, messages: messages, temperature: temperature)
        case .openWebUI:
            return try await generateWithOpenAICompatible(baseURL: backends[.openWebUI]?.url ?? "http://localhost:8080", model: selectedOllamaModel, prompt: prompt, systemPrompt: systemPrompt, messages: messages, temperature: temperature, maxTokens: maxTokens)
        case .openRouter:
            return try await generateWithOpenRouter(prompt: prompt, systemPrompt: systemPrompt, messages: messages, temperature: temperature, maxTokens: maxTokens)
        case .mlx:
            return try await generateWithMLX(prompt: prompt, systemPrompt: systemPrompt, maxTokens: maxTokens)
        case .novaGateway:
            return try await generateOpenAICompatible(endpoint: "\(backends[.novaGateway]?.url ?? ModelRegistry.novaGatewayDefaultURL)/v1/chat/completions", model: "nova", headers: [:], prompt: prompt, systemPrompt: systemPrompt, messages: messages, temperature: temperature, maxTokens: maxTokens)
        case .auto:
            throw LLMError.noBackendAvailable
        }
    }

    /// Automatic failover: probe the preference chain, then try each healthy
    /// backend in order. If a request fails mid-flight, fall through to the next
    /// healthy backend and retry.
    private func generateWithFailover(
        prompt: String,
        systemPrompt: String?,
        messages: [ChatMessage],
        temperature: Float,
        maxTokens: Int
    ) async throws -> String {
        var availability: [LLMBackendType: Bool] = [:]
        for backend in failoverChain {
            availability[backend] = await checkAvailability(backend)
        }
        let healthy = FailoverPlanner.orderedHealthy(chain: failoverChain, availability: availability)
        guard !healthy.isEmpty else { throw LLMError.noBackendAvailable }

        var lastError: Error = LLMError.noBackendAvailable
        for backend in healthy {
            do {
                let result = try await generate(on: backend, prompt: prompt, systemPrompt: systemPrompt, messages: messages, temperature: temperature, maxTokens: maxTokens)
                resolvedBackend = backend
                return result
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError
    }

    // MARK: - Multi-model load balancing

    /// Discover the enabled balancer pool honoring the three toggles. Resilient:
    /// any unreachable source contributes zero models.
    func discoverEnabledPool() async -> [DiscoveredModel] {
        let ollamaBase = backends[.ollama]?.url ?? ModelRegistry.ollamaBaseURL
        let novaURL = backends[.novaGateway]?.url ?? config.novaGatewayURL

        var ollama: [DiscoveredModel] = []
        var mlx: [DiscoveredModel] = []
        var frontier: [DiscoveredModel] = []

        if config.useAllLocalModels {
            ollama = await ModelRegistry.discoverOllama(baseURL: ollamaBase, session: session)
            mlx = ModelRegistry.discoverMLX()
        }
        if config.enableAllFrontierModels {
            // Refresh the OpenRouter list when a key is present, else use the
            // popular fallback set.
            await fetchOpenRouterModels()
            frontier = ModelRegistry.frontierModels(from: openRouterModels)
        }
        let nova = config.useNovaGateway ? ModelRegistry.novaGatewayModel(url: novaURL) : nil

        let pool = ModelRegistry.assemblePool(
            ollama: ollama,
            mlx: mlx,
            frontier: frontier,
            novaGateway: nova,
            useAllLocalModels: config.useAllLocalModels,
            enableAllFrontierModels: config.enableAllFrontierModels,
            useNovaGateway: config.useNovaGateway
        )
        discoveredModels = pool
        return pool
    }

    /// Fetch the OpenRouter model list; falls back to the hardcoded popular-models
    /// list if the fetch fails or no key is configured.
    func fetchOpenRouterModels() async {
        guard let key = openRouterAPIKey(), !key.isEmpty,
              let url = URL(string: OpenRouterProvider.modelsURL) else {
            openRouterModels = OpenRouterProvider.fallbackModels
            return
        }
        var request = URLRequest(url: url)
        for (header, value) in OpenRouterProvider.authHeaders(apiKey: key) {
            request.setValue(value, forHTTPHeaderField: header)
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                openRouterModels = OpenRouterProvider.fallbackModels
                return
            }
            let models = OpenRouterProvider.parseModels(data)
            openRouterModels = models.isEmpty ? OpenRouterProvider.fallbackModels : models
        } catch {
            openRouterModels = OpenRouterProvider.fallbackModels
        }
    }

    /// Build a `[modelId: Bool]` health map for `pool` by probing each distinct
    /// backend once (health-gating, composed with `FailoverPlanner` semantics).
    private func healthMap(for pool: [DiscoveredModel]) async -> [String: Bool] {
        var backendHealth: [LLMBackendType: Bool] = [:]
        for backend in Set(pool.map { $0.backend }) {
            backendHealth[backend] = await checkAvailability(backend)
        }
        var map: [String: Bool] = [:]
        for model in pool {
            map[model.id] = backendHealth[model.backend] ?? false
        }
        return map
    }

    /// Balanced dispatch: pick a model via the `LoadBalancer` over the healthy
    /// enabled pool and route it through the existing generic path. Returns nil
    /// when no pool/healthy model exists so the caller can fall back cleanly.
    private func generateBalanced(
        prompt: String,
        systemPrompt: String?,
        messages: [ChatMessage],
        temperature: Float,
        maxTokens: Int
    ) async throws -> String? {
        let pool = await discoverEnabledPool()
        guard !pool.isEmpty else { return nil }

        let health = await healthMap(for: pool)
        var remaining = pool
        var lastError: Error?

        // Try balancer-selected models, falling through on failure.
        while let choice = balancer.next(pool: remaining, health: health, policy: balancerPolicy) {
            balancer.checkOut(choice.id)
            do {
                let result = try await dispatchBalanced(model: choice, prompt: prompt, systemPrompt: systemPrompt, messages: messages, temperature: temperature, maxTokens: maxTokens)
                balancer.checkIn(choice.id)
                resolvedBackend = choice.backend
                return result
            } catch {
                balancer.checkIn(choice.id)
                lastError = error
                remaining.removeAll { $0.id == choice.id }
                continue
            }
        }

        // Nothing healthy in the pool — let the caller fall back to failover.
        if let lastError = lastError { throw lastError }
        return nil
    }

    /// Route a single balancer-selected model through the appropriate backend
    /// implementation (all OpenAI-compatible backends ride the generic path).
    private func dispatchBalanced(
        model: DiscoveredModel,
        prompt: String,
        systemPrompt: String?,
        messages: [ChatMessage],
        temperature: Float,
        maxTokens: Int
    ) async throws -> String {
        switch model.backend {
        case .ollama:
            return try await generateWithOllama(prompt: prompt, systemPrompt: systemPrompt, messages: messages, temperature: temperature, maxTokens: maxTokens, model: model.modelName)
        case .mlx:
            return try await generateWithMLX(prompt: prompt, systemPrompt: systemPrompt, maxTokens: maxTokens)
        case .openRouter:
            guard let key = openRouterAPIKey(), !key.isEmpty else { throw LLMError.noBackendAvailable }
            return try await generateOpenAICompatible(endpoint: model.endpoint, model: model.modelName, headers: OpenRouterProvider.authHeaders(apiKey: key), prompt: prompt, systemPrompt: systemPrompt, messages: messages, temperature: temperature, maxTokens: maxTokens)
        case .novaGateway:
            return try await generateOpenAICompatible(endpoint: model.endpoint, model: model.modelName, headers: [:], prompt: prompt, systemPrompt: systemPrompt, messages: messages, temperature: temperature, maxTokens: maxTokens)
        default:
            return try await generate(on: model.backend, prompt: prompt, systemPrompt: systemPrompt, messages: messages, temperature: temperature, maxTokens: maxTokens)
        }
    }

    // MARK: - Ollama Implementation

    private func generateWithOllama(
        prompt: String,
        systemPrompt: String?,
        messages: [ChatMessage],
        temperature: Float,
        maxTokens: Int,
        model: String? = nil
    ) async throws -> String {
        let baseURL = backends[.ollama]?.url ?? "http://localhost:11434"
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw LLMError.invalidURL
        }

        let apiMessages = buildOllamaMessages(prompt: prompt, systemPrompt: systemPrompt, messages: messages)
        let body: [String: Any] = [
            "model": model ?? selectedOllamaModel,
            "messages": apiMessages,
            "stream": false,
            "options": [
                "temperature": temperature,
                "num_predict": maxTokens
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LLMError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let message = json["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.noResponse
        }
        return content
    }

    private func buildOllamaMessages(prompt: String, systemPrompt: String?, messages: [ChatMessage]) -> [[String: String]] {
        var apiMessages: [[String: String]] = []
        if let system = systemPrompt, !system.isEmpty {
            apiMessages.append(["role": "system", "content": system])
        }
        for msg in messages where msg.role != .system {
            apiMessages.append(["role": msg.role.rawValue, "content": msg.content])
        }
        if messages.last?.role != .user || messages.last?.content != prompt {
            apiMessages.append(["role": "user", "content": prompt])
        }
        return apiMessages
    }

    // MARK: - OpenAI-Compatible Implementation (TinyLLM, OpenWebUI)

    private func generateWithOpenAICompatible(
        baseURL: String,
        model: String,
        prompt: String,
        systemPrompt: String?,
        messages: [ChatMessage],
        temperature: Float,
        maxTokens: Int,
        headers: [String: String] = [:]
    ) async throws -> String {
        try await generateOpenAICompatible(endpoint: "\(baseURL)/v1/chat/completions", model: model, headers: headers, prompt: prompt, systemPrompt: systemPrompt, messages: messages, temperature: temperature, maxTokens: maxTokens)
    }

    /// Non-streaming generation against a full OpenAI-compatible endpoint URL.
    /// Used by the balanced dispatch path, the Nova Gateway backend, TinyLLM and
    /// OpenWebUI.
    private func generateOpenAICompatible(
        endpoint: String,
        model: String,
        headers: [String: String],
        prompt: String,
        systemPrompt: String?,
        messages: [ChatMessage],
        temperature: Float,
        maxTokens: Int
    ) async throws -> String {
        let apiMessages = OpenAICompatibleRequest.chatMessages(prompt: prompt, systemPrompt: systemPrompt, history: messages)

        var request = try OpenAICompatibleRequest.build(
            endpoint: endpoint,
            model: model,
            messages: apiMessages,
            temperature: temperature,
            maxTokens: maxTokens,
            stream: false,
            headers: headers
        )
        request.timeoutInterval = 120

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LLMError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        struct OpenAIResponse: Codable {
            struct Choice: Codable {
                struct Message: Codable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }

        let apiResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
        return apiResponse.choices.first?.message.content ?? ""
    }

    // MARK: - OpenRouter Implementation (frontier models)

    private func generateWithOpenRouter(
        prompt: String,
        systemPrompt: String?,
        messages: [ChatMessage],
        temperature: Float,
        maxTokens: Int
    ) async throws -> String {
        guard let key = openRouterAPIKey(), !key.isEmpty else {
            throw LLMError.noBackendAvailable
        }
        return try await generateOpenAICompatible(
            endpoint: OpenRouterProvider.chatCompletionsURL,
            model: selectedOpenRouterModel,
            headers: OpenRouterProvider.authHeaders(apiKey: key),
            prompt: prompt,
            systemPrompt: systemPrompt,
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens
        )
    }

    // MARK: - TinyChat Implementation

    private func generateWithTinyChat(
        prompt: String,
        systemPrompt: String?,
        messages: [ChatMessage],
        temperature: Float
    ) async throws -> String {
        let baseURL = backends[.tinyChat]?.url ?? "http://localhost:8000"
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw LLMError.invalidURL
        }
        let body: [String: Any] = [
            "message": prompt,
            "model": selectedOllamaModel,
            "temperature": temperature
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LLMError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        if let responseText = String(data: data, encoding: .utf8) {
            let lines = responseText.components(separatedBy: "\n").filter { !$0.isEmpty }
            for line in lines.reversed() {
                if let lineData = line.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                   let content = json["content"] as? String {
                    return content
                }
            }
        }
        throw LLMError.noResponse
    }

    // MARK: - MLX Implementation

    private func generateWithMLX(
        prompt: String,
        systemPrompt: String?,
        maxTokens: Int
    ) async throws -> String {
        let pythonPath = config.pythonPath
        let mlxPath = "/opt/homebrew/bin/mlx_lm.generate"

        guard FileManager.default.fileExists(atPath: mlxPath) || FileManager.default.fileExists(atPath: pythonPath) else {
            throw LLMError.mlxNotAvailable
        }

        var fullPrompt = prompt
        if let system = systemPrompt, !system.isEmpty {
            fullPrompt = "\(system)\n\n\(prompt)"
        }

        let promptFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("mlx_prompt_\(UUID().uuidString).txt")
        try fullPrompt.write(to: promptFile, atomically: true, encoding: .utf8)

        return try await withCheckedThrowingContinuation { continuation in
            defer { try? FileManager.default.removeItem(at: promptFile) }

            let process = Process()
            if FileManager.default.fileExists(atPath: mlxPath) {
                process.executableURL = URL(fileURLWithPath: mlxPath)
                process.arguments = ["--model", "mlx-community/Llama-3.2-3B-Instruct-4bit", "--prompt", fullPrompt, "--max-tokens", "\(maxTokens)"]
            } else {
                process.executableURL = URL(fileURLWithPath: pythonPath)
                process.arguments = ["-c", """
                    from mlx_lm import load, generate
                    with open('\(promptFile.path)', 'r', encoding='utf-8') as f:
                        prompt = f.read()
                    model, tokenizer = load("mlx-community/Llama-3.2-3B-Instruct-4bit")
                    response = generate(model, tokenizer, prompt=prompt, max_tokens=\(maxTokens))
                    print(response)
                    """]
            }

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    continuation.resume(throwing: LLMError.mlxNotAvailable)
                    return
                }
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                guard let output = String(data: data, encoding: .utf8), !output.isEmpty else {
                    continuation.resume(throwing: LLMError.noResponse)
                    return
                }
                continuation.resume(returning: output.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                continuation.resume(throwing: LLMError.mlxNotAvailable)
            }
        }
    }
}

// MARK: - LLM Errors

enum LLMError: LocalizedError, Sendable {
    case noBackendAvailable
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case noResponse
    case mlxNotAvailable

    var errorDescription: String? {
        switch self {
        case .noBackendAvailable:
            return "No LLM backend is available. Start Ollama (or set OPENROUTER_API_KEY / --nova-gateway)."
        case .invalidURL:
            return "Invalid backend URL configuration."
        case .invalidResponse:
            return "Received invalid response from LLM backend."
        case .httpError(let code):
            return "HTTP error \(code) from LLM backend."
        case .noResponse:
            return "No response received from LLM backend."
        case .mlxNotAvailable:
            return "MLX not available. Install: pip install mlx-lm"
        }
    }
}
