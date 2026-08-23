import CodexBarCrossSupport
import Testing

struct CodexBarCrossHistoryCoverageSummaryTests {
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
        #expect(summary.message.contains("5 session files are still incomplete"))
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

        #expect(summary.title == "PARTIAL INDEX")
        #expect(summary.message == "Usage is indexed on 1 day with activity (2026-08-23). "
            + "1 session file is still incomplete.")
    }
}
