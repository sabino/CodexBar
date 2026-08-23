import Foundation

// MARK: - Synchronous scanner bridge

struct CostUsageStoreLoad: @unchecked Sendable {
    var store: CostUsageStore
    var cache: CostUsageCache
}

enum CostUsageStoreAccess {
    static func load(cacheRoot: URL?, calendar: Calendar) -> CostUsageStoreLoad {
        let store = CostUsageStore(cacheRoot: cacheRoot)
        let cache = store.syncLoadCodexCache(calendar: calendar)
        return CostUsageStoreLoad(store: store, cache: cache)
    }

    static func loadForScan(cacheRoot: URL?, calendar: Calendar) -> CostUsageStoreLoad {
        let store = CostUsageStore(cacheRoot: cacheRoot)
        let cache = store.syncLoadCodexCacheForScan(calendar: calendar)
        return CostUsageStoreLoad(store: store, cache: cache)
    }

    static func hydrate(
        store: CostUsageStore,
        path: String,
        usage: CostUsageFileUsage) -> CostUsageFileUsage?
    {
        store.syncHydrateCodexUsage(path: path, usage: usage)
    }

    static func read(cacheRoot: URL?, calendar: Calendar = .current) -> CostUsageCache {
        self.load(cacheRoot: cacheRoot, calendar: calendar).cache
    }

    static func readAggregateReportCache(
        cacheRoot: URL?,
        calendar: Calendar,
        sinceDay: String,
        untilDay: String) -> CostUsageCache
    {
        // The dashboard reads bounded aggregate rows and fails soft on SQLite errors. Avoid a
        // full-file quick_check here: on large history stores it is orders of magnitude more
        // expensive than the report query itself. Scanner/writer opens retain full validation.
        let store = CostUsageStore(cacheRoot: cacheRoot, validatesIntegrityOnOpen: false)
        let report = store.syncReadReport(sinceDay: sinceDay, untilDay: untilDay)
        return CostUsageStore.aggregateReportCache(from: report, calendar: calendar)
    }

    static func readScanProgress(cacheRoot: URL?) -> CostUsageStoreScanProgress {
        CostUsageStore(cacheRoot: cacheRoot).syncReadScanProgress()
    }

    /// Test and maintenance mutation seam for metadata-only edits. Scanner writes should keep
    /// using the loaded store instance so one actor owns the full read/scan/write cycle.
    @discardableResult
    static func replace(
        cacheRoot: URL?,
        cache: CostUsageCache,
        calendar: Calendar = .current) -> CostUsageStoreBudgetResult
    {
        let loaded = self.load(cacheRoot: cacheRoot, calendar: calendar)
        let since = cache.scanSinceKey ?? "0000-01-01"
        let until = cache.scanUntilKey ?? "9999-12-31"
        return self.save(
            store: loaded.store,
            cache: cache,
            calendar: calendar,
            requestedScanWindow: (sinceKey: since, untilKey: until))
    }

    @discardableResult
    static func save(
        store: CostUsageStore,
        cache: CostUsageCache,
        calendar: Calendar,
        requestedScanWindow: (sinceKey: String, untilKey: String),
        reportWindow: (sinceKey: String, untilKey: String)? = nil,
        skipIdenticalContent: Bool = false) -> CostUsageStoreBudgetResult
    {
        store.syncSaveCodexCache(
            cache,
            calendar: calendar,
            requestedScanWindow: requestedScanWindow,
            reportWindow: reportWindow,
            skipIdenticalContent: skipIdenticalContent)
    }
}
