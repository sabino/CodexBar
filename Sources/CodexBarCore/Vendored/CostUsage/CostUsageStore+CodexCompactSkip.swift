import Foundation

extension CostUsageStore {
    /// Performs the unchanged-content fast path without hydrating the raw event tables that
    /// compact scanner caches deliberately leave in SQLite. The optimistic comparison avoids
    /// taking a writer lock for changed scans; the second comparison under the lock preserves
    /// the same cross-process safety guarantees as the fully hydrated save path.
    func skipCompactSaveIfIdentical(
        _ cache: CostUsageCache,
        calendar: Calendar,
        budgetProtectionWindow: (sinceKey: String, untilKey: String),
        budgets: (rows: Int, fileBytes: Int64)) -> CostUsageStoreBudgetResult?
    {
        let previous = self.readCompactScannerSnapshot()
        guard Self.persistedContentMatches(
            previous: previous,
            cache: cache,
            calendar: calendar,
            rawDetailsHydrated: false)
        else { return nil }

        let result = self.enforceBudgets(
            maxRows: budgets.rows,
            maxFileBytes: budgets.fileBytes,
            requestedSinceDay: budgetProtectionWindow.sinceKey,
            requestedUntilDay: budgetProtectionWindow.untilKey,
            calendar: calendar)
        guard !result.catchUpRequired else { return result }
        Self.identicalContentPreLockCheckpointForTesting?()
        guard self.beginSaveTransaction() else {
            var retry = result
            retry.catchUpRequired = true
            return retry
        }

        let lockedPrevious = self.readCompactScannerSnapshotInCurrentTransaction()
        guard Self.persistedContentMatches(
            previous: lockedPrevious,
            cache: cache,
            calendar: calendar,
            rawDetailsHydrated: false)
        else {
            _ = self.rollbackSaveTransaction()
            var retry = result
            retry.catchUpRequired = true
            return retry
        }

        guard self.persistPriorityTurnsCursorIfChanged(previous: lockedPrevious, cache: cache) else {
            _ = self.rollbackSaveTransaction()
            var retry = result
            retry.catchUpRequired = true
            return retry
        }

        let advanced = self.advanceLastScanUnixMsInCurrentTransaction(cache.lastScanUnixMs)
        let committed = self.endSaveTransaction()
        guard advanced, committed else {
            var retry = result
            retry.catchUpRequired = true
            return retry
        }
        return result
    }
}
