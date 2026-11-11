//
//  MboxAI.swift
//  MboxChatCLI
//
//  The tool's AI features on top of NovaAIKit, kept free of I/O so they can be unit-tested:
//    - command-line options → NovaAI settings (a CLI has no settings window);
//    - "ask": a question about the loaded mailbox, answered by AI with the most relevant emails as context,
//      validated, and answered by a built-in keyword search when AI is off or unreachable;
//    - the status report (the CLI's status indicator).
//
//  Copyright © 2026 Jordan Koch. All rights reserved.
//

import Foundation
import NovaAIKit

/// The tool's version (printed by `--version`).
enum MboxChatCLIVersion {
    static let current = "1.1.0"
}

// MARK: - Options

/// Everything the AI-related flags and environment variables ask for.
struct MboxAIOptions: Equatable {
    var ask: String?
    var system: String?
    var status = false
    var help = false
    var version = false
    var listModels = false
    /// Persist the setting overrides (`--save`); otherwise they apply to this run only.
    var save = false
    var enabled: Bool?
    var backend: NovaAIBackend?
    /// `--model` (applies to the chosen backend; Ollama when Auto).
    var model: String?
    var models: [NovaAIBackend: String] = [:]
    var urls: [NovaAIBackend: String] = [:]
    var timeout: TimeInterval?
    /// `--set-key <backend>` (key read from stdin) / `--clear-key <backend>`.
    var setKey: NovaAIBackend?
    var clearKey: NovaAIBackend?
    /// Notes about deprecated flags/variables, printed to stderr.
    var notices: [String] = []

    /// True when the arguments ask for something AI-related, so `main.m` hands off to the bridge.
    static func isAIInvocation(_ args: [String]) -> Bool {
        args.contains { arg in
            triggers.contains(arg) || arg.hasPrefix("--url=")
        }
    }

    static let triggers: Set<String> = [
        "--ask", "--llm-status", "--ai-status", "--llm-help", "--ai-help", "--version",
        "--ai", "--no-ai", "--backend", "--model", "--url", "--list-models", "--set-key", "--clear-key", "--save",
        "--timeout", "--ollama-url", "--nova-url", "--ollama-model", "--openrouter-model",
        // Pre-1.1 balancer flags (still accepted).
        "--all-local", "--frontier", "--nova-gateway", "--policy", "--llm-config",
    ]

    enum ParseError: Error, Equatable, LocalizedError {
        case missingValue(String)
        case unknownBackend(String)
        case badValue(String, String)

        var errorDescription: String? {
            switch self {
            case .missingValue(let f): return "\(f) needs a value."
            case .unknownBackend(let b):
                return "Unknown backend '\(b)'. Use one of: \(NovaAIBackend.selectable.map(\.rawValue).joined(separator: ", "))."
            case .badValue(let f, let v): return "Invalid value for \(f): \(v)"
            }
        }
    }

    static func backend(named raw: String) throws -> NovaAIBackend {
        guard let b = NovaAIBackend(legacyName: raw) else { throw ParseError.unknownBackend(raw) }
        return b
    }

    /// Environment first, then flags (flags win). Secrets are never read from the environment.
    static func parse(_ args: [String], environment env: [String: String] = [:]) throws -> MboxAIOptions {
        var o = MboxAIOptions()
        if let v = env["OLLAMA_URL"], !v.isEmpty { o.urls[.ollama] = v }
        if let v = env["NOVA_GATEWAY_URL"], !v.isEmpty { o.urls[.novaGateway] = v }
        if let v = env["MBOX_AI_BACKEND"], !v.isEmpty { o.backend = try backend(named: v) }
        if isTruthy(env["MBOX_LLM_ALL_LOCAL"]) { o.backend = .auto }
        if isTruthy(env["MBOX_LLM_NOVA"]) { o.backend = .novaGateway }
        if isTruthy(env["MBOX_LLM_FRONTIER"]) { o.backend = .openRouter }
        if env.keys.contains(where: { $0.hasSuffix("_API_KEY") }) {
            o.notices.append("API keys in environment variables are ignored. Store one in the Keychain with --set-key <backend>.")
        }
        if env["MBOX_LLM_CONFIG"] != nil {
            o.notices.append("MBOX_LLM_CONFIG is no longer used; settings persist with --save.")
        }

        var i = args.startIndex
        func value(_ flag: String) throws -> String {
            let n = args.index(after: i)
            guard n < args.endIndex else { throw ParseError.missingValue(flag) }
            i = n
            return args[n]
        }
        while i < args.endIndex {
            let arg = args[i]
            switch arg {
            case "--ask": o.ask = try value(arg)
            case "--system": o.system = try value(arg)
            case "--llm-status", "--ai-status": o.status = true
            case "--llm-help", "--ai-help": o.help = true
            case "--version": o.version = true
            case "--list-models": o.listModels = true
            case "--save": o.save = true
            case "--no-ai": o.enabled = false
            case "--ai":
                let v = try value(arg).lowercased()
                if ["on", "true", "1", "yes"].contains(v) { o.enabled = true }
                else if ["off", "false", "0", "no"].contains(v) { o.enabled = false }
                else { throw ParseError.badValue(arg, v) }
            case "--backend": o.backend = try backend(named: try value(arg))
            case "--model": o.model = try value(arg)
            case "--ollama-model": o.models[.ollama] = try value(arg)
            case "--openrouter-model": o.models[.openRouter] = try value(arg)
            case "--ollama-url": o.urls[.ollama] = try value(arg)
            case "--nova-url": o.urls[.novaGateway] = try value(arg)
            case "--url":
                let (b, u) = try backendAndURL(try value(arg), flag: arg)
                o.urls[b] = u
            case "--timeout":
                let v = try value(arg)
                guard let t = TimeInterval(v), NovaAISettings.timeoutRange.contains(t) else { throw ParseError.badValue(arg, v) }
                o.timeout = t
            case "--set-key": o.setKey = try backend(named: try value(arg))
            case "--clear-key": o.clearKey = try backend(named: try value(arg))
            // Pre-1.1 balancer modes: NovaAIKit's Auto failover replaces the pool.
            case "--all-local": o.backend = .auto
            case "--frontier": o.backend = .openRouter
            case "--nova-gateway": o.backend = .novaGateway
            case "--policy":
                _ = try value(arg)
                o.notices.append("--policy is ignored: Auto now fails over in a fixed order (local first).")
            case "--llm-config":
                _ = try value(arg)
                o.notices.append("--llm-config is no longer used; pass flags and --save to keep them.")
            default:
                if arg.hasPrefix("--url=") {
                    let (b, u) = try backendAndURL(String(arg.dropFirst(6)), flag: "--url")
                    o.urls[b] = u
                }
            }
            i = args.index(after: i)
        }
        return o
    }

    /// "ollama=http://host:11434" → (.ollama, URL).
    static func backendAndURL(_ s: String, flag: String) throws -> (NovaAIBackend, String) {
        guard let eq = s.firstIndex(of: "=") else { throw ParseError.badValue(flag, s) }
        let b = try backend(named: String(s[..<eq]))
        let u = String(s[s.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
        guard b != .auto, let url = URL(string: u), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host?.isEmpty == false else { throw ParseError.badValue(flag, s) }
        return (b, u)
    }

    static func isTruthy(_ s: String?) -> Bool {
        guard let s = s?.lowercased() else { return false }
        return ["1", "true", "yes", "on"].contains(s)
    }

    /// True when the options change settings (as opposed to only reading them).
    var changesSettings: Bool {
        enabled != nil || backend != nil || model != nil || !models.isEmpty || !urls.isEmpty || timeout != nil
    }

    /// The settings with these options applied.
    func applied(to base: NovaAISettings) -> NovaAISettings {
        var s = base
        if let enabled { s.enabled = enabled }
        if let backend { s.backend = backend }
        if let timeout { s.timeout = timeout }
        for (b, u) in urls { s.setURL(u, for: b) }
        for (b, m) in models { s.setModel(m, for: b) }
        if let model { s.setModel(model, for: s.backend == .auto ? .ollama : s.backend) }
        return s
    }
}

// MARK: - Ask

/// One email as the bridge hands it over from the Objective-C side.
struct MboxEmail: Sendable, Equatable {
    var from: String
    var subject: String
    var date: String
    var body: String

    init(from: String = "", subject: String = "", date: String = "", body: String = "") {
        self.from = from
        self.subject = subject
        self.date = date
        self.body = body
    }

    init(dictionary d: [String: String]) {
        self.init(from: d["from"] ?? "", subject: d["subject"] ?? "", date: d["date"] ?? "", body: d["body"] ?? "")
    }
}

enum MboxAsk {
    static let defaultSystemPrompt = """
    You answer questions about the user's email archive (an MBOX file). Use only the emails provided as context. \
    If they do not contain the answer, say so plainly. Be concise. Plain text, no markdown.
    """

    /// Emails sent to the model at most, and characters of each body.
    static let maxContextEmails = 8
    static let maxBodyCharacters = 1_200
    /// Longest answer printed.
    static let maxAnswerCharacters = 6_000

    /// Lowercased words of 3+ letters, minus common filler.
    static func keywords(_ text: String) -> [String] {
        let stop: Set<String> = ["the", "and", "for", "are", "was", "were", "what", "who", "when", "where", "which",
                                 "how", "why", "did", "does", "about", "with", "from", "that", "this", "any", "all",
                                 "email", "emails", "mail", "message", "messages", "have", "has", "had", "you", "me"]
        var seen = Set<String>()
        return text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stop.contains($0) && seen.insert($0).inserted }
    }

    /// The emails that best match the question (subject hits count double), best first; ties keep archive order.
    static func relevant(_ emails: [MboxEmail], to question: String, limit: Int = maxContextEmails) -> [MboxEmail] {
        let words = keywords(question)
        guard !words.isEmpty, limit > 0 else { return [] }
        let scored: [(Int, Int)] = emails.enumerated().compactMap { idx, e in
            let subject = e.subject.lowercased(), from = e.from.lowercased(), body = e.body.lowercased()
            let score = words.reduce(0) { acc, w in
                acc + (subject.contains(w) ? 2 : 0) + (from.contains(w) ? 2 : 0) + (body.contains(w) ? 1 : 0)
            }
            return score > 0 ? (idx, score) : nil
        }
        return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }.prefix(limit).map { emails[$0.0] }
    }

    /// The context block sent with the question.
    static func context(_ emails: [MboxEmail]) -> String {
        emails.enumerated().map { i, e in
            let body = e.body.count > maxBodyCharacters ? String(e.body.prefix(maxBodyCharacters)) + "…" : e.body
            return "[\(i + 1)] From: \(e.from)\nDate: \(e.date)\nSubject: \(e.subject)\n\(body)"
        }.joined(separator: "\n\n")
    }

    static func request(question: String, system: String?, emails: [MboxEmail], totalLoaded: Int) -> NovaAIRequest {
        let matches = relevant(emails, to: question)
        var prompt = question
        if totalLoaded > 0 {
            prompt = """
            The archive holds \(totalLoaded) emails. \(matches.isEmpty ? "None matched the question's keywords." : "The \(matches.count) most relevant:")

            \(context(matches))

            Question: \(question)
            """
        }
        return NovaAIRequest(prompt: prompt, system: system ?? defaultSystemPrompt, temperature: 0.3, maxTokens: 800)
    }

    /// Built-in answer when AI is off, unreachable, or its reply was rejected: a keyword search of the archive.
    static func fallback(question: String, emails: [MboxEmail], totalLoaded: Int, reason: String) -> String {
        var lines = ["AI unavailable (\(reason)). Built-in keyword search:"]
        guard totalLoaded > 0 else {
            lines.append("No mailbox is loaded. Start the tool with an .mbox file, or use from/subject/count/summarize.")
            return lines.joined(separator: "\n")
        }
        let words = keywords(question)
        let matches = relevant(emails, to: question, limit: Int.max)
        if words.isEmpty {
            lines.append("No searchable keywords in the question.")
        } else {
            lines.append("\(matches.count) of \(totalLoaded) emails match \(words.map { "'\($0)'" }.joined(separator: ", ")).")
        }
        for e in matches.prefix(5) {
            lines.append("- \(e.date.isEmpty ? "?" : e.date) | \(e.from.isEmpty ? "?" : e.from) | \(e.subject.isEmpty ? "(no subject)" : e.subject)")
        }
        return lines.joined(separator: "\n")
    }

    /// Output validation: non-empty after removing reasoning, plain text, capped, and not just the question echoed.
    static func validate(question: String) -> @Sendable (String) throws -> String {
        { reply in
            guard let cleaned = NovaAIText.clean(reply) else { throw NovaAIValidationError("empty reply") }
            let text = NovaAIText.plain(cleaned, max: maxAnswerCharacters)
            guard !text.isEmpty else { throw NovaAIValidationError("empty reply") }
            let q = question.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !q.isEmpty && text.lowercased() == q { throw NovaAIValidationError("the reply only repeated the question") }
            return text
        }
    }

    static func reasonText(_ source: NovaAISource) -> String {
        switch source {
        case .ai: return "AI"
        case .fallback(.disabled): return "AI is off; turn it on with --ai on --save"
        case .fallback(.unavailable(let why)): return why
        case .fallback(.validationFailed(let why)): return "reply rejected: \(why)"
        }
    }

    /// Ask: AI with validation, or the built-in search. Never throws.
    @MainActor
    static func answer(_ question: String, system: String?, emails: [MboxEmail], totalLoaded: Int,
                       ai: NovaAI) async -> NovaAIResult<String> {
        let req = request(question: question, system: system, emails: emails, totalLoaded: totalLoaded)
        // The fallback text depends on why it ran, so it is built after the call.
        let result = await ai.text(req, validate: validate(question: question)) { "" }
        guard !result.isAI else { return result }
        let text = fallback(question: question, emails: emails, totalLoaded: totalLoaded, reason: reasonText(result.source))
        return NovaAIResult(value: text, source: result.source)
    }
}

// MARK: - Status

enum MboxAIStatusReport {
    /// The CLI's status indicator: state, active backend/model, reachability, keys (stored or not, never values).
    @MainActor
    static func lines(_ ai: NovaAI) -> [String] {
        let s = ai.settings
        var out = ["MboxChatCLI \(MboxChatCLIVersion.current) — AI status (NovaAIKit)"]
        out.append("  status:   \(symbol(ai.status.state)) \(ai.status.label)")
        out.append("  AI:       \(s.enabled ? "on" : "off (built-in keyword search only)")")
        out.append("  backend:  \(s.backend.displayName)\(s.backend == .auto ? " (fails over: \(NovaAIBackend.autoOrder.map(\.rawValue).joined(separator: " → ")))" : "")")
        out.append("  timeout:  \(Int(s.timeout)) s")
        for b in NovaAIBackend.autoOrder {
            let reach: String
            switch ai.status.reachability[b] {
            case true?: reach = "reachable"
            case false?: reach = "unreachable"
            case nil: reach = "not checked"
            }
            var line = "    \(b.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)) \(s.url(for: b))  model: \(s.model(for: b))  [\(reach)]"
            if b.acceptsKey { line += "  key: \(ai.hasAPIKey(for: b) ? "stored" : "none")" }
            out.append(line)
        }
        if let err = ai.status.lastError, ai.status.state != .online { out.append("  last error: \(err)") }
        out.append("  Keychain: \(AppAI.configuration.keychainService(for: .openRouter).replacingOccurrences(of: ".openrouter", with: ".<backend>"))")
        return out
    }

    nonisolated static func symbol(_ state: NovaAIStatus.State) -> String {
        switch state {
        case .online: return "●"
        case .offline: return "○"
        case .off: return "–"
        default: return "…"
        }
    }
}
