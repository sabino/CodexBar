import Foundation

extension CostUsageFetcher {
    static func codexScanCatchUpStatus(
        options: CostUsageScanner.Options) -> CodexScanCatchUpStatus
    {
        let rootsFingerprint = CostUsageScanner.codexRootsFingerprint(options: options)
        let progress = CostUsageStoreAccess.readScanProgress(cacheRoot: options.cacheRoot)
        guard progress.metadata.rootMtimes == rootsFingerprint else {
            return CodexScanCatchUpStatus(pending: false, progressKey: "scope-mismatch")
        }

        let pending = progress.metadata.catchUpPending
            || progress.incompleteFileCount > 0
            || progress.bufferedLineCount > 0
        let previousUpdatedAt = progress.metadata.previousReportPayload
            .flatMap { try? JSONDecoder().decode(CostUsageCodexPreviousReport.self, from: $0) }
            .flatMap(\.updatedAt)
        return CodexScanCatchUpStatus(
            pending: pending,
            progressKey: self.codexScanProgressKey(progress: progress),
            processedBytes: progress.metadata.processedBytes ?? progress.parsedBytes,
            totalBytes: progress.metadata.totalBytes ?? progress.sourceBytes,
            completedFiles: progress.metadata.completedFiles
                ?? max(0, progress.fileCount - progress.incompleteFileCount),
            totalFiles: progress.metadata.totalFiles ?? progress.fileCount,
            incompleteFiles: progress.incompleteFileCount,
            bufferedLines: progress.bufferedLineCount,
            revalidationActive: progress.lookbackState?.cacheWideMigrationQueueActive == true,
            staleSnapshotUpdatedAt: pending ? previousUpdatedAt : nil)
    }

    static func codexScanProgressKey(progress: CostUsageStoreScanProgress) -> String {
        var hasher = Hasher()
        hasher.combine(progress.metadata.processedBytes)
        hasher.combine(progress.metadata.totalBytes)
        hasher.combine(progress.metadata.completedFiles)
        hasher.combine(progress.metadata.totalFiles)
        hasher.combine(progress.fileCount)
        hasher.combine(progress.incompleteFileCount)
        hasher.combine(progress.parsedBytes)
        hasher.combine(progress.sourceBytes)
        hasher.combine(progress.bufferedLineCount)
        if let inventoryPaths = progress.metadata.scanInventoryPaths {
            hasher.combine("inventory")
            for path in inventoryPaths.sorted() {
                hasher.combine(path)
            }
        } else {
            hasher.combine("no-inventory")
        }
        // `updated_at_ms` changes whenever a stalled file is rewritten, even if no byte,
        // cursor, dependency, or buffered-line state advanced. It is deliberately absent
        // from this semantic key so an unresolved fork cannot make a manual refresh spin.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        hasher.combine(try? encoder.encode(progress.discoveryState))
        hasher.combine(try? encoder.encode(progress.lookbackState))
        return "v4:\(progress.fileCount):\(hasher.finalize())"
    }

    static func codexHistoryCoverageIsEstablished(
        options: CostUsageScanner.Options) -> Bool
    {
        let status = self.codexScanCatchUpStatus(options: options)
        return !status.pending && status.progressKey != "scope-mismatch"
    }
}
