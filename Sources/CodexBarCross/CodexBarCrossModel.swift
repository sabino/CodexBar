import CodexBarCore
import CodexBarCrossSupport
import Foundation
import SwiftCrossUI

@MainActor
final class CodexBarCrossModel: SwiftCrossUI.ObservableObject {
    typealias Section = CodexBarCrossSection

    enum SpendRange: Int, CaseIterable, Identifiable {
        case week = 7
        case month = 30
        case quarter = 90
        case year = 365

        var id: Int {
            self.rawValue
        }

        var label: String {
            switch self {
            case .week: "7d"
            case .month: "30d"
            case .quarter: "90d"
            case .year: "All"
            }
        }
    }

    struct ProviderRow: Identifiable {
        let id: UsageProvider
        let name: String
        let shortName: String
        let accent: ProviderColor
        var enabled: Bool
        var snapshot: UsageSnapshot?
        var credits: CreditsSnapshot?
        var source: String?
        var error: String?

        var statusLabel: String {
            if self.error != nil { return "Needs attention" }
            if self.snapshot != nil || self.credits != nil { return "Connected" }
            return self.enabled ? "Ready" : "Disabled"
        }

        var remainingPercent: Double? {
            let windows = [self.snapshot?.primary, self.snapshot?.secondary, self.snapshot?.tertiary]
                .compactMap(\.self)
                .filter { !$0.isSyntheticPlaceholder }
            return windows.map(\.remainingPercent).min()
        }
    }

    struct ContentRevision: Hashable {
        let preferences: UInt64
        let provider: UInt64
        let spend: UInt64
    }

    private struct ProviderPresentation {
        var providers: [ProviderRow]
        var isRefreshing = false
        var lastUpdated: Date?
        var globalError: String?
    }

    private struct SpendPresentation {
        var range: SpendRange = .month
        var snapshot: CostUsageTokenSnapshot?
        var dashboard = SpendDashboardModel(requestedDays: SpendRange.month.rawValue, groups: [])
        var isRefreshing = false
        var error: String?
        var historyProgressText: String?
        var historyProgressFraction: Double?
    }

    @SwiftCrossUI.Published private var providerPresentation: ProviderPresentation
    @SwiftCrossUI.Published private var spendPresentation = SpendPresentation()
    @SwiftCrossUI.Published var preferences: CodexBarCrossPreferences

    private var config: CodexBarConfig
    private let configStore: CodexBarConfigStore
    private let providerRuntime: ProviderRuntimeSession
    private let costFetcher = CostUsageFetcher()
    private let preferencesStore: CodexBarCrossPreferencesStore
    private var automaticHistoryMaintenanceTask: Task<Void, Never>?
    private var automaticHistoryMaintenanceStarted = false
    private var preferencesRevision: UInt64 = 0
    private var providerRevision: UInt64 = 0
    private var spendRevision: UInt64 = 0
    let navigationModel = CodexBarCrossNavigationModel()

    init(configStore: CodexBarConfigStore = CodexBarConfigStore()) {
        let preferencesStore = CodexBarCrossPreferencesStore()
        self.preferencesStore = preferencesStore
        self.preferences = preferencesStore.load()
        self.configStore = configStore
        self.config = (try? configStore.load()) ?? CodexBarConfig.makeDefault()
        self.providerRuntime = ProviderRuntimeSession(configStore: configStore)
        let enabled = Set(self.config.enabledProviders().compactMap(\.firstPartyProvider))
        let providers = ProviderDescriptorRegistry.all.map { descriptor in
            ProviderRow(
                id: descriptor.id,
                name: descriptor.metadata.displayName,
                shortName: descriptor.metadata.shortDisplayName,
                accent: descriptor.branding.color,
                enabled: enabled.contains(descriptor.id))
        }
        self.providerPresentation = ProviderPresentation(providers: providers)
    }

    var section: Section {
        self.navigationModel.state.section ?? .general
    }

    var selectedProviderID: UsageProvider? {
        self.navigationModel.state.provider
    }

    var searchQuery: String {
        self.navigationModel.searchQuery
    }

    var providers: [ProviderRow] {
        self.providerPresentation.providers
    }

    var isRefreshing: Bool {
        self.providerPresentation.isRefreshing
    }

    var lastUpdated: Date? {
        self.providerPresentation.lastUpdated
    }

    var globalError: String? {
        self.providerPresentation.globalError
    }

    var spendRange: SpendRange {
        self.spendPresentation.range
    }

    var costSnapshot: CostUsageTokenSnapshot? {
        self.spendPresentation.snapshot
    }

    var spendDashboard: SpendDashboardModel {
        self.spendPresentation.dashboard
    }

    var isRefreshingSpend: Bool {
        self.spendPresentation.isRefreshing
    }

    var spendError: String? {
        self.spendPresentation.error
    }

    var historyProgressText: String? {
        self.spendPresentation.historyProgressText
    }

    var historyProgressFraction: Double? {
        self.spendPresentation.historyProgressFraction
    }

    var filteredProviders: [ProviderRow] {
        let query = self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return self.providers }
        return self.providers.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.id.rawValue.localizedCaseInsensitiveContains(query)
        }
    }

    var selectedProvider: ProviderRow? {
        guard let selectedProviderID else { return nil }
        return self.providers.first(where: { $0.id == selectedProviderID })
    }

    var selectedContentRevision: ContentRevision {
        if self.selectedProviderID != nil {
            return ContentRevision(
                preferences: self.preferencesRevision,
                provider: self.providerRevision,
                spend: 0)
        }
        if self.section == .spend {
            return ContentRevision(
                preferences: self.preferencesRevision,
                provider: 0,
                spend: self.spendRevision)
        }
        return ContentRevision(
            preferences: self.preferencesRevision,
            provider: 0,
            spend: 0)
    }

    func authenticationSummary(for provider: UsageProvider) -> ProviderDiagnosticAuthSummary {
        let summary = self.providerRuntime.authenticationSummary(provider: provider, config: self.config)
        let fetchedSuccessfully = self.providers.first(where: { $0.id == provider }).map {
            $0.snapshot != nil || $0.credits != nil
        } ?? false
        guard fetchedSuccessfully, !summary.configured else { return summary }
        return ProviderDiagnosticAuthSummary(configured: true, modes: summary.modes)
    }

    var primarySpendGroup: SpendDashboardModel.CurrencyGroup? {
        self.spendDashboard.groups.first
    }

    var indexedSpendCoverageText: String? {
        guard let snapshot = self.costSnapshot,
              !snapshot.historyCoverageIsEstablished,
              !snapshot.daily.isEmpty
        else { return nil }
        let count = snapshot.daily.count
        return "Showing \(count) indexed \(count == 1 ? "day" : "days") while historical catch-up is incomplete"
    }

    func select(_ section: Section) {
        _ = self.navigationModel.select(section)
        if section == .spend, self.costSnapshot == nil, !self.isRefreshingSpend {
            Task {
                let cachedSnapshotLoaded = await self.loadCachedSpendHistory()
                if CodexBarCrossHistoryLoadingPolicy.shouldRunImmediateMaintenance(
                    cachedSnapshotLoaded: cachedSnapshotLoaded,
                    refreshOnOpen: self.preferences.refreshOnOpen)
                {
                    await self.performAutomaticHistoryMaintenanceSlice()
                }
            }
        }
    }

    @discardableResult
    func select(_ provider: UsageProvider) -> Bool {
        self.navigationModel.select(provider)
    }

    func selectSpendRange(_ range: SpendRange) {
        guard self.spendRange != range else { return }
        var presentation = self.spendPresentation
        presentation.range = range
        presentation.dashboard = Self.makeSpendDashboard(snapshot: presentation.snapshot, range: range)
        self.publishSpendPresentation(presentation)
    }

    func setSearchQuery(_ query: String) {
        self.navigationModel.setSearchQuery(query)
    }

    func refreshSelectedProvider() async {
        guard let providerID = self.selectedProviderID else { return }
        await self.refresh(providerID, interaction: .background)
    }

    func refresh(
        _ provider: UsageProvider,
        interaction: ProviderInteraction = .userInitiated) async
    {
        guard !self.isRefreshing else { return }
        var loadingPresentation = self.providerPresentation
        loadingPresentation.isRefreshing = true
        loadingPresentation.globalError = nil
        self.publishProviderPresentation(loadingPresentation)
        defer { PlatformMemory.releaseUnusedHeapPages() }

        do {
            let result = try await self.providerRuntime.fetch(
                provider: provider,
                config: self.config,
                historyDays: 365,
                interaction: interaction)
            var presentation = self.providerPresentation
            Self.updateProvider(
                provider,
                in: &presentation.providers,
                result: result,
                error: nil)
            presentation.lastUpdated = Date()
            presentation.isRefreshing = false
            self.publishProviderPresentation(presentation)
        } catch {
            var presentation = self.providerPresentation
            Self.updateProvider(
                provider,
                in: &presentation.providers,
                result: nil,
                error: error.localizedDescription)
            presentation.globalError = error.localizedDescription
            presentation.isRefreshing = false
            self.publishProviderPresentation(presentation)
        }
    }

    func setEnabled(_ provider: UsageProvider, enabled: Bool) {
        guard var providerConfig = self.config.providerConfig(for: provider.instanceID) else { return }
        guard providerConfig.enabled != enabled else { return }
        providerConfig.enabled = enabled
        self.config.setProviderConfig(providerConfig)
        do {
            try self.configStore.save(self.config)
            var presentation = self.providerPresentation
            if let index = presentation.providers.firstIndex(where: { $0.id == provider }),
               presentation.providers[index].enabled != enabled
            {
                presentation.providers[index].enabled = enabled
                self.publishProviderPresentation(presentation)
            }
        } catch {
            var presentation = self.providerPresentation
            if presentation.globalError != error.localizedDescription {
                presentation.globalError = error.localizedDescription
                self.publishProviderPresentation(presentation)
            }
        }
    }

    func setPreference<Value: Equatable>(
        _ keyPath: WritableKeyPath<CodexBarCrossPreferences, Value>,
        to value: Value)
    {
        var preferences = self.preferences
        guard preferences[keyPath: keyPath] != value else { return }
        preferences[keyPath: keyPath] = value
        self.preferencesRevision &+= 1
        self.preferences = preferences
        self.preferencesStore.save(preferences)
        self.rescheduleAutomaticHistoryMaintenance()
    }

    /// Starts the low-duty history loop without doing work at application startup.
    ///
    /// The first pass happens only after the configured refresh interval. Opening
    /// Usage & Spend requests one immediate bounded pass only when no compact cache
    /// exists yet. Explicit Refresh uses the separate draining coordinator.
    func startAutomaticHistoryMaintenance() {
        guard !self.automaticHistoryMaintenanceStarted else { return }
        self.automaticHistoryMaintenanceStarted = true
        self.rescheduleAutomaticHistoryMaintenance()
    }

    @discardableResult
    func loadCachedSpendHistory() async -> Bool {
        guard !self.isRefreshingSpend else { return false }
        guard self.preferences.historyEnabled else {
            self.setSpendError("Local usage history is disabled in Advanced.")
            return false
        }
        var loadingPresentation = self.spendPresentation
        loadingPresentation.isRefreshing = true
        loadingPresentation.error = nil
        self.publishSpendPresentation(loadingPresentation)
        defer { PlatformMemory.releaseUnusedHeapPages() }

        let snapshot = await self.costFetcher.loadCachedCodexTokenSnapshot(
            historyDays: SpendRange.year.rawValue,
            includeProjectAndSessionBreakdowns: false)
        var presentation = self.spendPresentation
        if let snapshot {
            Self.applySpendSnapshot(snapshot, to: &presentation)
        } else {
            presentation.error = "No indexed spend history is available yet."
        }
        presentation.isRefreshing = false
        self.publishSpendPresentation(presentation)
        return snapshot != nil
    }

    func refreshSpendHistory() async {
        guard !self.isRefreshingSpend else { return }
        guard self.preferences.historyEnabled else {
            self.setSpendError("Local usage history is disabled in Advanced.")
            return
        }
        var loadingPresentation = self.spendPresentation
        loadingPresentation.isRefreshing = true
        loadingPresentation.error = nil
        loadingPresentation.historyProgressFraction = nil
        self.publishSpendPresentation(loadingPresentation)
        defer { PlatformMemory.releaseUnusedHeapPages() }

        do {
            // Never blank already indexed history while an explicit full catch-up runs. The
            // aggregate-only cache read is cheap even for very large raw-session corpora.
            if let cached = await self.costFetcher.loadCachedCodexTokenSnapshot(
                historyDays: SpendRange.year.rawValue,
                includeProjectAndSessionBreakdowns: false)
            {
                self.publishSpendSnapshot(cached)
            }
            self.setHistoryProgress(
                text: "Starting full historical refresh…",
                fraction: nil)
            let stableSnapshot = try await self.costFetcher.refreshCodexHistoryToCompletion(
                historyDays: SpendRange.year.rawValue,
                refreshPricingInBackground: false)
            { [weak self] status in
                await self?.publishHistoryProgress(status)
            }
            var presentation = self.spendPresentation
            Self.applySpendSnapshot(stableSnapshot, to: &presentation)
            presentation.historyProgressText = "Historical usage is fully up to date."
            presentation.historyProgressFraction = nil
            presentation.isRefreshing = false
            self.publishSpendPresentation(presentation)
        } catch {
            var presentation = self.spendPresentation
            presentation.error = error.localizedDescription
            if presentation.snapshot == nil {
                if let cached = await self.costFetcher.loadCachedCodexTokenSnapshot(
                    historyDays: SpendRange.year.rawValue,
                    includeProjectAndSessionBreakdowns: false)
                {
                    presentation = self.spendPresentation
                    presentation.error = error.localizedDescription
                    Self.applySpendSnapshot(cached, to: &presentation)
                }
            }
            presentation.historyProgressFraction = nil
            presentation.isRefreshing = false
            self.publishSpendPresentation(presentation)
        }
    }

    private func publishSpendSnapshot(_ snapshot: CostUsageTokenSnapshot) {
        var presentation = self.spendPresentation
        Self.applySpendSnapshot(snapshot, to: &presentation)
        self.publishSpendPresentation(presentation)
    }

    private func rescheduleAutomaticHistoryMaintenance() {
        self.automaticHistoryMaintenanceTask?.cancel()
        self.automaticHistoryMaintenanceTask = nil
        guard self.automaticHistoryMaintenanceStarted,
              let delayNanoseconds = self.automaticHistoryMaintenanceDelayNanoseconds
        else { return }

        self.automaticHistoryMaintenanceTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: delayNanoseconds)
                } catch {
                    return
                }
                guard !Task.isCancelled, let self else { return }
                await self.performAutomaticHistoryMaintenanceSlice()
            }
        }
    }

    private var automaticHistoryMaintenanceDelayNanoseconds: UInt64? {
        let baseSeconds: UInt64? = switch self.preferences.refreshInterval {
        case "1 minute": 60
        case "5 minutes": 5 * 60
        case "15 minutes": 15 * 60
        case "30 minutes": 30 * 60
        case "1 hour": 60 * 60
        default: nil
        }
        guard let baseSeconds else { return nil }
        let lowPowerMultiplier: UInt64 = self.preferences.lowPowerMode == "Always" ? 3 : 1
        return baseSeconds * lowPowerMultiplier * 1_000_000_000
    }

    private func performAutomaticHistoryMaintenanceSlice() async {
        guard self.preferences.historyEnabled, !self.isRefreshingSpend else { return }
        defer { PlatformMemory.releaseUnusedHeapPages() }
        do {
            // This is the original incremental scanner with a cross-platform
            // 350 ms budget. Its compact load retains aggregate history and only
            // hydrates raw rows for files whose size/mtime or tail state changed.
            let snapshot = try await self.costFetcher.loadTokenSnapshot(
                provider: .codex,
                now: Date(),
                forceRefresh: true,
                historyDays: SpendRange.year.rawValue,
                allowPricingRefresh: false,
                refreshPricingInBackground: false,
                includePiSessions: true,
                includeProjectAndSessionBreakdowns: false,
                bypassScannerDebounce: true)
            if self.costSnapshot != nil || self.section == .spend {
                self.publishSpendSnapshot(snapshot)
            }
        } catch {
            // Automatic maintenance is best-effort. Existing indexed history stays
            // visible and an explicit Refresh remains available for actionable errors.
        }
    }

    private static func makeSpendDashboard(
        snapshot: CostUsageTokenSnapshot?,
        range: SpendRange) -> SpendDashboardModel
    {
        guard let snapshot else {
            return SpendDashboardModel(requestedDays: range.rawValue, groups: [])
        }
        let input = SpendDashboardModel.ProviderInput(
            provider: .codex,
            displayName: ProviderDescriptorRegistry.descriptor(for: .codex).metadata.displayName,
            snapshot: snapshot,
            includesIndexedPartialHistory: !snapshot.historyCoverageIsEstablished)
        return SpendDashboardModel.build(
            inputs: [input],
            requestedDays: range.rawValue,
            now: Date())
    }

    private func publishHistoryProgress(_ status: CostUsageFetcher.CodexScanCatchUpStatus) {
        let text: String
        let fraction: Double?
        if status.totalBytes > 0 {
            let processed = min(status.processedBytes, status.totalBytes)
            fraction = Double(processed) / Double(status.totalBytes)
            text = "Indexed \(status.completedFiles) of \(status.totalFiles) sessions"
        } else if status.totalFiles > 0 {
            fraction = Double(status.completedFiles) / Double(status.totalFiles)
            text = "Indexed \(status.completedFiles) of \(status.totalFiles) sessions"
        } else {
            fraction = nil
            text = status.pending ? "Indexing historical sessions…" : "Historical usage is current."
        }
        self.setHistoryProgress(text: text, fraction: fraction)
    }

    private func setSpendError(_ error: String?) {
        guard self.spendPresentation.error != error else { return }
        var presentation = self.spendPresentation
        presentation.error = error
        self.publishSpendPresentation(presentation)
    }

    private func setHistoryProgress(text: String?, fraction: Double?) {
        guard self.historyProgressText != text || self.historyProgressFraction != fraction else { return }
        var presentation = self.spendPresentation
        presentation.historyProgressText = text
        presentation.historyProgressFraction = fraction
        self.publishSpendPresentation(presentation)
    }

    private func publishProviderPresentation(_ presentation: ProviderPresentation) {
        self.providerRevision &+= 1
        self.providerPresentation = presentation
    }

    private func publishSpendPresentation(_ presentation: SpendPresentation) {
        self.spendRevision &+= 1
        self.spendPresentation = presentation
    }

    private static func applySpendSnapshot(
        _ snapshot: CostUsageTokenSnapshot,
        to presentation: inout SpendPresentation)
    {
        presentation.snapshot = snapshot
        presentation.dashboard = self.makeSpendDashboard(snapshot: snapshot, range: presentation.range)
    }

    private static func updateProvider(
        _ provider: UsageProvider,
        in providers: inout [ProviderRow],
        result: ProviderFetchResult?,
        error: String?)
    {
        guard let index = providers.firstIndex(where: { $0.id == provider }) else { return }
        providers[index].snapshot = result?.usage
        providers[index].credits = result?.credits
        providers[index].source = result?.sourceLabel
        providers[index].error = error
    }
}
