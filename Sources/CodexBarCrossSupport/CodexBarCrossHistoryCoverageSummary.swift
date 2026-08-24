import Foundation

public enum CodexBarCrossHistoryCoveragePolicy {
    public static func shouldShow(
        coverageEstablished: Bool,
        indexedDayCount: Int,
        catchUpStatusAvailable: Bool,
        catchUpPending: Bool)
        -> Bool
    {
        !coverageEstablished
            && indexedDayCount > 0
            && catchUpStatusAvailable
            && catchUpPending
    }
}

public struct CodexBarCrossHistoryCoverageSummary: Equatable, Sendable {
    public let title: String
    public let message: String

    public init(
        indexedDayCount: Int,
        firstDay: String?,
        lastDay: String?,
        incompleteFileCount: Int,
        bufferedLineCount: Int,
        revalidationActive: Bool)
    {
        self.title = revalidationActive ? "HISTORY VERIFYING" : "PARTIAL HISTORY"

        let dayWord = indexedDayCount == 1 ? "day" : "days"
        var clauses =
            ["Usage is indexed on \(indexedDayCount) \(dayWord) with activity\(Self.range(firstDay, lastDay))"]
        if incompleteFileCount > 0 {
            let recordWord = incompleteFileCount == 1 ? "session record could" : "session records could"
            clauses.append("\(incompleteFileCount) \(recordWord) not be finalized")
        }
        if bufferedLineCount > 0 {
            let lineWord = bufferedLineCount == 1 ? "line is" : "lines are"
            clauses.append("\(bufferedLineCount) deferred \(lineWord) held for exact lineage reconciliation")
        }
        if revalidationActive {
            clauses.append("Cached file metadata verification is continuing in the background")
        }
        self.message = clauses.joined(separator: ". ") + "."
    }

    private static func range(_ firstDay: String?, _ lastDay: String?) -> String {
        guard let firstDay, let lastDay else { return "" }
        if firstDay == lastDay {
            return " (\(firstDay))"
        }
        return ", spanning \(firstDay) through \(lastDay)"
    }
}

public enum CodexBarCrossHistoricalRefreshFailureSummary {
    public static func noProgress(incompleteFileCount: Int, bufferedLineCount: Int) -> String {
        var message = "Full local history was scanned"
        if incompleteFileCount > 0 {
            let recordWord = incompleteFileCount == 1 ? "session record remains" : "session records remain"
            let reason = incompleteFileCount == 1
                ? "its log is incomplete or references unavailable parent lineage"
                : "their logs are incomplete or reference unavailable parent lineage"
            message += ". \(incompleteFileCount) \(recordWord) unresolved because \(reason)"
        } else {
            message += ", but unresolved scanner state remains"
        }
        if bufferedLineCount > 0 {
            let lineWord = bufferedLineCount == 1 ? "line remains" : "lines remain"
            message += ". \(bufferedLineCount) deferred \(lineWord) fail-closed instead of being estimated"
        }
        return message + "."
    }
}
