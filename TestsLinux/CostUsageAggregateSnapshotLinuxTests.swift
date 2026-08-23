import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CostUsageAggregateSnapshotLinuxTests {
    @Test
    func `partial dashboard mode exposes indexed rows without changing strict coverage semantics`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 8,
            day: 21,
            hour: 12)))
        let entry = CostUsageDailyReport.Entry(
            date: "2026-08-20",
            inputTokens: 120,
            outputTokens: 30,
            totalTokens: 150,
            costUSD: 1.25,
            modelsUsed: ["gpt-5"],
            modelBreakdowns: [.init(modelName: "gpt-5", costUSD: 1.25, totalTokens: 150)])
        let snapshot = CostUsageTokenSnapshot(
            sessionTokens: 150,
            sessionCostUSD: 1.25,
            last30DaysTokens: 150,
            last30DaysCostUSD: 1.25,
            historyDays: 365,
            historyCoverageIsEstablished: false,
            costProvenance: .listPriceEstimate,
            daily: [entry],
            updatedAt: now)
        let strictDashboard = SpendDashboardModel.build(
            inputs: [.init(provider: .codex, displayName: "Codex", snapshot: snapshot)],
            requestedDays: 365,
            now: now,
            calendar: calendar)
        let partialDashboard = SpendDashboardModel.build(
            inputs: [.init(
                provider: .codex,
                displayName: "Codex",
                snapshot: snapshot,
                includesIndexedPartialHistory: true)],
            requestedDays: 365,
            now: now,
            calendar: calendar)

        #expect(strictDashboard.groups.first?.dailyPoints.isEmpty == true)
        #expect(strictDashboard.groups.first?.totalTokens == nil)
        #expect(partialDashboard.groups.first?.dailyPoints.count == 1)
        #expect(partialDashboard.groups.first?.totalTokens == 150)
        #expect(partialDashboard.groups.first?.totalCost == 1.25)
    }

    @Test
    func `aggregate dashboard read preserves original daily report without hydrating session details`() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBar-AggregateSnapshot-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026,
            month: 8,
            day: 21,
            hour: 12)))
        var options = CostUsageScanner.Options()
        options.cacheRoot = root
        options.calendar = calendar
        let roots = CostUsageScanner.codexRootsFingerprint(options: options)
        let sessionRoot = roots.keys.sorted().first ?? "/tmp/codexbar-sessions"
        let day = "2026-08-20"
        let model = "gpt-5"
        let rows = [CostUsageScanner.CodexUsageRow(
            day: day,
            model: model,
            turnID: "turn-1",
            eventIndex: 0,
            input: 120,
            cached: 20,
            output: 30,
            reasoning: 10,
            pricingModel: model,
            pricingMode: "standard")]
        let tokenSnapshots = [CostUsageCodexTokenSnapshot(
            timestamp: "2026-08-20T12:00:00Z",
            last: CostUsageCodexTotals(input: 120, cached: 20, output: 30, reasoning: 10),
            total: CostUsageCodexTotals(input: 120, cached: 20, output: 30, reasoning: 10),
            endOffset: 512)]
        let usage = CostUsageScanner.makeFileUsage(
            mtimeUnixMs: Int64(now.timeIntervalSince1970 * 1000),
            size: 512,
            days: [day: [model: [120, 20, 30]]],
            parsedBytes: 512,
            codexCostCacheComplete: true,
            codexStandardTokens: [day: [model: 150]],
            codexRows: rows,
            codexTokenSnapshots: tokenSnapshots,
            codexTokenCheckpoints: CostUsageScanner.codexTokenCheckpoints(for: tokenSnapshots),
            codexScanComplete: true)
        let since = try #require(calendar.date(byAdding: .day, value: -6, to: now))
        let range = CostUsageScanner.CostUsageDayRange(since: since, until: now, calendar: calendar)
        var cache = CostUsageCache()
        cache.lastScanUnixMs = Int64(now.timeIntervalSince1970 * 1000)
        cache.scanSinceKey = range.scanSinceKey
        cache.scanUntilKey = range.scanUntilKey
        cache.timeZoneIdentifier = calendar.timeZone.identifier
        cache.codexScanCatchUpPending = false
        cache.codexScanCompletedFiles = 1
        cache.codexScanTotalFiles = 1
        cache.files[sessionRoot + "/aggregate-fixture.jsonl"] = usage
        cache.days = usage.days
        cache.roots = roots
        _ = CostUsageStoreAccess.replace(cacheRoot: root, cache: cache, calendar: calendar)

        let compactLoad = CostUsageStoreAccess.loadForScan(cacheRoot: root, calendar: calendar)
        let path = sessionRoot + "/aggregate-fixture.jsonl"
        let compactUsage = try #require(compactLoad.cache.files[path])
        #expect(compactUsage.codexLazyStorageState?.rowsHydrated == false)
        #expect(compactUsage.codexLazyStorageState?.tokenSnapshotsHydrated == false)
        #expect(compactUsage.codexTokenSnapshots == nil)
        #expect(compactUsage.codexRows?.isEmpty == false)

        _ = CostUsageStoreAccess.save(
            store: compactLoad.store,
            cache: compactLoad.cache,
            calendar: calendar,
            requestedScanWindow: (range.scanSinceKey, range.scanUntilKey))
        let preserved = CostUsageStoreAccess.read(cacheRoot: root, calendar: calendar)
        #expect(preserved.files[path]?.codexRows == rows)
        #expect(preserved.files[path]?.codexTokenSnapshots == tokenSnapshots)

        let secondCompactLoad = CostUsageStoreAccess.loadForScan(cacheRoot: root, calendar: calendar)
        let secondCompactUsage = try #require(secondCompactLoad.cache.files[path])
        let hydrated = try #require(CostUsageStoreAccess.hydrate(
            store: secondCompactLoad.store,
            path: path,
            usage: secondCompactUsage))
        #expect(hydrated.codexLazyStorageState?.rowsHydrated == true)
        #expect(hydrated.codexRows == rows)
        #expect(hydrated.codexTokenSnapshots == tokenSnapshots)

        let persisted = await CostUsageStore(cacheRoot: root).readReport(
            sinceDay: "2026-08-15",
            untilDay: "2026-08-21")
        #expect(persisted.metadata.lastScanUnixMs == cache.lastScanUnixMs)
        #expect(persisted.metadata.rootMtimes == roots)
        #expect(persisted.aggregates.count == 1)
        let loaded = CostUsageStoreAccess.read(cacheRoot: root, calendar: calendar)
        #expect(loaded.days[day]?[model] == [120, 20, 30])
        #expect(loaded.timeZoneIdentifier == range.calendar.timeZone.identifier)
        #expect(loaded.roots == roots)
        #expect(!CostUsageScanner.requestedWindowExpandsCache(range: range, cache: loaded))
        #expect(!CostUsageScanner.buildCodexReportFromCache(cache: loaded, range: range).data.isEmpty)

        let full = await CostUsageFetcher.loadCachedCodexTokenSnapshot(
            now: now,
            historyDays: 7,
            includePiSessions: false,
            includeProjectAndSessionBreakdowns: true,
            scannerOptions: options)
        let aggregate = await CostUsageFetcher.loadCachedCodexTokenSnapshot(
            now: now,
            historyDays: 7,
            includePiSessions: false,
            includeProjectAndSessionBreakdowns: false,
            scannerOptions: options)

        #expect(full != nil)
        #expect(aggregate != nil)
        #expect(aggregate?.daily == full?.daily)
        #expect(aggregate?.last30DaysTokens == 150)
        #expect(aggregate?.daily.first?.modelBreakdowns?.first?.modelName == model)
        #expect(aggregate?.historyCoverageIsEstablished == true)
    }

    @Test
    func `compact progress read detects pending files and advances its semantic key`() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBar-CompactProgress-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CostUsageStore(cacheRoot: root)
        let first = Self.file(path: "/sessions/incomplete.jsonl", parsedBytes: 128)
        #expect(await store.upsertFile(first))

        let initial = await store.readScanProgress()
        #expect(initial.fileCount == 1)
        #expect(initial.incompleteFileCount == 1)
        #expect(initial.parsedBytes == 128)

        var advanced = first
        advanced.parsedBytes = 256
        advanced.updatedAtUnixMs += 1
        #expect(await store.upsertFile(advanced))
        let next = await store.readScanProgress()
        #expect(next.parsedBytes == 256)
        #expect(next.latestFileUpdateUnixMs > initial.latestFileUpdateUnixMs)
    }

    @Test
    func `lazy scanner adopts the current upstream cache without rebuilding`() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexBar-UpstreamCacheAdoption-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let predecessorHash = "99848ef16ca7e069"
        #expect(CostUsageStore.compatiblePredecessorParserHashes.contains(predecessorHash))
        let predecessorVersion = CostUsageStore.combinedSchemaVersion(
            base: CostUsageStore.baseSchemaVersion,
            parserHash: predecessorHash)
        let predecessor = CostUsageStore(
            cacheRoot: root,
            schemaVersion: predecessorVersion,
            parserHash: predecessorHash)
        let file = Self.file(path: "/sessions/upstream-cache.jsonl", parsedBytes: 512)
        let aggregate = CostUsageStoreDayAggregate(
            day: "2026-08-20",
            model: "gpt-5",
            inputTokens: 120,
            cachedTokens: 20,
            outputTokens: 30,
            reasoningTokens: 10,
            requestCount: 1,
            authoritativeCostNanos: 0,
            standardInputTokens: 120,
            standardCachedTokens: 20,
            standardOutputTokens: 30,
            priorityInputTokens: 0,
            priorityCachedTokens: 0,
            priorityOutputTokens: 0,
            standardTokens: 150,
            priorityTokens: 0)
        #expect(await predecessor.upsertFile(file))
        #expect(await predecessor.mergeDayAggregates([aggregate]))
        let before = await predecessor.readSnapshot()

        let current = CostUsageStore(cacheRoot: root)
        let after = await current.readSnapshot()
        #expect(after == before)
        #expect(await current.rebuildCount == 0)
        #expect(await current.configuration()?.userVersion == Int(CostUsageStore.schemaVersion))
    }

    private static func file(path: String, parsedBytes: Int64) -> CostUsageStoreFile {
        CostUsageStoreFile(
            path: path,
            inode: nil,
            mtimeUnixMs: 1,
            size: 512,
            parsedBytes: parsedBytes,
            anchor: nil,
            scanState: CostUsageStoreScanState(
                targetSize: 512,
                isComplete: false,
                resumePayload: nil,
                tokenTimestampsMonotonic: true,
                nextUsageRowIndex: nil,
                lastModel: nil,
                lastTurnID: nil,
                fileIdentity: nil,
                detailsPayload: nil),
            sessionID: nil,
            coverageSinceDay: "2026-08-01",
            coverageUntilDay: "2026-08-21",
            updatedAtUnixMs: parsedBytes)
    }
}
