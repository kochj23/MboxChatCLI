//
//  AIKitAdoptionTests.swift
//  MboxLLMTests
//
//  The tool's contract with NovaAIKit, grouped by the seven test categories (security, performance, retry,
//  unit, integration, functional, frame/UI-state). No network (every request goes to a stub URLProtocol) and no
//  real Keychain (in-memory key store).
//
//  Copyright © 2026 Jordan Koch. All rights reserved.
//

import XCTest
import NovaAIKit
@testable import MboxLLM

// MARK: - Helpers

/// Fails every request: "every backend is down".
final class RefuseAllProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost)) }
    override func stopLoading() {}
}

/// Answers every chat request with `StubReplyProtocol.reply` in Ollama's /api/chat format and counts requests.
final class StubReplyProtocol: URLProtocol {
    nonisolated(unsafe) static var reply = "stub"
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [String] = []
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        if let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                data.append(buf, count: n)
            }
            stream.close()
            Self.bodies.append(String(decoding: data, as: UTF8.self))
        } else if let body = request.httpBody {
            Self.bodies.append(String(decoding: body, as: UTF8.self))
        }
        let reply = Self.reply
        Self.lock.unlock()
        let obj: [String: Any] = ["model": "stub-model", "message": ["role": "assistant", "content": reply], "done": true]
        let data = try! JSONSerialization.data(withJSONObject: obj)
        let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                   headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func reset(reply: String) {
        lock.lock(); self.reply = reply; requests = []; bodies = []; lock.unlock()
    }
}

@MainActor
func makeAI(_ s: NovaAISettings = NovaAISettings(), protocolClass: AnyClass = RefuseAllProtocol.self,
            keys: NovaAIMemoryKeyStore = NovaAIMemoryKeyStore()) -> NovaAI {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.protocolClasses = [protocolClass]
    return NovaAI(configuration: AppAI.configuration, storage: NovaAIMemoryStorage(s), keyStore: keys,
                  session: URLSession(configuration: cfg), sleep: { _ in })
}

let sampleMail: [MboxEmail] = [
    MboxEmail(from: "alice@example.com", subject: "Budget review Q3", date: "Mon, 1 Jul 2024", body: "The budget is 4,100 dollars."),
    MboxEmail(from: "bob@example.com", subject: "Lunch", date: "Tue, 2 Jul 2024", body: "Pizza on Friday?"),
    MboxEmail(from: "carol@example.com", subject: "Re: budget", date: "Wed, 3 Jul 2024", body: "Approved the budget."),
]

// MARK: - Security

final class AISecurityTests: XCTestCase {
    func testKeychainServiceNames() {
        let c = AppAI.configuration
        XCTAssertEqual(c.appID, "mboxchatcli")
        XCTAssertEqual(c.keychainService(for: .openRouter), "com.jkoch.mboxchatcli.openrouter")
        XCTAssertEqual(c.keychainService(for: .openAI), "com.jkoch.mboxchatcli.openai")
        XCTAssertEqual(NovaAIConfiguration.keychainAccount, "apiKey")
    }

    func testEnvironmentKeysAreIgnored() throws {
        let o = try MboxAIOptions.parse(["--ask", "hi"], environment: ["OPENROUTER_API_KEY": "sk-secret", "OPENAI_API_KEY": "sk-x"])
        XCTAssertTrue(o.notices.contains { $0.contains("ignored") })
        // Nothing in the parsed options carries the secret.
        XCTAssertFalse(String(describing: o).contains("sk-secret"))
    }

    @MainActor
    func testLegacyOpenRouterKeyCopiedAndOriginalKept() {
        let store = NovaAIMemoryKeyStore()
        _ = store.write("or-key", service: AppAI.legacyOpenRouterService, account: "apiKey")
        let ai = makeAI(keys: store)
        let defaults = UserDefaults(suiteName: "mboxchatcli.test.\(UUID().uuidString)")!
        AppAI.migrateLegacy(ai, defaults: defaults)
        XCTAssertTrue(ai.hasAPIKey(for: .openRouter))
        // AIStudio still owns the old item: it must survive.
        XCTAssertEqual(store.read(service: AppAI.legacyOpenRouterService, account: "apiKey"), "or-key")
        XCTAssertTrue(defaults.bool(forKey: AppAI.keyMigrationMarker))
    }

    @MainActor
    func testPlaintextOpenAIKeyMovesOutOfUserDefaults() {
        let store = NovaAIMemoryKeyStore()
        let ai = makeAI(keys: store)
        let defaults = UserDefaults(suiteName: "mboxchatcli.test.\(UUID().uuidString)")!
        defaults.set("sk-plain", forKey: "AIBackend_OpenAI_Key")
        defaults.set("gcp", forKey: "AIBackend_GoogleCloud_Key")
        AppAI.migrateLegacy(ai, defaults: defaults)
        XCTAssertNil(defaults.object(forKey: "AIBackend_OpenAI_Key"))
        XCTAssertNil(defaults.object(forKey: "AIBackend_GoogleCloud_Key"))
        XCTAssertTrue(ai.hasAPIKey(for: .openAI))
    }

    @MainActor
    func testKeyIsNeverSentOverPlainHTTP() async {
        let keys = NovaAIMemoryKeyStore()
        var s = NovaAISettings(backend: .openRouter)
        s.setURL("http://example.com", for: .openRouter)
        let ai = makeAI(s, protocolClass: StubReplyProtocol.self, keys: keys)
        ai.setAPIKey("k", for: .openRouter)
        StubReplyProtocol.reset(reply: "should not be used")
        let r = await MboxAsk.answer("budget", system: nil, emails: sampleMail, totalLoaded: 3, ai: ai)
        XCTAssertFalse(r.isAI)
        XCTAssertTrue(StubReplyProtocol.requests.isEmpty, "nothing may be sent with a key over http")
    }

    func testStatusReportNeverPrintsKeys() async {
        let ai = await makeAI()
        await MainActor.run { _ = ai.setAPIKey("sk-very-secret", for: .openAI) }
        let lines = await MboxAIStatusReport.lines(ai)
        XCTAssertFalse(lines.joined().contains("sk-very-secret"))
        XCTAssertTrue(lines.contains { $0.contains("openai") && $0.contains("key: stored") })
    }
}

// MARK: - Performance

final class AIPerformanceTests: XCTestCase {
    func testRelevanceRankingIsFastOnLargeArchives() {
        let mail = (0..<20_000).map { MboxEmail(from: "u\($0)@x.com", subject: "Subject \($0 % 50)", date: "", body: "body text \($0)") }
        measure { _ = MboxAsk.relevant(mail, to: "subject budget body") }
    }

    func testContextIsBounded() {
        let big = String(repeating: "x", count: 50_000)
        let mail = (0..<100).map { MboxEmail(from: "a", subject: "budget \($0)", date: "", body: big) }
        let req = MboxAsk.request(question: "budget", system: nil, emails: mail, totalLoaded: mail.count)
        let chars = req.messages.reduce(0) { $0 + $1.content.count }
        XCTAssertLessThan(chars, MboxAsk.maxContextEmails * (MboxAsk.maxBodyCharacters + 300) + 1_000)
    }

    @MainActor
    func testOfflineFallbackDoesNotHang() async {
        let start = Date()
        _ = await MboxAsk.answer("budget", system: nil, emails: sampleMail, totalLoaded: 3, ai: makeAI())
        XCTAssertLessThan(Date().timeIntervalSince(start), 10)
    }
}

// MARK: - Retry / failover

final class AIRetryTests: XCTestCase {
    @MainActor
    func testRejectedReplyIsRetriedOnceThenFallsBack() async {
        StubReplyProtocol.reset(reply: "budget")      // only echoes the question → rejected twice
        let ai = makeAI(NovaAISettings(backend: .ollama), protocolClass: StubReplyProtocol.self)
        let r = await MboxAsk.answer("budget", system: nil, emails: sampleMail, totalLoaded: 3, ai: ai)
        XCTAssertFalse(r.isAI)
        XCTAssertEqual(StubReplyProtocol.requests.count, 2, "one ask + one retry with the complaint")
        XCTAssertTrue(r.value.contains("Built-in keyword search"))
        guard case .fallback(.validationFailed) = r.source else { return XCTFail("expected validationFailed, got \(r.source)") }
    }

    @MainActor
    func testAutoFailsOverAndFallsBackWhenEverythingIsDown() async {
        let ai = makeAI(NovaAISettings(backend: .auto))
        let r = await MboxAsk.answer("budget", system: nil, emails: sampleMail, totalLoaded: 3, ai: ai)
        guard case .fallback(.unavailable) = r.source else { return XCTFail("expected unavailable fallback, got \(r.source)") }
        XCTAssertEqual(ai.status.state, .offline)
    }

    func testAutoOrderIsLocalFirst() {
        XCTAssertEqual(NovaAIBackend.autoOrder.first, .ollama)
        XCTAssertEqual(NovaAIBackend.allCases.count, 9)
        XCTAssertEqual(Array(NovaAIBackend.autoOrder.suffix(2)), [.openRouter, .openAI])
    }
}

// MARK: - Unit

final class AIUnitTests: XCTestCase {
    func testParseSettingsFlags() throws {
        let o = try MboxAIOptions.parse(["--backend", "ollama", "--model", "llama3.2:3b", "--url", "ollama=http://studio.local:11434",
                                         "--timeout", "30", "--ai", "off", "--save"])
        XCTAssertEqual(o.backend, .ollama)
        XCTAssertEqual(o.model, "llama3.2:3b")
        XCTAssertEqual(o.urls[.ollama], "http://studio.local:11434")
        XCTAssertEqual(o.timeout, 30)
        XCTAssertEqual(o.enabled, false)
        XCTAssertTrue(o.save)
        let s = o.applied(to: NovaAISettings())
        XCTAssertEqual(s.backend, .ollama)
        XCTAssertEqual(s.model(for: .ollama), "llama3.2:3b")
        XCTAssertEqual(s.url(for: .ollama), "http://studio.local:11434")
        XCTAssertFalse(s.enabled)
    }

    func testLegacyBalancerFlagsMapToBackends() throws {
        XCTAssertEqual(try MboxAIOptions.parse(["--all-local"]).backend, .auto)
        XCTAssertEqual(try MboxAIOptions.parse(["--frontier"]).backend, .openRouter)
        XCTAssertEqual(try MboxAIOptions.parse(["--nova-gateway"]).backend, .novaGateway)
        let p = try MboxAIOptions.parse(["--policy", "roundRobin"])
        XCTAssertNil(p.backend)
        XCTAssertFalse(p.notices.isEmpty)
        XCTAssertEqual(try MboxAIOptions.parse(["--ollama-model", "m"]).models[.ollama], "m")
        XCTAssertEqual(try MboxAIOptions.parse([], environment: ["OLLAMA_URL": "http://h:1"]).urls[.ollama], "http://h:1")
    }

    func testParseErrors() {
        XCTAssertThrowsError(try MboxAIOptions.parse(["--backend", "watson-ish"]))
        XCTAssertThrowsError(try MboxAIOptions.parse(["--ask"]))
        XCTAssertThrowsError(try MboxAIOptions.parse(["--url", "ollama"]))
        XCTAssertThrowsError(try MboxAIOptions.parse(["--url", "ollama=ftp://x"]))
        XCTAssertThrowsError(try MboxAIOptions.parse(["--timeout", "9999"]))
        XCTAssertThrowsError(try MboxAIOptions.parse(["--ai", "maybe"]))
    }

    func testRemovedCloudBackendsMapToAuto() throws {
        XCTAssertEqual(try MboxAIOptions.backend(named: "Google Cloud AI"), .auto)
        XCTAssertEqual(try MboxAIOptions.backend(named: "OpenRouter"), .openRouter)
    }

    func testAIInvocationDetection() {
        XCTAssertTrue(MboxAIOptions.isAIInvocation(["x", "--ask", "q"]))
        XCTAssertTrue(MboxAIOptions.isAIInvocation(["x", "--ai-status"]))
        XCTAssertTrue(MboxAIOptions.isAIInvocation(["x", "--llm-status"]))
        XCTAssertFalse(MboxAIOptions.isAIInvocation(["x", "/tmp/a.mbox"]))
    }

    func testValidatorRejectsNonsense() {
        let v = MboxAsk.validate(question: "What is the budget?")
        XCTAssertThrowsError(try v(""))
        XCTAssertThrowsError(try v("<think>hmm</think>   "))
        XCTAssertThrowsError(try v("what is the budget?"))
        XCTAssertEqual(try v("<think>x</think>**4,100** dollars"), "4,100 dollars")
        XCTAssertLessThanOrEqual(try v(String(repeating: "a", count: 50_000)).count, MboxAsk.maxAnswerCharacters)
    }

    func testRelevanceRanksSubjectHitsFirst() {
        let r = MboxAsk.relevant(sampleMail, to: "budget")
        XCTAssertEqual(r.map(\.from), ["alice@example.com", "carol@example.com"])
        XCTAssertTrue(MboxAsk.relevant(sampleMail, to: "the and").isEmpty)
    }
}

// MARK: - Integration

final class AIIntegrationTests: XCTestCase {
    @MainActor
    func testAskSendsRelevantEmailsAsContext() async {
        StubReplyProtocol.reset(reply: "The budget is 4,100 dollars and was approved.")
        let ai = makeAI(NovaAISettings(backend: .ollama), protocolClass: StubReplyProtocol.self)
        let r = await MboxAsk.answer("What is the budget?", system: nil, emails: sampleMail, totalLoaded: 3, ai: ai)
        XCTAssertTrue(r.isAI)
        XCTAssertEqual(r.value, "The budget is 4,100 dollars and was approved.")
        XCTAssertEqual(StubReplyProtocol.requests.first?.url?.path, "/api/chat")
        let body = StubReplyProtocol.bodies.first ?? ""
        XCTAssertTrue(body.contains("Budget review Q3"))
        XCTAssertFalse(body.contains("Pizza on Friday"), "irrelevant emails stay out of the prompt")
        XCTAssertEqual(ai.status.state, .online)
    }

    @MainActor
    func testLegacySettingsMigrate() {
        let ai = makeAI()
        let defaults = UserDefaults(suiteName: "mboxchatcli.test.\(UUID().uuidString)")!
        defaults.set("Ollama", forKey: "AIBackend_Active")
        defaults.set("http://studio.local:11434", forKey: "AIBackend_OllamaURL")
        defaults.set("mistral:latest", forKey: "AIBackend_OllamaModel")
        AppAI.migrateLegacy(ai, defaults: defaults)
        XCTAssertEqual(ai.settings.backend, .ollama)
        XCTAssertEqual(ai.settings.url(for: .ollama), "http://studio.local:11434")
        XCTAssertEqual(ai.settings.model(for: .ollama), "mistral:latest")
    }

    func testNoLegacyAIClientInSources() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let banned = ["AIBackendManager", "LLMBackendManager", "OpenRouterProvider", "KeychainStore", "OPENAI_API_KEY",
                      "AIBackend_OpenAI_Key", "chat/completions", "/api/generate"]
        let fm = FileManager.default
        var checked = 0
        for dir in ["MboxChatCLI", "."] {
            let base = root.appendingPathComponent(dir)
            let files = (dir == "." ? (try fm.contentsOfDirectory(atPath: base.path)).map { base.appendingPathComponent($0) }
                         : (fm.enumerator(at: base, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []))
            for f in files where f.pathExtension == "swift" && f.lastPathComponent != "Package.swift" {
                let text = try String(contentsOf: f, encoding: .utf8)
                    .replacingOccurrences(of: "migrateFromLegacyAIBackendManager", with: "")
                checked += 1
                for b in banned {
                    XCTAssertFalse(text.contains(b), "\(f.lastPathComponent) still references \(b)")
                }
            }
        }
        XCTAssertGreaterThan(checked, 0)
    }
}

// MARK: - Functional

final class AIFunctionalTests: XCTestCase {
    @MainActor
    func testEveryFeatureWorksWithAIOff() async {
        StubReplyProtocol.reset(reply: "unused")
        let ai = makeAI(NovaAISettings(enabled: false), protocolClass: StubReplyProtocol.self)
        let r = await MboxAsk.answer("budget", system: nil, emails: sampleMail, totalLoaded: 3, ai: ai)
        XCTAssertEqual(r.source, .fallback(.disabled))
        XCTAssertTrue(r.value.contains("2 of 3 emails match 'budget'"))
        XCTAssertTrue(r.value.contains("Budget review Q3"))
        XCTAssertTrue(StubReplyProtocol.requests.isEmpty, "AI off: nothing is sent")
        XCTAssertEqual(ai.status.state, .off)
    }

    @MainActor
    func testEveryFeatureFallsBackWhenOffline() async {
        let r = await MboxAsk.answer("lunch", system: nil, emails: sampleMail, totalLoaded: 3, ai: makeAI())
        XCTAssertFalse(r.isAI)
        XCTAssertTrue(r.value.contains("1 of 3 emails match 'lunch'"))
    }

    func testFallbackWithoutMailbox() {
        let t = MboxAsk.fallback(question: "anything", emails: [], totalLoaded: 0, reason: "AI is off")
        XCTAssertTrue(t.contains("No mailbox is loaded"))
    }

    func testRequestWithoutMailboxIsThePlainQuestion() {
        let r = MboxAsk.request(question: "Hello?", system: "S", emails: [], totalLoaded: 0)
        XCTAssertEqual(r.messages.map(\.content), ["S", "Hello?"])
    }
}

// MARK: - Frame / UI state (the CLI's status indicator)

final class AIStatusStateTests: XCTestCase {
    @MainActor
    func testStatusOffWhenDisabled() {
        let ai = makeAI(NovaAISettings(enabled: false))
        XCTAssertEqual(ai.status.state, .off)
        let lines = MboxAIStatusReport.lines(ai)
        XCTAssertTrue(lines.contains { $0.contains("AI:") && $0.contains("off") })
        XCTAssertEqual(MboxAIStatusReport.symbol(.off), "–")
    }

    @MainActor
    func testStatusOfflineAfterRefreshWithNothingReachable() async {
        let ai = makeAI()
        await ai.refreshStatus()
        XCTAssertEqual(ai.status.state, .offline)
        let lines = MboxAIStatusReport.lines(ai)
        XCTAssertTrue(lines.contains { $0.contains("ollama") && $0.contains("unreachable") })
        XCTAssertEqual(MboxAIStatusReport.symbol(.offline), "○")
    }

    @MainActor
    func testStatusOnlineAfterAnAnswer() async {
        StubReplyProtocol.reset(reply: "ok answer")
        let ai = makeAI(NovaAISettings(backend: .ollama), protocolClass: StubReplyProtocol.self)
        _ = await MboxAsk.answer("budget", system: nil, emails: sampleMail, totalLoaded: 3, ai: ai)
        XCTAssertEqual(ai.status.state, .online)
        XCTAssertEqual(ai.status.activeBackend, .ollama)
        XCTAssertEqual(ai.status.lastSource?.isAI, true)
        XCTAssertEqual(MboxAIStatusReport.symbol(.online), "●")
    }

    @MainActor
    func testTransientOverridesAreNotSaved() {
        let base = NovaAISettings()
        let o = try! MboxAIOptions.parse(["--backend", "ollama"])
        let ai = AppAI.transient(o.applied(to: base))
        XCTAssertEqual(ai.settings.backend, .ollama)
        XCTAssertEqual(base.backend, .auto)
    }
}
