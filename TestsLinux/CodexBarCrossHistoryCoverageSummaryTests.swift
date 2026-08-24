import CodexBarCrossSupport
import Testing

struct CodexBarCrossHistoryCoverageSummaryTests {
    @Test
    func `partial banner requires a current pending scanner status`() {
        #expect(!CodexBarCrossHistoryCoveragePolicy.shouldShow(
            coverageEstablished: false,
            indexedDayCount: 240,
            catchUpStatusAvailable: false,
            catchUpPending: false))
        #expect(!CodexBarCrossHistoryCoveragePolicy.shouldShow(
            coverageEstablished: false,
            indexedDayCount: 240,
            catchUpStatusAvailable: true,
            catchUpPending: false))
        #expect(CodexBarCrossHistoryCoveragePolicy.shouldShow(
            coverageEstablished: false,
            indexedDayCount: 240,
            catchUpStatusAvailable: true,
            catchUpPending: true))
    }

    @Test
    func `partial banner stays hidden for complete or empty history`() {
        #expect(!CodexBarCrossHistoryCoveragePolicy.shouldShow(
            coverageEstablished: true,
            indexedDayCount: 240,
            catchUpStatusAvailable: true,
            catchUpPending: true))
        #expect(!CodexBarCrossHistoryCoveragePolicy.shouldShow(
            coverageEstablished: false,
            indexedDayCount: 0,
            catchUpStatusAvailable: true,
            catchUpPending: true))
    }

    @Test
    func `verification summary distinguishes active usage days from pending files`() {
        let summary = CodexBarCrossHistoryCoverageSummary(
            indexedDayCount: 240,
            firstDay: "2025-11-05",
            lastDay: "2026-08-23",
            incompleteFileCount: 5,
            bufferedLineCount: 479,
            revalidationActive: true)

        #expect(summary.title == "HISTORY VERIFYING")
        #expect(summary.message.contains("240 days with activity, spanning 2025-11-05 through 2026-08-23"))
        #expect(summary.message.contains("5 session records could not be finalized"))
        #expect(summary.message.contains("Cached file metadata verification"))
    }

    @Test
    func `partial summary handles a single indexed day`() {
        let summary = CodexBarCrossHistoryCoverageSummary(
            indexedDayCount: 1,
            firstDay: "2026-08-23",
            lastDay: "2026-08-23",
            incompleteFileCount: 1,
            bufferedLineCount: 0,
            revalidationActive: false)

        #expect(summary.title == "PARTIAL HISTORY")
        #expect(summary.message == "Usage is indexed on 1 day with activity (2026-08-23). "
            + "1 session record could not be finalized.")
    }

    @Test
    func `stalled full refresh explains fail closed session lineage`() {
        let message = CodexBarCrossHistoricalRefreshFailureSummary.noProgress(
            incompleteFileCount: 4,
            bufferedLineCount: 479)

        #expect(message == "Full local history was scanned. 4 session records remain unresolved because "
            + "their logs are incomplete or reference unavailable parent lineage. "
            + "479 deferred lines remain fail-closed instead of being estimated.")
    }
}
