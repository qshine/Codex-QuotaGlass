import Foundation

public enum QuotaWindowKind: String, Codable, Sendable, CaseIterable {
    case primary
    case secondary
    case individual

    public var tieBreakRank: Int {
        switch self {
        case .primary: 0
        case .secondary: 1
        case .individual: 2
        }
    }
}

public struct QuotaWindow: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let sourceID: String
    public let sourceName: String
    public let kind: QuotaWindowKind
    public let remainingPercent: Int
    public let windowDurationMinutes: Int?
    public let resetsAt: Date?

    public init(
        id: String,
        sourceID: String,
        sourceName: String,
        kind: QuotaWindowKind,
        remainingPercent: Int,
        windowDurationMinutes: Int?,
        resetsAt: Date?
    ) {
        self.id = id
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.kind = kind
        self.remainingPercent = Self.clamp(remainingPercent)
        self.windowDurationMinutes = windowDurationMinutes
        self.resetsAt = resetsAt
    }

    public var displayName: String {
        if kind == .individual {
            return sourceName.isEmpty ? "个人额度" : "\(sourceName) · 个人额度"
        }

        guard let minutes = windowDurationMinutes else {
            return sourceName.isEmpty ? "使用额度" : sourceName
        }

        let window: String
        if minutes % 10_080 == 0 {
            window = "\(minutes / 10_080)周额度"
        } else if minutes % 1_440 == 0 {
            window = "\(minutes / 1_440)天额度"
        } else if minutes % 60 == 0 {
            window = "\(minutes / 60)小时额度"
        } else {
            window = "\(minutes)分钟额度"
        }
        return sourceName.isEmpty ? window : "\(sourceName) · \(window)"
    }

    public static func clamp(_ value: Int) -> Int {
        min(max(value, 0), 100)
    }
}

public struct QuotaSnapshot: Equatable, Sendable {
    public let selected: QuotaWindow
    public let windows: [QuotaWindow]
    public let lastUpdated: Date

    public init(selected: QuotaWindow, windows: [QuotaWindow], lastUpdated: Date) {
        self.selected = selected
        self.windows = windows
        self.lastUpdated = lastUpdated
    }

    public func isStale(at date: Date, threshold: TimeInterval = 60) -> Bool {
        date.timeIntervalSince(lastUpdated) > threshold
    }
}

public enum QuotaState: Equatable, Sendable {
    case loading
    case available(QuotaSnapshot)
    case stale(QuotaSnapshot)
    case clientMissing
    case loginRequired(String?)
    case unsupportedVersion(String?)
    case unavailable(String)

    public var snapshot: QuotaSnapshot? {
        switch self {
        case .available(let snapshot), .stale(let snapshot): snapshot
        default: nil
        }
    }
}

public protocol RateLimitProvider: Sendable {
    func stateStream() async -> AsyncStream<QuotaState>
    func start() async
    func refresh() async
    func stop() async
}

public enum ReconnectBackoff {
    public static let delaySeconds = [1, 2, 5, 10, 30, 60]

    public static func delay(forAttempt attempt: Int) -> Int {
        delaySeconds[min(max(attempt, 0), delaySeconds.count - 1)]
    }
}
