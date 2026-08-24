#if CrossPlatformApp

import CodexBarCore
import Foundation
import SwiftCrossUI
#if os(Linux)
import GtkBackend
#elseif os(macOS)
import AppKitBackend
#elseif os(Windows)
import WinUIBackend
#endif

struct CodexBarRootView: View {
    @State private var model: CodexBarCrossModel
    @Environment(\.openURL) private var openURL

    init(model: CodexBarCrossModel) {
        self._model = State(wrappedValue: model)
    }

    var body: some View {
        HStack(spacing: 0) {
            ModelObservedRegion(model: self.model) {
                self.sidebar
            }
            .frame(minWidth: 228, idealWidth: 228, maxWidth: 228, maxHeight: .infinity)
            .background(CodexBarPalette.sidebarBackground)
            Divider()
            ModelObservedRegion(model: self.model) {
                ScrollView {
                    PublishedObservedRegion(observation: self.model.navigationModel.routeObservation) {
                        PersistentViewSwitcher(
                            selection: self.contentCacheKey,
                            revision: self.model.selectedContentRevision)
                        {
                            self.content
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(28)
                }
            }
            .frame(minWidth: 620, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 860, minHeight: 580)
        .background(LinearGradient(
            colors: CodexBarPalette.windowGradient,
            startPoint: .topLeading,
            endPoint: .bottomTrailing))
        .foregroundColor(CodexBarPalette.primaryText)
        .colorScheme(.dark)
        .toggleStyle(.switch)
        #if os(Linux)
            .inspectWindow { window in
                PlatformWindowController.shared.attachSettingsWindow(window)
                LinuxWindowResizeCoalescer.install(on: window)
                window.setEscapeKeyPressedHandler {
                    PlatformWindowController.shared.hideSettings()
                }
            }
        #elseif os(macOS)
            .inspectWindow { window in
                PlatformWindowController.shared.attachSettingsWindow(window)
            }
        #elseif os(Windows)
            .inspectWindow { window in
                PlatformWindowController.shared.attachSettingsWindow(window)
            }
        #endif
            .task {
                    self.model.startAutomaticHistoryMaintenance()
                    if self.model.selectedProviderID != nil {
                        await self.model.refreshSelectedProvider()
                    }
                }
    }

    private var sidebar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("CodexBar")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button {
                    PlatformWindowController.shared.hideSettings()
                } label: {
                    Text("×")
                        .font(.title2)
                        .frame(width: 34, height: 30, alignment: .center)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)

            PublishedObservedRegion(observation: self.model.navigationModel.searchObservation) {
                TextField("Search providers", text: Binding(
                    get: { self.model.searchQuery },
                    set: { self.model.setSearchQuery($0) }))
            }

            #if os(Linux)
            PublishedObservedRegion(observation: self.model.navigationModel.providerObservation) {
                PlatformNavigationList(
                    items: self.navigationItems,
                    selection: self.navigationSelection)
                    .frame(maxWidth: .infinity)
            }
            #else
            PublishedObservedRegion(observation: self.model.navigationModel.sectionObservation) {
                PlatformNavigationList(
                    items: self.navigationItems,
                    selection: self.navigationSelection)
                    .frame(maxWidth: .infinity)
            }
            #endif

            Divider()
            Text("PROVIDERS")
                .font(.caption)
                .foregroundColor(CodexBarPalette.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            SearchObservedRegion(navigation: self.model.navigationModel) {
                PublishedObservedRegion(observation: self.model.navigationModel.providerObservation) {
                    if self.model.filteredProviders.isEmpty {
                        Text("No matching providers")
                            .font(.caption)
                            .foregroundColor(CodexBarPalette.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                        Spacer()
                    } else {
                        PlatformProviderList(
                            items: { self.providerListItems },
                            selection: self.providerSelection)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .padding(14)
    }

    private var providerSelection: Binding<UsageProvider?> {
        Binding(
            get: { self.model.selectedProviderID },
            set: { provider in
                guard let provider else { return }
                if self.model.select(provider) {
                    Task { await self.model.refresh(provider) }
                }
            })
    }

    private var providerListItems: [PlatformProviderListItem] {
        self.model.filteredProviders.map { provider in
            PlatformProviderListItem(
                id: provider.id,
                title: provider.name,
                symbol: self.providerGlyph(provider.id),
                iconPath: ProviderIconStore.url(for: provider.id)?.path,
                state: self.providerListState(provider))
        }
    }

    private var navigationItems: [PlatformNavigationItem] {
        CodexBarCrossModel.Section.allCases.map { section in
            PlatformNavigationItem(
                id: section,
                title: section.rawValue,
                symbol: self.sectionGlyph(section))
        }
    }

    private var navigationSelection: Binding<CodexBarCrossModel.Section?> {
        Binding(
            get: {
                self.model.selectedProviderID == nil ? self.model.section : nil
            },
            set: { section in
                if let section {
                    self.model.select(section)
                }
            })
    }

    private var contentCacheKey: ContentCacheKey {
        if self.model.selectedProviderID != nil {
            .provider
        } else {
            .section(self.model.section)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let provider = self.model.selectedProvider {
            self.providerDetail(provider)
        } else {
            switch self.model.section {
            case .general:
                self.generalPane
            case .spend:
                self.spendPane
            case .notifications:
                self.notificationsPane
            case .menuBar:
                self.menuBarPane
            case .menu:
                self.menuPane
            case .advanced:
                self.advancedPane
            case .about:
                self.aboutPane
            }
        }
    }

    private var generalPane: some View {
        VStack(spacing: 18) {
            self.paneHeader(
                title: "General",
                subtitle: "System behavior, automatic refresh, and startup settings.")

            self.sectionLabel("SYSTEM")
            self.card {
                VStack(spacing: 14) {
                    self.settingPickerRow(
                        title: "Language",
                        subtitle: "Language used throughout CodexBar.",
                        options: ["System", "English", "Português (Brasil)"],
                        keyPath: \.appLanguage)
                    Divider()
                    self.settingPickerRow(
                        title: "Currency",
                        subtitle: "Currency used for local cost estimates.",
                        options: ["Automatic", "USD", "EUR", "GBP", "BRL"],
                        keyPath: \.preferredCurrency)
                    Divider()
                    self.settingToggleRow(
                        title: "Launch at login",
                        subtitle: "Start the native tray service when you sign in.",
                        keyPath: \.launchAtLogin)
                }
            }

            self.sectionLabel("REFRESHING")
            self.card {
                VStack(spacing: 14) {
                    self.settingPickerRow(
                        title: "Refresh interval",
                        subtitle: "How often enabled providers update in the background.",
                        options: ["Manual", "1 minute", "5 minutes", "15 minutes", "30 minutes", "1 hour"],
                        keyPath: \.refreshInterval)
                    Divider()
                    self.settingToggleRow(
                        title: "Refresh when opened",
                        subtitle: "Update the selected provider when the tray opens.",
                        keyPath: \.refreshOnOpen)
                    Divider()
                    self.settingPickerRow(
                        title: "Low power mode",
                        subtitle: "Throttle automatic work while preserving manual refresh.",
                        options: ["Automatic", "Always", "Never"],
                        keyPath: \.lowPowerMode)
                    Divider()
                    self.settingToggleRow(
                        title: "Provider status checks",
                        subtitle: "Include official status-page health when available.",
                        keyPath: \.statusChecksEnabled)
                }
            }

            self.sectionLabel("RUNTIME")
            self.card {
                VStack(spacing: 14) {
                    self.infoRow(label: "Provider engine", value: "CodexBarCore · in process")
                    Divider()
                    self.infoRow(label: "UI", value: "Shared SwiftCrossUI view tree")
                    Divider()
                    self.infoRow(label: "Open menu shortcut", value: "Super + Shift + U")
                }
            }
        }
    }

    private var spendPane: some View {
        VStack(spacing: 18) {
            HStack(spacing: 16) {
                self.paneHeader(
                    title: "Usage & Spend",
                    subtitle: "Local estimated cost history across supported providers.")
                Spacer()
                Button(self.model.isRefreshingSpend ? "Refreshing…" : "Refresh") {
                    Task { await self.model.refreshSpendHistory() }
                }
            }

            HStack(spacing: 6) {
                ForEach(CodexBarCrossModel.SpendRange.allCases) { range in
                    Button {
                        self.model.selectSpendRange(range)
                    } label: {
                        Text(range.label)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(self.model.spendRange == range
                                ? CodexBarPalette.selectionBackground
                                : Color.clear)
                            .cornerRadius(7)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }

            if let error = self.model.spendError {
                self.card {
                    HStack(spacing: 10) {
                        Text("ⓘ")
                        Text(error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .foregroundColor(CodexBarPalette.secondaryText)
                }
            }

            if let coverage = self.model.indexedSpendCoverageSummary {
                self.card {
                    HStack(spacing: 10) {
                        Text("◔")
                            .foregroundColor(CodexBarPalette.accent)
                        VStack(spacing: 3) {
                            Text(coverage.title)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(CodexBarPalette.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(coverage.message) Refresh runs a complete historical pass.")
                                .font(.caption)
                                .foregroundColor(CodexBarPalette.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            if let progressText = self.model.historyProgressText, self.model.isRefreshingSpend {
                self.card {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Historical usage")
                                .fontWeight(.bold)
                            Spacer()
                            Text(progressText)
                                .font(.caption)
                                .foregroundColor(CodexBarPalette.secondaryText)
                        }
                        if let progress = self.model.historyProgressFraction {
                            ProgressView(value: progress)
                        } else {
                            ProgressView()
                        }
                    }
                }
            }

            self.spendChartCard

            HStack(alignment: .top, spacing: 14) {
                self.providerSpendCard
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                self.modelSpendCard
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            VStack(spacing: 3) {
                Text("Normal opens reuse the incremental cache; only new or changed sessions are parsed again.")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Manual Refresh completes the original CodexBar historical index.")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption)
            .foregroundColor(CodexBarPalette.tertiaryText)
        }
    }

    private var spendChartCard: some View {
        self.card {
            VStack(spacing: 14) {
                HStack {
                    VStack(spacing: 3) {
                        Text("ESTIMATED TOTAL")
                            .font(.caption)
                            .foregroundColor(CodexBarPalette.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(self.formattedSpendTotal)
                            .font(.title)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(spacing: 3) {
                        Text("TOKENS")
                            .font(.caption)
                            .foregroundColor(CodexBarPalette.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(self.formattedSpendTokens)
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }

                if self.spendDailyPoints.isEmpty {
                    Text(self.model.isRefreshingSpend ? "Loading indexed history…" : "No indexed spend in this range")
                        .foregroundColor(CodexBarPalette.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
                } else {
                    HStack(alignment: .bottom, spacing: 3) {
                        ForEach(self.spendDailyPoints) { point in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(CodexBarPalette.accent)
                                .frame(maxWidth: .infinity)
                                .frame(height: self.spendBarHeight(point))
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 150, alignment: .bottom)

                    HStack {
                        Text(self.formattedSpendDay(self.spendDailyPoints.first?.day))
                        Spacer()
                        Text(self.formattedSpendDay(self.spendDailyPoints.last?.day))
                    }
                    .font(.caption)
                    .foregroundColor(CodexBarPalette.tertiaryText)
                }
            }
        }
    }

    private var providerSpendCard: some View {
        self.card {
            VStack(spacing: 14) {
                Text("PROVIDERS")
                    .font(.caption)
                    .foregroundColor(CodexBarPalette.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let group = self.model.primarySpendGroup, !group.providers.isEmpty {
                    ForEach(group.providers) { row in
                        HStack(spacing: 10) {
                            ProviderArtwork(
                                provider: row.provider,
                                fallback: self.providerGlyph(row.provider))
                                .frame(width: 20, height: 20)
                            VStack(spacing: 2) {
                                Text(row.displayName)
                                    .fontWeight(.bold)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(self.formattedTokens(row.totalTokens) + " tokens")
                                    .font(.caption)
                                    .foregroundColor(CodexBarPalette.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Text(self.formattedCost(row.totalCost, currencyCode: group.currencyCode))
                                .fontWeight(.bold)
                        }
                    }
                } else {
                    Text("No provider history is available in this range.")
                        .foregroundColor(CodexBarPalette.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var modelSpendCard: some View {
        self.card {
            VStack(spacing: 12) {
                Text("MODELS")
                    .font(.caption)
                    .foregroundColor(CodexBarPalette.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if self.model.primarySpendGroup?.displayedModels.isEmpty != false {
                    Text("No model breakdown is indexed for this range.")
                        .foregroundColor(CodexBarPalette.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(self.model.primarySpendGroup?.displayedModels ?? []) { row in
                        HStack(spacing: 10) {
                            Text(row.modelName)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(self.formattedTokens(row.totalTokens))
                                .font(.caption)
                                .foregroundColor(CodexBarPalette.secondaryText)
                            Text(self.formattedCost(
                                row.totalCost,
                                currencyCode: self.model.primarySpendGroup?.currencyCode ?? "USD"))
                                .fontWeight(.bold)
                        }
                    }
                }
            }
        }
    }

    private var notificationsPane: some View {
        VStack(spacing: 18) {
            self.paneHeader(
                title: "Notifications",
                subtitle: "Quota, pace, reset, and provider-status alerts.")

            self.sectionLabel("ALERTS")
            self.card {
                VStack(spacing: 14) {
                    self.settingToggleRow(
                        title: "Quota depleted",
                        subtitle: "Notify when a session or weekly quota reaches its limit.",
                        keyPath: \.depletedNotifications)
                    Divider()
                    self.settingToggleRow(
                        title: "Threshold warnings",
                        subtitle: "Warn before remaining quota drops below the selected threshold.",
                        keyPath: \.thresholdNotifications)
                    if self.model.preferences.thresholdNotifications {
                        Divider()
                        self.settingSliderRow(
                            title: "Warning threshold",
                            value: self.model.preferences.warningThreshold,
                            range: 5...50,
                            keyPath: \.warningThreshold,
                            suffix: "% remaining")
                    }
                    Divider()
                    self.settingToggleRow(
                        title: "Predictive pace warnings",
                        subtitle: "Warn when current pace is likely to exhaust quota before reset.",
                        keyPath: \.predictiveNotifications)
                    Divider()
                    self.settingToggleRow(
                        title: "Quiet hours",
                        subtitle: "Hold non-critical notifications overnight.",
                        keyPath: \.quietHoursEnabled)
                }
            }

            self.sectionLabel("CELEBRATIONS")
            self.card {
                self.settingPickerRow(
                    title: "Quota reset celebration",
                    subtitle: "Visual feedback when a quota window resets.",
                    options: ["Off", "Subtle", "Confetti"],
                    keyPath: \.resetCelebration)
            }
        }
    }

    private var menuBarPane: some View {
        VStack(spacing: 18) {
            self.paneHeader(
                title: "Menu Bar",
                subtitle: "Choose the native tray icon and the metrics shown beside it.")

            self.sectionLabel("APPEARANCE")
            self.card {
                VStack(spacing: 14) {
                    self.settingPickerRow(
                        title: "Icon style",
                        subtitle: "Use provider artwork, a compact gauge, or a monochrome mark.",
                        options: ["Provider icon", "Usage gauge", "Monochrome"],
                        keyPath: \.menuBarIconStyle)
                    Divider()
                    self.settingToggleRow(
                        title: "High contrast",
                        subtitle: "Increase tray-icon contrast against the system panel.",
                        keyPath: \.highContrastIcon)
                    Divider()
                    self.settingToggleRow(
                        title: "Merge provider icons",
                        subtitle: "Use one switcher icon instead of one tray icon per provider.",
                        keyPath: \.mergeProviderIcons)
                    Divider()
                    self.settingToggleRow(
                        title: "Show percentage",
                        subtitle: "Display the selected provider's remaining quota beside the icon.",
                        keyPath: \.showPercentageInTray)
                }
            }

            self.sectionLabel("SWITCHER")
            self.card {
                self.settingPickerRow(
                    title: "Visible providers",
                    subtitle: "Number of provider tabs shown before horizontal scrolling.",
                    options: ["3 providers", "5 providers", "8 providers", "All providers"],
                    keyPath: \.switcherRows)
            }
        }
    }

    private var menuPane: some View {
        VStack(spacing: 18) {
            self.paneHeader(
                title: "Menu",
                subtitle: "Configure provider cards, optional details, and privacy.")

            self.sectionLabel("PROVIDER CARD")
            self.card {
                VStack(spacing: 14) {
                    self.settingToggleRow(
                        title: "Provider header",
                        subtitle: "Show provider identity and connection state.",
                        keyPath: \.showProviderHeader)
                    Divider()
                    self.settingToggleRow(
                        title: "Usage bars",
                        subtitle: "Show quota progress bars for each available window.",
                        keyPath: \.showUsageBars)
                    Divider()
                    self.settingToggleRow(
                        title: "Reset times",
                        subtitle: "Show when each quota window resets.",
                        keyPath: \.showResetTimes)
                    Divider()
                    self.settingToggleRow(
                        title: "Account",
                        subtitle: "Show the active account for the selected provider.",
                        keyPath: \.showAccount)
                    Divider()
                    self.settingToggleRow(
                        title: "Plan",
                        subtitle: "Show the provider plan or login method when available.",
                        keyPath: \.showPlan)
                    Divider()
                    self.settingToggleRow(
                        title: "Local cost",
                        subtitle: "Show locally estimated token cost when supported.",
                        keyPath: \.showCost)
                }
            }

            self.sectionLabel("PRIVACY")
            self.card {
                self.settingToggleRow(
                    title: "Hide sensitive values",
                    subtitle: "Mask account names, emails, balances, and exact spend in the menu.",
                    keyPath: \.hideSensitiveValues)
            }
        }
    }

    private var advancedPane: some View {
        VStack(spacing: 18) {
            self.paneHeader(
                title: "Advanced",
                subtitle: "History policy, diagnostics, and provider-runtime controls.")

            self.sectionLabel("LOCAL HISTORY")
            self.card {
                VStack(spacing: 14) {
                    self.settingToggleRow(
                        title: "Index usage history",
                        subtitle: "Maintain a small incremental cache for Usage & Spend.",
                        keyPath: \.historyEnabled)
                    Divider()
                    self.settingPickerRow(
                        title: "Retained window",
                        subtitle: "Maximum history exposed by the dashboard.",
                        options: ["7 days", "30 days", "90 days", "6 months", "1 year"],
                        keyPath: \.historyWindow)
                    Divider()
                    self.infoRow(label: "Remote mount policy", value: "Exclude SSHFS, FUSE, NFS, SMB and 9p")
                    Divider()
                    self.infoRow(label: "Scan policy", value: "Incremental cache · bounded work budget")
                }
            }

            self.sectionLabel("DIAGNOSTICS")
            self.card {
                VStack(spacing: 14) {
                    #if os(Linux)
                    self.settingPickerRow(
                        title: "UI renderer",
                        subtitle: "Automatic uses GPU acceleration when GTK supports it. Changes apply after restart.",
                        options: ["Automatic", "Low-memory software"],
                        keyPath: \.rendererMode)
                    Divider()
                    #endif
                    self.settingToggleRow(
                        title: "Diagnostic details",
                        subtitle: "Expose non-secret provider routing and cache status in the UI.",
                        keyPath: \.diagnosticsEnabled)
                    Divider()
                    self.settingToggleRow(
                        title: "Verbose provider errors",
                        subtitle: "Show full provider failure messages instead of a compact summary.",
                        keyPath: \.verboseProviderErrors)
                }
            }
        }
    }

    private var aboutPane: some View {
        VStack(spacing: 18) {
            self.paneHeader(
                title: "About CodexBar",
                subtitle: "The canonical CodexBar provider engine in a shared native Swift UI.")

            self.card {
                VStack(spacing: 16) {
                    HStack(spacing: 14) {
                        Text("◉")
                            .font(.title)
                            .frame(width: 48, height: 48)
                            .background(CodexBarPalette.selectionBackground)
                            .cornerRadius(12)
                        VStack(spacing: 3) {
                            Text("CodexBar")
                                .font(.title2)
                                .fontWeight(.bold)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("Native Swift · CodexBarCore · SwiftCrossUI")
                                .foregroundColor(CodexBarPalette.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Divider()
                    self.infoRow(label: "Provider implementations", value: "Canonical Swift registry")
                    Divider()
                    self.infoRow(label: "Linux backend", value: "GTK 4")
                    Divider()
                    self.infoRow(label: "Embedded browser", value: "None")
                    Divider()
                    HStack(spacing: 10) {
                        Button("Project website") {
                            if let url = URL(string: "https://codexbar.app") { self.openURL(url) }
                        }
                        Button("Source code") {
                            if let url = URL(string: "https://github.com/steipete/CodexBar") { self.openURL(url) }
                        }
                        Spacer()
                        Button("Close") { PlatformWindowController.shared.hideSettings() }
                    }
                }
            }
        }
    }
}

extension CodexBarRootView {
    private func providerDetail(_ provider: CodexBarCrossModel.ProviderRow) -> some View {
        let descriptor = ProviderDescriptorRegistry.descriptor(for: provider.id)
        let authentication = self.model.authenticationSummary(for: provider.id)
        return VStack(spacing: 18) {
            HStack(spacing: 12) {
                ProviderArtwork(
                    provider: provider.id,
                    fallback: self.providerGlyph(provider.id))
                    .frame(width: 24, height: 24, alignment: .center)
                    .padding(10)
                    .background(self.providerAccent(provider).opacity(0.16))
                    .cornerRadius(12)
                VStack(spacing: 3) {
                    Text(provider.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 7) {
                        Circle()
                            .fill(self.providerStatusColor(provider))
                            .frame(width: 7, height: 7)
                        Text(provider.remainingPercent.map { "\(Int($0.rounded()))% left" } ?? provider.statusLabel)
                            .foregroundColor(CodexBarPalette.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Toggle("Enabled", isOn: Binding(
                    get: { provider.enabled },
                    set: { self.model.setEnabled(provider.id, enabled: $0) }))
            }

            if self.model.isRefreshing {
                ProgressView("Refreshing provider")
            }

            if let error = provider.error {
                self.card {
                    Text(error)
                        .foregroundColor(Color(red: 0.92, green: 0.42, blue: 0.42))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let snapshot = provider.snapshot {
                self.usageCards(descriptor: descriptor, snapshot: snapshot)
            } else {
                self.card {
                    VStack(spacing: 12) {
                        Text(provider.enabled
                            ? "No usage has been loaded for this provider yet."
                            : "This provider is disabled.")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Refresh connection") {
                            Task { await self.model.refresh(provider.id) }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
            }

            self.sectionLabel("CONNECTION")
            self.card {
                VStack(spacing: 12) {
                    self.infoRow(label: "Status", value: provider.statusLabel)
                    Divider()
                    self.infoRow(label: "Source", value: provider.source ?? "Not checked")
                    Divider()
                    self.infoRow(
                        label: "Authentication",
                        value: authentication.configured ? "Configured" : "Not configured")
                    if !authentication.modes.isEmpty {
                        Divider()
                        self.infoRow(label: "Available modes", value: authentication.modes.joined(separator: ", "))
                    }
                    if let identity = provider.snapshot?.identity {
                        if self.model.preferences.showAccount {
                            Divider()
                            self.infoRow(
                                label: "Account",
                                value: self.maskedIfNeeded(identity.accountEmail ?? "—"))
                        }
                        if self.model.preferences.showPlan {
                            Divider()
                            self.infoRow(label: "Plan", value: identity.loginMethod ?? "—")
                        }
                    }
                }
            }

            self.sectionLabel("ACTIONS")
            self.card {
                HStack(spacing: 10) {
                    Button("Refresh now") {
                        Task { await self.model.refresh(provider.id) }
                    }
                    if let dashboard = descriptor.metadata.dashboardURL,
                       let url = URL(string: dashboard)
                    {
                        Button("Open Dashboard") { self.openURL(url) }
                    }
                    if let status = descriptor.metadata.statusLinkURL ?? descriptor.metadata.statusPageURL,
                       let url = URL(string: status)
                    {
                        Button("Status Page") { self.openURL(url) }
                    }
                    Spacer()
                }
            }
        }
    }

    private func usageCards(descriptor: ProviderDescriptor, snapshot: UsageSnapshot) -> some View {
        VStack(spacing: 12) {
            if let window = snapshot.primary {
                self.quotaCard(label: descriptor.metadata.sessionLabel, window: window)
            }
            if let window = snapshot.secondary {
                self.quotaCard(label: descriptor.metadata.weeklyLabel, window: window)
            }
            if let window = snapshot.tertiary {
                self.quotaCard(label: descriptor.metadata.opusLabel ?? "Additional quota", window: window)
            }
        }
    }

    private func quotaCard(label: String, window: RateWindow) -> some View {
        self.card {
            VStack(spacing: 10) {
                HStack {
                    Text(label)
                        .font(.headline)
                    Spacer()
                    Text("\(Int(window.remainingPercent.rounded()))% left")
                        .fontWeight(.bold)
                }
                if self.model.preferences.showUsageBars {
                    ProgressView(value: max(0, min(1, window.usedPercent / 100)))
                }
                if self.model.preferences.showResetTimes {
                    Text(UsageFormatter.resetLine(for: window, style: .countdown) ?? "Reset time unavailable")
                        .font(.caption)
                        .foregroundColor(CodexBarPalette.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func paneHeader(title: String, subtitle: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.title)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(subtitle)
                .foregroundColor(CodexBarPalette.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption)
            .fontWeight(.bold)
            .foregroundColor(CodexBarPalette.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func card(@ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(CodexBarPalette.cardBackground)
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(CodexBarPalette.cardBorder, style: StrokeStyle(width: 1))
                }
            }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(spacing: 16) {
            Text(label)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .foregroundColor(CodexBarPalette.secondaryText)
        }
    }

    private func settingToggleRow(
        title: String,
        subtitle: String,
        keyPath: WritableKeyPath<CodexBarCrossPreferences, Bool>) -> some View
    {
        HStack(spacing: 16) {
            VStack(spacing: 3) {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(CodexBarPalette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Toggle("", isOn: Binding(
                get: { self.model.preferences[keyPath: keyPath] },
                set: { self.model.setPreference(keyPath, to: $0) }))
        }
    }

    private func settingPickerRow(
        title: String,
        subtitle: String,
        options: [String],
        keyPath: WritableKeyPath<CodexBarCrossPreferences, String>) -> some View
    {
        HStack(spacing: 16) {
            VStack(spacing: 3) {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(CodexBarPalette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            PlatformPicker(
                options: options,
                selection: Binding<String?>(
                    get: { self.model.preferences[keyPath: keyPath] },
                    set: { value in
                        if let value { self.model.setPreference(keyPath, to: value) }
                    }))
                    .frame(minWidth: 150, idealWidth: 170, maxWidth: 190)
        }
    }

    private func settingSliderRow(
        title: String,
        value: Int,
        range: ClosedRange<Int>,
        keyPath: WritableKeyPath<CodexBarCrossPreferences, Int>,
        suffix: String) -> some View
    {
        HStack(spacing: 16) {
            VStack(spacing: 3) {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(value)\(suffix)")
                    .font(.caption)
                    .foregroundColor(CodexBarPalette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Slider(
                value: Binding<Int>(
                    get: { self.model.preferences[keyPath: keyPath] },
                    set: { self.model.setPreference(keyPath, to: $0) }),
                in: range)
                .frame(minWidth: 170, maxWidth: 230)
        }
    }

    private var formattedSpendTotal: String {
        guard !self.model.preferences.hideSensitiveValues else { return "••••" }
        guard let group = self.model.primarySpendGroup else { return "—" }
        return self.formattedCost(group.totalCost, currencyCode: group.currencyCode)
    }

    private var formattedSpendTokens: String {
        guard !self.model.preferences.hideSensitiveValues else { return "••••" }
        return self.formattedTokens(self.model.primarySpendGroup?.totalTokens)
    }

    private var spendDailyPoints: [SpendDashboardModel.DailyPoint] {
        self.model.primarySpendGroup?.dailyPoints ?? []
    }

    private func spendBarHeight(_ point: SpendDashboardModel.DailyPoint) -> Double {
        let maximum = self.spendDailyPoints.map(\.stackEnd).max() ?? 0
        guard maximum > 0 else { return 3 }
        return max(3, min(142, 142 * point.cost / maximum))
    }

    private func formattedCost(_ cost: Double?, currencyCode: String) -> String {
        guard !self.model.preferences.hideSensitiveValues else { return "••••" }
        guard let cost else { return "—" }
        return UsageFormatter.currencyString(cost, currencyCode: currencyCode)
    }

    private func formattedTokens(_ tokens: Int?) -> String {
        guard !self.model.preferences.hideSensitiveValues else { return "••••" }
        guard let tokens else { return "—" }
        return UsageFormatter.tokenCountString(tokens)
    }

    private func formattedSpendDay(_ day: Date?) -> String {
        guard let day else { return "" }
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(self.model.spendRange == .year ? "MMM yy" : "MMM d")
        return formatter.string(from: day)
    }

    private func isSelected(_ section: CodexBarCrossModel.Section) -> Bool {
        self.model.selectedProviderID == nil && self.model.section == section
    }

    private func providerStatusColor(_ provider: CodexBarCrossModel.ProviderRow) -> Color {
        switch provider.statusLabel {
        case "Connected": CodexBarPalette.connected
        case "Needs attention": CodexBarPalette.attention
        case "Ready": CodexBarPalette.ready
        default: CodexBarPalette.tertiaryText
        }
    }

    private func providerListState(
        _ provider: CodexBarCrossModel.ProviderRow) -> PlatformProviderListItem.State
    {
        switch provider.statusLabel {
        case "Connected": .connected
        case "Needs attention": .attention
        case "Ready": .ready
        default: .disabled
        }
    }

    private func providerAccent(_ provider: CodexBarCrossModel.ProviderRow) -> Color {
        Color(red: provider.accent.red, green: provider.accent.green, blue: provider.accent.blue)
    }

    private func sidebarGlyph(_ glyph: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.white.opacity(0.045))
            Text(glyph)
                .font(.caption)
                .foregroundColor(CodexBarPalette.secondaryText)
        }
        .frame(width: 20, height: 20)
    }

    private func maskedIfNeeded(_ value: String) -> String {
        self.model.preferences.hideSensitiveValues ? "••••" : value
    }

    private func sectionGlyph(_ section: CodexBarCrossModel.Section) -> String {
        switch section {
        case .general: "⌂"
        case .spend: "▥"
        case .notifications: "◉"
        case .menuBar: "▰"
        case .menu: "☰"
        case .advanced: "⚙"
        case .about: "ⓘ"
        }
    }

    private func providerGlyph(_ provider: UsageProvider) -> String {
        // Provider-specific by design: these compact fallbacks mirror recognizable first-party provider marks.
        switch provider {
        case .codex: "◉"
        case .claude: "✳"
        case .cursor: "◆"
        case .gemini: "✦"
        case .copilot: "▣"
        default: "◇"
        }
    }
}

struct ModelObservedRegion<Content: View>: View {
    @State private var model: CodexBarCrossModel
    private let content: () -> Content

    init(
        model: CodexBarCrossModel,
        @ViewBuilder content: @escaping () -> Content)
    {
        self._model = State(wrappedValue: model)
        self.content = content
    }

    var body: some View {
        self.content(observing: self.model)
    }

    private func content(observing _: CodexBarCrossModel) -> Content {
        self.content()
    }
}

private struct PublishedObservedRegion<Value, Content: View>: View {
    @State private var observation: SwiftCrossUI.Published<Value>
    private let content: () -> Content

    init(
        observation: SwiftCrossUI.Published<Value>,
        @ViewBuilder content: @escaping () -> Content)
    {
        self._observation = State(wrappedValue: observation)
        self.content = content
    }

    var body: some View {
        self.content(observing: self.observation.wrappedValue)
    }

    private func content(observing _: Value) -> Content {
        self.content()
    }
}

private struct SearchObservedRegion<Content: View>: View {
    @State private var navigation: CodexBarCrossNavigationModel
    private let content: () -> Content

    init(
        navigation: CodexBarCrossNavigationModel,
        @ViewBuilder content: @escaping () -> Content)
    {
        self._navigation = State(wrappedValue: navigation)
        self.content = content
    }

    var body: some View {
        self.content(observing: self.navigation.searchQuery)
    }

    private func content(observing _: String) -> Content {
        self.content()
    }
}

private enum ContentCacheKey: Hashable {
    case section(CodexBarCrossModel.Section)
    case provider
}

enum CodexBarPalette {
    static let windowGradient = [
        Color(red: 0.105, green: 0.11, blue: 0.135),
        Color(red: 0.055, green: 0.065, blue: 0.085),
        Color(red: 0.075, green: 0.055, blue: 0.105),
    ]
    static let primaryText = Color(white: 0.95)
    static let secondaryText = Color(white: 0.69)
    static let tertiaryText = Color(white: 0.46)
    static let sidebarBackground = Color(red: 0.035, green: 0.04, blue: 0.055, opacity: 0.82)
    static let cardBackground = Color(red: 0.15, green: 0.155, blue: 0.18, opacity: 0.78)
    static let cardBorder = Color(white: 0.84, opacity: 0.16)
    static let selectionBackground = Color(red: 0.12, green: 0.39, blue: 0.44, opacity: 0.82)
    static let accent = Color(red: 0.31, green: 0.67, blue: 0.72)
    static let connected = Color(red: 0.35, green: 0.84, blue: 0.58)
    static let ready = Color(red: 0.43, green: 0.69, blue: 0.91)
    static let attention = Color(red: 0.92, green: 0.42, blue: 0.42)
}

#endif
