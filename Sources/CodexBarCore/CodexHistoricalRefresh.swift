import Foundation

package enum CodexHistoricalRefreshError: LocalizedError, Equatable, Sendable {
    case noProgress
    case coverageNotEstablished

    package var errorDescription: String? {
        switch self {
        case .noProgress:
            "Historical refresh stopped because a bounded scanner pass made no progress."
        case .coverageNotEstablished:
            "Historical refresh finished without establishing complete history coverage."
        }
    }
}

/// Drives the original bounded Codex scanner until it has established complete coverage.
///
/// A stable snapshot load can discover a file that changed while catch-up was finishing. The
/// outer loop intentionally verifies scanner status after every stable load and resumes catch-up
/// when necessary. Unchanged files continue to come from the scanner's incremental cache.
package enum CodexHistoricalRefreshCoordinator {
    package typealias SnapshotLoader = @Sendable () async throws -> CostUsageTokenSnapshot
    package typealias StatusLoader = @Sendable () async -> CostUsageFetcher.CodexScanCatchUpStatus
    package typealias Advance = @Sendable () async throws -> CostUsageFetcher.CodexScanCatchUpStatus
    package typealias Progress = @Sendable (CostUsageFetcher.CodexScanCatchUpStatus) async -> Void
    package typealias InterPassPause = @Sendable () async throws -> Void

    package static func run(
        loadSnapshot: @escaping SnapshotLoader,
        loadStatus: @escaping StatusLoader,
        advance: @escaping Advance,
        progress: @escaping Progress = { _ in },
        interPassPause: @escaping InterPassPause = {}) async throws -> CostUsageTokenSnapshot
    {
        while true {
            try Task.checkCancellation()
            let snapshot = try await loadSnapshot()
            var status = await loadStatus()
            await progress(status)

            guard status.pending else {
                guard snapshot.historyCoverageIsEstablished else {
                    throw CodexHistoricalRefreshError.coverageNotEstablished
                }
                return snapshot
            }

            var seenProgressKeys: Set<String> = [status.progressKey]
            while status.pending {
                try Task.checkCancellation()
                try await interPassPause()
                let nextStatus = try await advance()
                await progress(nextStatus)
                if nextStatus.pending,
                   !seenProgressKeys.insert(nextStatus.progressKey).inserted
                {
                    throw CodexHistoricalRefreshError.noProgress
                }
                status = nextStatus
            }

            // Load the final stable report, then verify that publishing it did not uncover
            // fresh tail work. This mirrors UsageStore's original catch-up outer loop.
        }
    }
}

extension CostUsageFetcher {
    /// Manual Refresh may consume a core continuously, but still checkpoints often
    /// enough to keep cancellation responsive and publish meaningful UI progress.
    private static let codexManualScanDurationPerRefresh: TimeInterval = 8

    package func refreshCodexHistoryToCompletion(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        codexHomePath: String? = nil,
        historyDays: Int = 365,
        allowPricingRefresh: Bool = true,
        refreshPricingInBackground: Bool = false,
        includePiSessions: Bool = true,
        calendar: Calendar? = nil,
        progress: @escaping CodexHistoricalRefreshCoordinator.Progress = { _ in })
        async throws -> CostUsageTokenSnapshot
    {
        let fetcher = self
        return try await CodexHistoricalRefreshCoordinator.run(
            loadSnapshot: {
                try await fetcher.loadTokenSnapshot(
                    provider: .codex,
                    environment: environment,
                    now: Date(),
                    forceRefresh: true,
                    codexHomePath: codexHomePath,
                    historyDays: historyDays,
                    allowPricingRefresh: allowPricingRefresh,
                    refreshPricingInBackground: refreshPricingInBackground,
                    includePiSessions: includePiSessions,
                    includeProjectAndSessionBreakdowns: false,
                    bypassScannerDebounce: true,
                    calendar: calendar)
            },
            loadStatus: {
                await fetcher.codexScanCatchUpStatus(
                    codexHomePath: codexHomePath,
                    calendar: calendar)
            },
            advance: {
                try await fetcher.advanceCodexScanCatchUp(
                    now: Date(),
                    codexHomePath: codexHomePath,
                    historyDays: historyDays,
                    maximumScanDurationPerRefresh: Self.codexManualScanDurationPerRefresh,
                    renewScanDurationBeforeFileWork: true,
                    calendar: calendar)
            },
            progress: progress)
    }
}
