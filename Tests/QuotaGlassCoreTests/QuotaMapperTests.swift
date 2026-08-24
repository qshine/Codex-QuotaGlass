import Foundation
import Testing
@testable import QuotaGlassCore

@Suite("Quota mapping")
struct QuotaMapperTests {
    @Test func clampCoversBounds() {
        #expect(QuotaWindow.clamp(-1) == 0)
        #expect(QuotaWindow.clamp(0) == 0)
        #expect(QuotaWindow.clamp(73) == 73)
        #expect(QuotaWindow.clamp(100) == 100)
        #expect(QuotaWindow.clamp(130) == 100)
    }

    @Test func decoderAndMultiBucketMapping() throws {
        let url = try #require(Bundle.module.url(forResource: "rate-limits", withExtension: "json", subdirectory: "Fixtures"))
        let line = try String(contentsOf: url, encoding: .utf8)
        let message = AppServerMessageDecoder.decode(line: line)

        guard case .rateLimitResponse(let id, let result) = message else {
            Issue.record("Expected rate-limit response, received \(message)")
            return
        }

        #expect(id == 2)
        let windows = QuotaMapper.windows(from: result)
        #expect(windows.count == 3)
        #expect(windows.first(where: { $0.kind == .primary })?.remainingPercent == 93)
        #expect(windows.first(where: { $0.kind == .secondary })?.remainingPercent == 46)
        #expect(windows.first(where: { $0.kind == .individual })?.remainingPercent == 61)
        #expect(QuotaMapper.selectMostConstrained(from: windows)?.kind == .secondary)
    }

    @Test func multiBucketViewWinsOverLegacyView() {
        let result = decodeResult(
            """
            {
              "rateLimits": {"primary":{"usedPercent":99}},
              "rateLimitsByLimitId": {
                "codex":{"primary":{"usedPercent":20}}
              }
            }
            """
        )

        let windows = QuotaMapper.windows(from: result)
        #expect(windows.count == 1)
        #expect(windows[0].remainingPercent == 80)
    }

    @Test func legacyFallbackWorks() {
        let result = decodeResult(
            """
            {"rateLimits":{"limitId":"codex","primary":{"usedPercent":100}}}
            """
        )

        let selected = QuotaMapper.selectMostConstrained(from: QuotaMapper.windows(from: result))
        #expect(selected?.remainingPercent == 0)
    }

    @Test func tiePrefersLaterResetThenPrimary() {
        let early = Date(timeIntervalSince1970: 100)
        let late = Date(timeIntervalSince1970: 200)
        let secondary = window(id: "secondary", kind: .secondary, percent: 20, reset: late)
        let primaryEarly = window(id: "primary-early", kind: .primary, percent: 20, reset: early)
        #expect(QuotaMapper.selectMostConstrained(from: [primaryEarly, secondary])?.id == secondary.id)

        let primaryLate = window(id: "primary-late", kind: .primary, percent: 20, reset: late)
        #expect(QuotaMapper.selectMostConstrained(from: [secondary, primaryLate])?.id == primaryLate.id)
    }

    @Test func snapshotStalenessThreshold() throws {
        let updated = Date(timeIntervalSince1970: 1_000)
        let selected = window(id: "primary", kind: .primary, percent: 50, reset: nil)
        let snapshot = QuotaSnapshot(selected: selected, windows: [selected], lastUpdated: updated)

        #expect(!snapshot.isStale(at: updated.addingTimeInterval(60)))
        #expect(snapshot.isStale(at: updated.addingTimeInterval(60.01)))
    }

    @Test func notificationAndErrorDecoding() {
        #expect(
            AppServerMessageDecoder.decode(line: #"{"id":1,"result":{}}"#)
                == .otherResponse(id: 1)
        )

        #expect(
            AppServerMessageDecoder.decode(line: #"{"method":"account/rateLimits/updated","params":{}}"#)
                == .notification(method: "account/rateLimits/updated")
        )

        #expect(
            AppServerMessageDecoder.decode(line: #"{"id":2,"error":{"code":401,"message":"Login required"}}"#)
                == .errorResponse(id: 2, error: RPCErrorPayload(code: 401, message: "Login required"))
        )

        #expect(
            AppServerMessageDecoder.decode(line: #"{"id":3,"result":{"rateLimits":{"primary":{}}}}"#)
                != .unknown
        )
    }

    @Test func missingFieldsAndResetJumpAreSafe() {
        let missing = decodeResult(#"{"rateLimits":{"limitId":"codex"}}"#)
        #expect(QuotaMapper.windows(from: missing).isEmpty)

        let exhausted = decodeResult(#"{"rateLimits":{"primary":{"usedPercent":100,"resetsAt":100}}}"#)
        let reset = decodeResult(#"{"rateLimits":{"primary":{"usedPercent":0,"resetsAt":200}}}"#)
        #expect(QuotaMapper.snapshot(from: exhausted)?.selected.remainingPercent == 0)
        #expect(QuotaMapper.snapshot(from: reset)?.selected.remainingPercent == 100)
    }

    @Test func reconnectBackoffIsBounded() {
        #expect((0 ... 7).map(ReconnectBackoff.delay(forAttempt:)) == [1, 2, 5, 10, 30, 60, 60, 60])
    }

    private func decodeResult(_ json: String) -> RateLimitReadResult {
        try! JSONDecoder().decode(RateLimitReadResult.self, from: Data(json.utf8))
    }

    private func window(
        id: String,
        kind: QuotaWindowKind,
        percent: Int,
        reset: Date?
    ) -> QuotaWindow {
        QuotaWindow(
            id: id,
            sourceID: "codex",
            sourceName: "Codex",
            kind: kind,
            remainingPercent: percent,
            windowDurationMinutes: 300,
            resetsAt: reset
        )
    }
}
