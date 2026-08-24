import Foundation
import Testing
@testable import QuotaGlassCore

@Suite("Mock provider")
struct MockProviderTests {
    @Test func drivesFullHourglassSequence() async {
        let provider = MockRateLimitProvider()
        let stream = await provider.stateStream()
        let expected = [100, 50, 1, 0, 100]

        let collector = Task { () -> [Int] in
            var received: [Int] = []
            for await state in stream {
                if case .available(let snapshot) = state {
                    received.append(snapshot.selected.remainingPercent)
                    if received.count == expected.count { break }
                }
            }
            return received
        }

        for percent in expected {
            await provider.send(percent: percent)
        }

        let received = await collector.value
        #expect(received == expected)
    }
}

private actor MockRateLimitProvider: RateLimitProvider {
    private var continuation: AsyncStream<QuotaState>.Continuation?

    func stateStream() -> AsyncStream<QuotaState> {
        AsyncStream { continuation in
            self.continuation = continuation
        }
    }

    func start() {}
    func refresh() {}

    func stop() {
        continuation?.finish()
    }

    func send(percent: Int) {
        let window = QuotaWindow(
            id: "mock",
            sourceID: "mock",
            sourceName: "Mock",
            kind: .primary,
            remainingPercent: percent,
            windowDurationMinutes: 300,
            resetsAt: Date().addingTimeInterval(3_600)
        )
        continuation?.yield(
            .available(QuotaSnapshot(selected: window, windows: [window], lastUpdated: Date()))
        )
    }
}
