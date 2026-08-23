import Foundation

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
        self.title = revalidationActive ? "HISTORY VERIFYING" : "PARTIAL INDEX"

        let dayWord = indexedDayCount == 1 ? "day" : "days"
        var clauses =
            ["Usage is indexed on \(indexedDayCount) \(dayWord) with activity\(Self.range(firstDay, lastDay))"]
        if incompleteFileCount > 0 {
            let fileWord = incompleteFileCount == 1 ? "session file is" : "session files are"
            clauses.append("\(incompleteFileCount) \(fileWord) still incomplete")
        }
        if bufferedLineCount > 0 {
            let lineWord = bufferedLineCount == 1 ? "line is" : "lines are"
            clauses.append("\(bufferedLineCount) deferred \(lineWord) awaiting reconciliation")
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
