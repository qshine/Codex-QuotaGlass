import Foundation
import QuotaGlassCore

@main
struct QuotaGlassChecks {
    static func main() async {
        var checks = CheckRecorder()

        checks.expect(QuotaWindow.clamp(-5) == 0, "negative percentage is clamped")
        checks.expect(QuotaWindow.clamp(125) == 100, "oversized percentage is clamped")

        let fullResponse = #"{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","limitName":"Codex","primary":{"usedPercent":7,"windowDurationMins":10080,"resetsAt":200},"secondary":{"usedPercent":54,"windowDurationMins":300,"resetsAt":300},"individualLimit":{"remainingPercent":61,"resetsAt":400},"futureField":"ignored"}}}}"#
        if case .rateLimitResponse(let id, let result) = AppServerMessageDecoder.decode(line: fullResponse) {
            let windows = QuotaMapper.windows(from: result)
            checks.expect(id == 2, "JSON-RPC response id")
            checks.expect(windows.count == 3, "all quota windows are mapped")
            checks.expect(windows.first(where: { $0.kind == .primary })?.remainingPercent == 93, "used percentage conversion")
            checks.expect(QuotaMapper.selectMostConstrained(from: windows)?.remainingPercent == 46, "most constrained window selection")
        } else {
            checks.expect(false, "full JSON-RPC response decoding")
        }

        checks.expect(
            AppServerMessageDecoder.decode(line: #"{"id":1,"result":{}}"#) == .otherResponse(id: 1),
            "initialization response decoding"
        )
        checks.expect(
            AppServerMessageDecoder.decode(line: #"{"method":"account/rateLimits/updated","params":{"partial":true}}"#)
                == .notification(method: "account/rateLimits/updated"),
            "sparse notification decoding"
        )
        checks.expect(
            AppServerMessageDecoder.decode(line: #"{"id":2,"error":{"code":401,"message":"Login required"}}"#)
                == .errorResponse(id: 2, error: RPCErrorPayload(code: 401, message: "Login required")),
            "error response decoding"
        )

        let missing = decodeResult(#"{"rateLimits":{"limitId":"codex"}}"#)
        checks.expect(QuotaMapper.windows(from: missing).isEmpty, "missing window fields")

        let legacy = decodeResult(#"{"rateLimits":{"primary":{"usedPercent":100}}}"#)
        checks.expect(QuotaMapper.snapshot(from: legacy)?.selected.remainingPercent == 0, "legacy payload fallback")

        let primary = window(id: "primary", kind: .primary, reset: 200)
        let secondary = window(id: "secondary", kind: .secondary, reset: 200)
        checks.expect(QuotaMapper.selectMostConstrained(from: [secondary, primary])?.kind == .primary, "primary tie break")
        let secondaryLater = window(id: "secondary-later", kind: .secondary, reset: 300)
        checks.expect(QuotaMapper.selectMostConstrained(from: [primary, secondaryLater])?.id == "secondary-later", "later reset tie break")

        let snapshot = QuotaSnapshot(selected: primary, windows: [primary], lastUpdated: Date(timeIntervalSince1970: 1_000))
        checks.expect(!snapshot.isStale(at: Date(timeIntervalSince1970: 1_060)), "fresh at 60 seconds")
        checks.expect(snapshot.isStale(at: Date(timeIntervalSince1970: 1_061)), "stale after 60 seconds")
        checks.expect((0 ... 7).map(ReconnectBackoff.delay(forAttempt:)) == [1, 2, 5, 10, 30, 60, 60, 60], "bounded reconnect backoff")

        let exhausted = decodeResult(#"{"rateLimits":{"primary":{"usedPercent":100,"resetsAt":100}}}"#)
        let reset = decodeResult(#"{"rateLimits":{"primary":{"usedPercent":0,"resetsAt":200}}}"#)
        checks.expect(QuotaMapper.snapshot(from: exhausted)?.selected.remainingPercent == 0, "exhausted state")
        checks.expect(QuotaMapper.snapshot(from: reset)?.selected.remainingPercent == 100, "server-confirmed reset jump")

        let provider = MockProvider()
        let stream = await provider.stateStream()
        let collector = Task { () -> [Int] in
            var values: [Int] = []
            for await state in stream {
                if case .available(let value) = state {
                    values.append(value.selected.remainingPercent)
                    if values.count == 5 { break }
                }
            }
            return values
        }
        for percent in [100, 50, 1, 0, 100] {
            await provider.send(percent)
        }
        let collectedValues = await collector.value
        checks.expect(collectedValues == [100, 50, 1, 0, 100], "mock provider UI sequence")
        await provider.stop()

        if checks.failures.isEmpty {
            print("QuotaGlass checks passed (\(checks.count) assertions)")
        } else {
            for failure in checks.failures {
                FileHandle.standardError.write(Data("FAIL: \(failure)\n".utf8))
            }
            exit(1)
        }
    }

    private static func decodeResult(_ json: String) -> RateLimitReadResult {
        try! JSONDecoder().decode(RateLimitReadResult.self, from: Data(json.utf8))
    }

    private static func window(id: String, kind: QuotaWindowKind, reset: TimeInterval) -> QuotaWindow {
        QuotaWindow(
            id: id,
            sourceID: "codex",
            sourceName: "Codex",
            kind: kind,
            remainingPercent: 20,
            windowDurationMinutes: 300,
            resetsAt: Date(timeIntervalSince1970: reset)
        )
    }
}

private struct CheckRecorder {
    private(set) var count = 0
    private(set) var failures: [String] = []

    mutating func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        count += 1
        if !condition() { failures.append(name) }
    }
}

private actor MockProvider: RateLimitProvider {
    private var continuation: AsyncStream<QuotaState>.Continuation?

    func stateStream() -> AsyncStream<QuotaState> {
        AsyncStream { continuation = $0 }
    }

    func start() {}
    func refresh() {}

    func stop() {
        continuation?.finish()
    }

    func send(_ percent: Int) {
        let value = QuotaWindow(
            id: "mock",
            sourceID: "mock",
            sourceName: "Mock",
            kind: .primary,
            remainingPercent: percent,
            windowDurationMinutes: 300,
            resetsAt: nil
        )
        continuation?.yield(.available(QuotaSnapshot(selected: value, windows: [value], lastUpdated: Date())))
    }
}
