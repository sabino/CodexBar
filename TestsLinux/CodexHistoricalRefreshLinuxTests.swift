import Foundation
import Testing
@testable import CodexBarCore

struct CodexHistoricalRefreshLinuxTests {
    @Test
    func `manual file work renews an expired idle scanner window`() {
        let clock = CodexHistoricalRefreshTestClock()
        let budget = CostUsageScanner.CodexScanBudget(
            maxFileBytes: 100,
            maxBytesPerRefresh: 150,
            maxDuration: 2,
            now: { clock.now() })

        clock.advance(by: .seconds(3))
        #expect(budget.shouldStopBeforeNextFile())

        budget.renewDurationBeforeFileWorkIfIdle()
        #expect(!budget.shouldStopBeforeNextFile())

        clock.advance(by: .seconds(3))
        #expect(!budget.shouldStopBeforeNextFile())
        guard case let .allow(work) = budget.admit(workBytes: 100) else {
            Issue.record("expected renewed file work to be admitted")
            return
        }
        budget.consume(workBytes: work)

        #expect(budget.shouldStopBeforeNextFile())
    }

    private actor RefreshScript {
        var snapshotLoads = 0
        var statusLoads = 0
        var advances = 0
        var progressKeys: [String] = []

        func loadSnapshot() -> CostUsageTokenSnapshot {
            self.snapshotLoads += 1
            return Self.snapshot(coverageEstablished: self.snapshotLoads >= 2)
        }

        func loadStatus() -> CostUsageFetcher.CodexScanCatchUpStatus {
            self.statusLoads += 1
            return CostUsageFetcher.CodexScanCatchUpStatus(
                pending: self.statusLoads == 1,
                progressKey: "status-\(self.statusLoads)")
        }

        func advance() -> CostUsageFetcher.CodexScanCatchUpStatus {
            self.advances += 1
            return CostUsageFetcher.CodexScanCatchUpStatus(
                pending: self.advances < 2,
                progressKey: "advance-\(self.advances)")
        }

        func recordProgress(_ status: CostUsageFetcher.CodexScanCatchUpStatus) {
            self.progressKeys.append(status.progressKey)
        }

        func counts() -> (snapshotLoads: Int, statusLoads: Int, advances: Int, progressKeys: [String]) {
            (self.snapshotLoads, self.statusLoads, self.advances, self.progressKeys)
        }

        static func snapshot(coverageEstablished: Bool) -> CostUsageTokenSnapshot {
            CostUsageTokenSnapshot(
                sessionTokens: nil,
                sessionCostUSD: nil,
                last30DaysTokens: nil,
                last30DaysCostUSD: nil,
                historyDays: 365,
                historyCoverageIsEstablished: coverageEstablished,
                daily: [],
                updatedAt: Date(timeIntervalSince1970: 0))
        }
    }

    @Test
    func `manual refresh drains every bounded pass and publishes a verified stable snapshot`() async throws {
        let script = RefreshScript()

        let snapshot = try await CodexHistoricalRefreshCoordinator.run(
            loadSnapshot: { await script.loadSnapshot() },
            loadStatus: { await script.loadStatus() },
            advance: { await script.advance() },
            progress: { await script.recordProgress($0) })

        let counts = await script.counts()
        #expect(snapshot.historyCoverageIsEstablished)
        #expect(counts.snapshotLoads == 2)
        #expect(counts.statusLoads == 2)
        #expect(counts.advances == 2)
        #expect(counts.progressKeys == ["status-1", "advance-1", "advance-2", "status-2"])
    }

    @Test
    func `manual refresh fails instead of pretending completion after no progress`() async {
        let pending = CostUsageFetcher.CodexScanCatchUpStatus(
            pending: true,
            progressKey: "unchanged")
        let snapshot = RefreshScript.snapshot(coverageEstablished: false)

        await #expect(throws: CodexHistoricalRefreshError.noProgress) {
            try await CodexHistoricalRefreshCoordinator.run(
                loadSnapshot: { snapshot },
                loadStatus: { pending },
                advance: { pending })
        }
    }
}

private final class CodexHistoricalRefreshTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private let origin = ContinuousClock.now
    private var offset = Duration.zero

    func now() -> ContinuousClock.Instant {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.origin.advanced(by: self.offset)
    }

    func advance(by duration: Duration) {
        self.lock.lock()
        self.offset += duration
        self.lock.unlock()
    }
}
