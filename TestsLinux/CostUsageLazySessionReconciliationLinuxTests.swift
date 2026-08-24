import Foundation
import Testing
@testable import CodexBarCore

@Suite(.serialized)
struct CostUsageLazySessionReconciliationLinuxTests {
    private struct Environment {
        let root: URL
        let cacheRoot: URL
        let sessionsRoot: URL
        let archivedSessionsRoot: URL

        init() throws {
            self.root = FileManager.default.temporaryDirectory
                .appendingPathComponent("codexbar-lazy-session-\(UUID().uuidString)", isDirectory: true)
            self.cacheRoot = self.root.appendingPathComponent("cache", isDirectory: true)
            self.sessionsRoot = self.root.appendingPathComponent("sessions", isDirectory: true)
            self.archivedSessionsRoot = self.root.appendingPathComponent("archived_sessions", isDirectory: true)
            try FileManager.default.createDirectory(at: self.cacheRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: self.sessionsRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: self.archivedSessionsRoot, withIntermediateDirectories: true)
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: self.root)
        }

        func localNoon(year: Int, month: Int, day: Int) throws -> Date {
            var components = DateComponents()
            components.calendar = Calendar.current
            components.timeZone = TimeZone.current
            components.year = year
            components.month = month
            components.day = day
            components.hour = 12
            guard let date = components.date else {
                throw NSError(domain: "CostUsageLazySessionReconciliationLinuxTests", code: 1)
            }
            return date
        }

        func isoString(for date: Date) -> String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            return formatter.string(from: date)
        }

        func jsonl(_ objects: [[String: Any]]) throws -> String {
            try objects
                .map { try String(decoding: JSONSerialization.data(withJSONObject: $0), as: UTF8.self) }
                .joined(separator: "\n") + "\n"
        }

        @discardableResult
        func writeSession(day: Date, filename: String, contents: String) throws -> URL {
            let components = Calendar.current.dateComponents([.year, .month, .day], from: day)
            let directory = self.sessionsRoot
                .appendingPathComponent(String(format: "%04d", components.year ?? 1970), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", components.month ?? 1), isDirectory: true)
                .appendingPathComponent(String(format: "%02d", components.day ?? 1), isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appendingPathComponent(filename)
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        }

        @discardableResult
        func writeArchived(filename: String, contents: String) throws -> URL {
            let fileURL = self.archivedSessionsRoot.appendingPathComponent(filename)
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        }
    }

    private static let model = "openai/gpt-5.5"

    private static func sessionMeta(id: String) -> [String: Any] {
        ["type": "session_meta", "payload": ["session_id": id]]
    }

    private static func turnContext(timestamp: String) -> [String: Any] {
        ["type": "turn_context", "timestamp": timestamp, "payload": ["model": self.model]]
    }

    private static func taskStarted(timestamp: String, turnID: String) -> [String: Any] {
        [
            "type": "event_msg",
            "timestamp": timestamp,
            "payload": ["type": "task_started", "turn_id": turnID],
        ]
    }

    private static func tokenCount(timestamp: String, input: Int, output: Int) -> [String: Any] {
        [
            "type": "event_msg",
            "timestamp": timestamp,
            "payload": [
                "type": "token_count",
                "info": [
                    "model": self.model,
                    "last_token_usage": [
                        "input_tokens": input,
                        "cached_input_tokens": 0,
                        "output_tokens": output,
                    ],
                ],
            ],
        ]
    }

    private static func options(for env: Environment) -> CostUsageScanner.Options {
        var options = CostUsageScanner.Options(
            codexSessionsRoot: env.sessionsRoot,
            claudeProjectsRoots: nil,
            cacheRoot: env.cacheRoot,
            codexTraceDatabaseURL: env.root.appendingPathComponent("missing.sqlite"))
        options.refreshMinIntervalSeconds = 0
        return options
    }

    @Test
    func `warm active archive reconciliation does not inflate repeated totals`() throws {
        let env = try Environment()
        defer { env.cleanup() }

        let day = try env.localNoon(year: 2026, month: 6, day: 27)
        let iso0 = env.isoString(for: day)
        let iso1 = env.isoString(for: day.addingTimeInterval(1))
        let iso2 = env.isoString(for: day.addingTimeInterval(2))
        let sessionID = "sess-identical-delta-active-archive"
        let common = [
            Self.sessionMeta(id: sessionID),
            Self.turnContext(timestamp: iso0),
            Self.taskStarted(timestamp: iso1, turnID: "turn-a"),
            Self.tokenCount(timestamp: iso1, input: 20, output: 5),
        ]
        try env.writeSession(
            day: day,
            filename: "active-identical-delta.jsonl",
            contents: env.jsonl(common))
        let dayKey = CostUsageScanner.CostUsageDayRange.dayKey(from: day)
        try env.writeArchived(
            filename: "rollout-\(dayKey)T12-00-00-identical-delta.jsonl",
            contents: env.jsonl(common + [Self.tokenCount(timestamp: iso2, input: 20, output: 5)]))

        let options = Self.options(for: env)
        let first = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day,
            options: options)
        let repeated = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day.addingTimeInterval(1),
            options: options)

        #expect(first.data.first?.inputTokens == 40)
        #expect(first.data.first?.outputTokens == 10)
        #expect(first.data.first?.totalTokens == 50)
        #expect(repeated.data.first?.inputTokens == 40)
        #expect(repeated.data.first?.outputTokens == 10)
        #expect(repeated.data.first?.totalTokens == 50)
    }

    @Test
    func `unrelated new file does not bypass bounded pending queue order`() throws {
        let env = try Environment()
        defer { env.cleanup() }

        let day = try env.localNoon(year: 2026, month: 5, day: 10)
        let iso = env.isoString(for: day)
        let cachedURL = try env.writeSession(
            day: day,
            filename: "a-cached.jsonl",
            contents: env.jsonl([
                Self.sessionMeta(id: "cached"),
                Self.turnContext(timestamp: iso),
                Self.tokenCount(timestamp: iso, input: 100, output: 10),
            ]))
        var options = Self.options(for: env)
        options.preferNewestCodexSessionsFirst = false
        _ = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day,
            options: options)

        let pendingURL = try env.writeSession(
            day: day,
            filename: "b-pending.jsonl",
            contents: env.jsonl([
                Self.sessionMeta(id: "pending"),
                Self.turnContext(timestamp: iso),
            ]))
        let cachedHandle = try FileHandle(forWritingTo: cachedURL)
        try cachedHandle.seekToEnd()
        try cachedHandle.write(contentsOf: Data("\n".utf8))
        try cachedHandle.close()

        var pendingCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        let roots = CostUsageScanner.codexSessionsRoots(options: options)
            .map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
            .sorted()
        pendingCache.codexActiveLookbackState = try CostUsageCodexActiveLookbackState(
            scanSinceKey: #require(pendingCache.scanSinceKey),
            rootPaths: roots,
            completedRootPaths: roots,
            pendingFilePaths: [cachedURL.path, pendingURL.path],
            completedCurrentWindowRootPaths: roots,
            completedCurrentWindowFlatRootPaths: roots)
        pendingCache.codexScanCatchUpPending = true
        CostUsageStoreAccess.replace(cacheRoot: env.cacheRoot, cache: pendingCache)

        options.maxCodexScanBytesPerRefresh = 1
        options.maxCodexScanDurationPerRefresh = 60
        _ = CostUsageScanner.loadDailyReport(
            provider: .codex,
            since: day,
            until: day,
            now: day.addingTimeInterval(1),
            options: options)

        let deferredCache = CostUsageStoreAccess.read(cacheRoot: env.cacheRoot)
        #expect(deferredCache.files[pendingURL.path] == nil)
        #expect(deferredCache.codexActiveLookbackState?.pendingFilePaths.contains(pendingURL.path) == true)
        #expect(deferredCache.codexScanCatchUpPending == true)
    }
}
