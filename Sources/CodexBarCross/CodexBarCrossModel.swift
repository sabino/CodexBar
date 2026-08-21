import CodexBarCore
import Foundation
import SwiftCrossUI

@MainActor
final class CodexBarCrossModel: SwiftCrossUI.ObservableObject {
    enum Section: String, CaseIterable {
        case general = "General"
        case spend = "Usage & Spend"
        case notifications = "Notifications"
        case menuBar = "Menu Bar"
        case menu = "Menu"
        case advanced = "Advanced"
        case about = "About"
    }

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

    @SwiftCrossUI.Published var section: Section = .general
    @SwiftCrossUI.Published var selectedProviderID: UsageProvider?
    @SwiftCrossUI.Published var searchQuery = ""
    @SwiftCrossUI.Published var providers: [ProviderRow]
    @SwiftCrossUI.Published var isRefreshing = false
    @SwiftCrossUI.Published var lastUpdated: Date?
    @SwiftCrossUI.Published var globalError: String?
    @SwiftCrossUI.Published var spendRange: SpendRange = .month
    @SwiftCrossUI.Published var costSnapshot: CostUsageTokenSnapshot?
    @SwiftCrossUI.Published var spendDashboard = SpendDashboardModel(requestedDays: 30, groups: [])
    @SwiftCrossUI.Published var isRefreshingSpend = false
    @SwiftCrossUI.Published var spendError: String?
    @SwiftCrossUI.Published var historyProgressText: String?
    @SwiftCrossUI.Published var historyProgressFraction: Double?
    @SwiftCrossUI.Published var preferences: CodexBarCrossPreferences

    private var config: CodexBarConfig
    private let configStore: CodexBarConfigStore
    private let providerRuntime: ProviderRuntimeSession
    private let costFetcher = CostUsageFetcher()
    private let preferencesStore: CodexBarCrossPreferencesStore
    private var automaticHistoryMaintenanceTask: Task<Void, Never>?
    private var automaticHistoryMaintenanceStarted = false

    init(configStore: CodexBarConfigStore = CodexBarConfigStore()) {
        let preferencesStore = CodexBarCrossPreferencesStore()
        self.preferencesStore = preferencesStore
        self.preferences = preferencesStore.load()
        self.configStore = configStore
        self.config = (try? configStore.load()) ?? CodexBarConfig.makeDefault()
        self.providerRuntime = ProviderRuntimeSession(configStore: configStore)
        let enabled = Set(self.config.enabledProviders().compactMap(\.firstPartyProvider))
        self.providers = ProviderDescriptorRegistry.all.map { descriptor in
            ProviderRow(
                id: descriptor.id,
                name: descriptor.metadata.displayName,
                shortName: descriptor.metadata.shortDisplayName,
                accent: descriptor.branding.color,
                enabled: enabled.contains(descriptor.id))
        }
        // The standalone window is the settings surface. The tray popup owns the
        // selected-provider-at-open behavior, so opening Settings must not trigger
        // a real provider probe or land on an unrelated provider pane.
        self.selectedProviderID = nil
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
        self.selectedProviderID = nil
        self.section = section
        if section == .spend, self.costSnapshot == nil, !self.isRefreshingSpend {
            Task {
                await self.loadCachedSpendHistory()
                if self.preferences.refreshOnOpen {
                    await self.performAutomaticHistoryMaintenanceSlice()
                }
            }
        }
    }

    func select(_ provider: UsageProvider) {
        self.selectedProviderID = provider
    }

    func selectSpendRange(_ range: SpendRange) {
        guard self.spendRange != range else { return }
        self.spendRange = range
        self.rebuildSpendDashboard()
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
        self.isRefreshing = true
        self.globalError = nil
        defer {
            self.isRefreshing = false
            PlatformMemory.releaseUnusedHeapPages()
        }

        do {
            let result = try await self.providerRuntime.fetch(
                provider: provider,
                config: self.config,
                historyDays: 365,
                interaction: interaction)
            self.update(provider: provider, result: result, error: nil)
            self.lastUpdated = Date()
        } catch {
            self.update(provider: provider, result: nil, error: error.localizedDescription)
            self.globalError = error.localizedDescription
        }
    }

    func setEnabled(_ provider: UsageProvider, enabled: Bool) {
        guard var providerConfig = self.config.providerConfig(for: provider.instanceID) else { return }
        providerConfig.enabled = enabled
        self.config.setProviderConfig(providerConfig)
        do {
            try self.configStore.save(self.config)
            if let index = self.providers.firstIndex(where: { $0.id == provider }) {
                self.providers[index].enabled = enabled
            }
        } catch {
            self.globalError = error.localizedDescription
        }
    }

    func setPreference<Value>(_ keyPath: WritableKeyPath<CodexBarCrossPreferences, Value>, to value: Value) {
        var preferences = self.preferences
        preferences[keyPath: keyPath] = value
        self.preferences = preferences
        self.preferencesStore.save(preferences)
        self.rescheduleAutomaticHistoryMaintenance()
    }

    /// Starts the low-duty history loop without doing work at application startup.
    ///
    /// The first pass happens only after the configured refresh interval. Opening
    /// Usage & Spend can request one immediate bounded pass after its compact cache
    /// has already rendered. Explicit Refresh uses the separate draining coordinator.
    func startAutomaticHistoryMaintenance() {
        guard !self.automaticHistoryMaintenanceStarted else { return }
        self.automaticHistoryMaintenanceStarted = true
        self.rescheduleAutomaticHistoryMaintenance()
    }

    func loadCachedSpendHistory() async {
        guard !self.isRefreshingSpend else { return }
        guard self.preferences.historyEnabled else {
            self.spendError = "Local usage history is disabled in Advanced."
            return
        }
        self.isRefreshingSpend = true
        self.spendError = nil
        defer {
            self.isRefreshingSpend = false
            PlatformMemory.releaseUnusedHeapPages()
        }
        if let snapshot = await self.costFetcher.loadCachedCodexTokenSnapshot(
            historyDays: SpendRange.year.rawValue,
            includeProjectAndSessionBreakdowns: false)
        {
            self.publishSpendSnapshot(snapshot)
        } else {
            self.spendError = "No indexed spend history is available yet."
        }
    }

    func refreshSpendHistory() async {
        guard !self.isRefreshingSpend else { return }
        guard self.preferences.historyEnabled else {
            self.spendError = "Local usage history is disabled in Advanced."
            return
        }
        self.isRefreshingSpend = true
        self.spendError = nil
        self.historyProgressFraction = nil
        defer {
            self.isRefreshingSpend = false
            self.historyProgressFraction = nil
            PlatformMemory.releaseUnusedHeapPages()
        }
        do {
            // Never blank already indexed history while an explicit full catch-up runs. The
            // aggregate-only cache read is cheap even for very large raw-session corpora.
            if let cached = await self.costFetcher.loadCachedCodexTokenSnapshot(
                historyDays: SpendRange.year.rawValue,
                includeProjectAndSessionBreakdowns: false)
            {
                self.publishSpendSnapshot(cached)
            }
            self.historyProgressText = "Starting full historical refresh…"
            let stableSnapshot = try await self.costFetcher.refreshCodexHistoryToCompletion(
                historyDays: SpendRange.year.rawValue,
                refreshPricingInBackground: false)
            { [weak self] status in
                await self?.publishHistoryProgress(status)
            }
            self.publishSpendSnapshot(stableSnapshot)
            self.historyProgressText = "Historical usage is fully up to date."
        } catch {
            self.spendError = error.localizedDescription
            if self.costSnapshot == nil {
                if let cached = await self.costFetcher.loadCachedCodexTokenSnapshot(
                    historyDays: SpendRange.year.rawValue,
                    includeProjectAndSessionBreakdowns: false)
                {
                    self.publishSpendSnapshot(cached)
                }
            }
        }
    }

    private func publishSpendSnapshot(_ snapshot: CostUsageTokenSnapshot) {
        self.costSnapshot = snapshot
        self.rebuildSpendDashboard()
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

    private func rebuildSpendDashboard() {
        guard let snapshot = self.costSnapshot else {
            self.spendDashboard = SpendDashboardModel(requestedDays: self.spendRange.rawValue, groups: [])
            return
        }
        let input = SpendDashboardModel.ProviderInput(
            provider: .codex,
            displayName: ProviderDescriptorRegistry.descriptor(for: .codex).metadata.displayName,
            snapshot: snapshot,
            includesIndexedPartialHistory: !snapshot.historyCoverageIsEstablished)
        self.spendDashboard = SpendDashboardModel.build(
            inputs: [input],
            requestedDays: self.spendRange.rawValue,
            now: Date())
    }

    private func publishHistoryProgress(_ status: CostUsageFetcher.CodexScanCatchUpStatus) {
        if status.totalBytes > 0 {
            let processed = min(status.processedBytes, status.totalBytes)
            self.historyProgressFraction = Double(processed) / Double(status.totalBytes)
            self.historyProgressText = "Indexed \(status.completedFiles) of \(status.totalFiles) sessions"
        } else if status.totalFiles > 0 {
            self.historyProgressFraction = Double(status.completedFiles) / Double(status.totalFiles)
            self.historyProgressText = "Indexed \(status.completedFiles) of \(status.totalFiles) sessions"
        } else {
            self.historyProgressFraction = nil
            self.historyProgressText = status.pending ? "Indexing historical sessions…" : "Historical usage is current."
        }
    }

    private func update(provider: UsageProvider, result: ProviderFetchResult?, error: String?) {
        guard let index = self.providers.firstIndex(where: { $0.id == provider }) else { return }
        self.providers[index].snapshot = result?.usage
        self.providers[index].credits = result?.credits
        self.providers[index].source = result?.sourceLabel
        self.providers[index].error = error
    }
}
