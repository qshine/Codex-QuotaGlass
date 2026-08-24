import Foundation

public enum QuotaMapper {
    public static func windows(from result: RateLimitReadResult) -> [QuotaWindow] {
        let buckets: [(String, RateLimitSnapshotPayload)]

        if let byID = result.rateLimitsByLimitID, !byID.isEmpty {
            buckets = byID.keys.sorted().compactMap { key in
                byID[key].map { (key, $0) }
            }
        } else if let legacy = result.rateLimits {
            buckets = [(legacy.limitID ?? "codex", legacy)]
        } else {
            buckets = []
        }

        return buckets.flatMap { bucketID, snapshot in
            makeWindows(bucketID: bucketID, snapshot: snapshot)
        }
    }

    public static func selectMostConstrained(from windows: [QuotaWindow]) -> QuotaWindow? {
        windows.min { lhs, rhs in
            if lhs.remainingPercent != rhs.remainingPercent {
                return lhs.remainingPercent < rhs.remainingPercent
            }

            let lhsReset = lhs.resetsAt?.timeIntervalSince1970 ?? -.infinity
            let rhsReset = rhs.resetsAt?.timeIntervalSince1970 ?? -.infinity
            if lhsReset != rhsReset {
                return lhsReset > rhsReset
            }

            if lhs.kind.tieBreakRank != rhs.kind.tieBreakRank {
                return lhs.kind.tieBreakRank < rhs.kind.tieBreakRank
            }

            return lhs.id < rhs.id
        }
    }

    public static func snapshot(
        from result: RateLimitReadResult,
        updatedAt: Date = Date()
    ) -> QuotaSnapshot? {
        let allWindows = windows(from: result)
        guard let selected = selectMostConstrained(from: allWindows) else { return nil }
        return QuotaSnapshot(selected: selected, windows: allWindows, lastUpdated: updatedAt)
    }

    private static func makeWindows(
        bucketID: String,
        snapshot: RateLimitSnapshotPayload
    ) -> [QuotaWindow] {
        let sourceID = snapshot.limitID ?? bucketID
        let sourceName = snapshot.limitName ?? sourceID.capitalized
        var windows: [QuotaWindow] = []

        if let primary = snapshot.primary {
            windows.append(
                makeRateWindow(
                    payload: primary,
                    bucketID: bucketID,
                    sourceID: sourceID,
                    sourceName: sourceName,
                    kind: .primary
                )
            )
        }

        if let secondary = snapshot.secondary {
            windows.append(
                makeRateWindow(
                    payload: secondary,
                    bucketID: bucketID,
                    sourceID: sourceID,
                    sourceName: sourceName,
                    kind: .secondary
                )
            )
        }

        if let individual = snapshot.individualLimit {
            windows.append(
                QuotaWindow(
                    id: "\(bucketID)-individual",
                    sourceID: sourceID,
                    sourceName: sourceName,
                    kind: .individual,
                    remainingPercent: individual.remainingPercent,
                    windowDurationMinutes: nil,
                    resetsAt: Date(timeIntervalSince1970: TimeInterval(individual.resetsAt))
                )
            )
        }

        return windows
    }

    private static func makeRateWindow(
        payload: RateLimitWindowPayload,
        bucketID: String,
        sourceID: String,
        sourceName: String,
        kind: QuotaWindowKind
    ) -> QuotaWindow {
        QuotaWindow(
            id: "\(bucketID)-\(kind.rawValue)",
            sourceID: sourceID,
            sourceName: sourceName,
            kind: kind,
            remainingPercent: 100 - payload.usedPercent,
            windowDurationMinutes: payload.windowDurationMins,
            resetsAt: payload.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        )
    }
}
