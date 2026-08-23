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

struct CodexBarMiniView: View {
    @State private var model: CodexBarCrossModel
    @State private var selectedProviderID: UsageProvider
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow

    init(model: CodexBarCrossModel) {
        self._model = State(wrappedValue: model)
        let initial = model.providers.first(where: { $0.id == .codex && $0.enabled })?.id
            ?? model.providers.first(where: \.enabled)?.id
            ?? .codex
        self._selectedProviderID = State(wrappedValue: initial)
    }

    var body: some View {
        ModelObservedRegion(model: self.model) {
            VStack(spacing: 0) {
                self.titleBar
                Divider()
                self.providerSwitcher
                Divider()
                ScrollView {
                    self.providerContent
                        .padding(18)
                }
                self.footer
            }
        }
        .frame(minWidth: 390, minHeight: 500)
        .background(LinearGradient(
            colors: CodexBarPalette.windowGradient,
            startPoint: .topLeading,
            endPoint: .bottomTrailing))
        .foregroundColor(CodexBarPalette.primaryText)
        .colorScheme(.dark)
        #if os(Linux)
            .inspectWindow { window in
                PlatformWindowController.shared.attachMiniWindow(window)
                LinuxWindowResizeCoalescer.install(on: window)
                window.setEscapeKeyPressedHandler {
                    PlatformWindowController.shared.hideMini()
                }
            }
        #elseif os(macOS)
            .inspectWindow { window in
                PlatformWindowController.shared.attachMiniWindow(window)
            }
        #elseif os(Windows)
            .inspectWindow { window in
                PlatformWindowController.shared.attachMiniWindow(window)
            }
        #endif
            .onChange(of: self.model.providerContentRevision, initial: true) {
                    self.updateTray()
                }
                .onChange(of: self.selectedProviderID, initial: true) {
                    self.updateTray()
                }
                .task {
                    self.model.startAutomaticHistoryMaintenance()
                    await self.model.refresh(self.selectedProviderID, interaction: .background)
                }
    }

    private var titleBar: some View {
        HStack(spacing: 10) {
            Text("CodexBar")
                .font(.headline)
                .fontWeight(.bold)
            Spacer()
            Button {
                Task { await self.model.refresh(self.selectedProviderID) }
            } label: {
                Text(self.model.isRefreshing ? "…" : "↻")
                    .font(.headline)
                    .frame(width: 30, height: 28)
            }
            .buttonStyle(.plain)
            Button {
                PlatformWindowController.shared.hideMini()
                self.openWindow(id: "settings")
            } label: {
                Text("⚙")
                    .frame(width: 30, height: 28)
            }
            .buttonStyle(.plain)
            Button {
                PlatformWindowController.shared.hideMini()
            } label: {
                Text("×")
                    .font(.title2)
                    .frame(width: 30, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(CodexBarPalette.sidebarBackground)
    }

    private var providerSwitcher: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(self.switcherProviders) { provider in
                    Button {
                        self.selectedProviderID = provider.id
                        Task { await self.model.refresh(provider.id) }
                    } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                ProviderArtwork(
                                    provider: provider.id,
                                    fallback: self.providerGlyph(provider.id))
                                    .frame(width: 22, height: 22)
                                Circle()
                                    .fill(self.statusColor(provider))
                                    .frame(width: 6, height: 6)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            }
                            .frame(width: 28, height: 24)
                            Text(provider.shortName)
                                .font(.caption)
                                .lineLimit(1)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(self.selectedProviderID == provider.id
                                    ? self.accent(provider)
                                    : Color.clear)
                                .frame(width: 30, height: 2)
                        }
                        .frame(width: 64, height: 58)
                        .background(self.selectedProviderID == provider.id
                            ? Color.white.opacity(0.09)
                            : Color.clear)
                        .cornerRadius(9)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(height: 76)
        .background(CodexBarPalette.sidebarBackground.opacity(0.72))
    }

    @ViewBuilder
    private var providerContent: some View {
        if let provider = self.selectedProvider {
            VStack(spacing: 14) {
                self.providerHeader(provider)
                if let error = provider.error {
                    self.card {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(CodexBarPalette.attention)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let snapshot = provider.snapshot {
                    let lanes = self.usageLanes(provider: provider, snapshot: snapshot)
                    if lanes.isEmpty {
                        self.emptyUsageCard(provider)
                    } else {
                        ForEach(lanes) { lane in
                            self.quotaCard(lane)
                        }
                    }
                    if let cost = snapshot.providerCost {
                        self.costCard(cost)
                    }
                } else {
                    self.emptyUsageCard(provider)
                }
                if let credits = provider.credits {
                    self.card {
                        HStack {
                            VStack(spacing: 3) {
                                Text("CREDITS")
                                    .font(.caption)
                                    .foregroundColor(CodexBarPalette.tertiaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(String(format: "%.2f remaining", credits.remaining))
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Spacer()
                        }
                    }
                }
            }
        } else {
            Text("No providers are enabled.")
                .foregroundColor(CodexBarPalette.secondaryText)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Divider()
            HStack(spacing: 10) {
                Button("Usage & Spend") {
                    self.model.select(.spend)
                    PlatformWindowController.shared.hideMini()
                    self.openWindow(id: "settings")
                }
                if let dashboardURL = self.selectedDashboardURL {
                    Button("Dashboard") {
                        self.openURL(dashboardURL)
                    }
                }
                Spacer()
                Button("Hide") {
                    PlatformWindowController.shared.hideMini()
                }
            }
            Text(self.updatedText)
                .font(.caption)
                .foregroundColor(CodexBarPalette.tertiaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(CodexBarPalette.sidebarBackground.opacity(0.78))
    }

    private var switcherProviders: [CodexBarCrossModel.ProviderRow] {
        let enabled = self.model.providers.filter(\.enabled)
        return enabled.isEmpty ? Array(self.model.providers.prefix(8)) : enabled
    }

    private var selectedProvider: CodexBarCrossModel.ProviderRow? {
        self.model.providers.first(where: { $0.id == self.selectedProviderID })
            ?? self.switcherProviders.first
    }

    private var selectedDashboardURL: URL? {
        guard let selectedProvider else { return nil }
        let descriptor = ProviderDescriptorRegistry.descriptor(for: selectedProvider.id)
        return descriptor.metadata.dashboardURL.flatMap(URL.init(string:))
    }

    private var updatedText: String {
        guard let updated = self.selectedProvider?.snapshot?.updatedAt ?? self.model.lastUpdated else {
            return self.selectedProvider?.source ?? "Ready"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "Updated \(formatter.string(from: updated))"
    }

    private func providerHeader(_ provider: CodexBarCrossModel.ProviderRow) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(self.accent(provider).opacity(0.17))
                ProviderArtwork(
                    provider: provider.id,
                    fallback: self.providerGlyph(provider.id))
                    .frame(width: 28, height: 28)
            }
            .frame(width: 48, height: 48)
            VStack(spacing: 3) {
                Text(provider.name)
                    .font(.title2)
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(self.providerIdentity(provider))
                    .foregroundColor(CodexBarPalette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 6) {
                Circle()
                    .fill(self.statusColor(provider))
                    .frame(width: 7, height: 7)
                Text(provider.statusLabel)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.06))
            .cornerRadius(15)
        }
    }

    private func providerIdentity(_ provider: CodexBarCrossModel.ProviderRow) -> String {
        let identity = provider.snapshot?.identity
        let values = [identity?.accountEmail, identity?.loginMethod, provider.source]
            .compactMap(\.self)
            .filter { !$0.isEmpty }
        return values.isEmpty ? provider.statusLabel : values.joined(separator: " · ")
    }

    private func usageLanes(
        provider: CodexBarCrossModel.ProviderRow,
        snapshot: UsageSnapshot) -> [MiniUsageLane]
    {
        let metadata = ProviderDescriptorRegistry.descriptor(for: provider.id).metadata
        var lanes: [MiniUsageLane] = []
        if let primary = snapshot.primary, !primary.isSyntheticPlaceholder {
            lanes.append(MiniUsageLane(id: "primary", label: metadata.sessionLabel, window: primary))
        }
        if let secondary = snapshot.secondary {
            lanes.append(MiniUsageLane(id: "secondary", label: metadata.weeklyLabel, window: secondary))
        }
        if let tertiary = snapshot.tertiary {
            lanes.append(MiniUsageLane(
                id: "tertiary",
                label: metadata.opusLabel ?? "Additional quota",
                window: tertiary))
        }
        for extra in snapshot.extraRateWindows ?? [] where extra.usageKnown {
            lanes.append(MiniUsageLane(id: extra.id, label: extra.title, window: extra.window))
        }
        return lanes
    }

    private func quotaCard(_ lane: MiniUsageLane) -> some View {
        self.card {
            VStack(spacing: 9) {
                HStack {
                    Text(lane.label)
                        .font(.headline)
                    Spacer()
                    Text("\(Int(lane.window.remainingPercent.rounded()))% left")
                        .fontWeight(.bold)
                }
                ProgressView(value: max(0, min(1, lane.window.usedPercent / 100)))
                Text(UsageFormatter.resetLine(for: lane.window, style: .countdown) ?? "Reset time unavailable")
                    .font(.caption)
                    .foregroundColor(CodexBarPalette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func emptyUsageCard(_ provider: CodexBarCrossModel.ProviderRow) -> some View {
        self.card {
            VStack(spacing: 10) {
                Text(provider.enabled ? "Usage is not available yet." : "This provider is disabled.")
                    .foregroundColor(CodexBarPalette.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Refresh provider") {
                    Task { await self.model.refresh(provider.id) }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func costCard(_ cost: ProviderCostSnapshot) -> some View {
        self.card {
            VStack(spacing: 8) {
                HStack {
                    Text(cost.period ?? "Cost")
                        .font(.headline)
                    Spacer()
                    Text(self.currency(cost.used, code: cost.currencyCode))
                        .fontWeight(.bold)
                }
                if cost.limit > 0 {
                    ProgressView(value: max(0, min(1, cost.used / cost.limit)))
                    Text("\(self.currency(cost.used, code: cost.currencyCode)) of "
                        + self.currency(cost.limit, code: cost.currencyCode))
                        .font(.caption)
                        .foregroundColor(CodexBarPalette.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func card(@ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(14)
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

    private func statusColor(_ provider: CodexBarCrossModel.ProviderRow) -> Color {
        switch provider.statusLabel {
        case "Connected": CodexBarPalette.connected
        case "Needs attention": CodexBarPalette.attention
        case "Ready": CodexBarPalette.ready
        default: CodexBarPalette.tertiaryText
        }
    }

    private func accent(_ provider: CodexBarCrossModel.ProviderRow) -> Color {
        Color(red: provider.accent.red, green: provider.accent.green, blue: provider.accent.blue)
    }

    private func providerGlyph(_ provider: UsageProvider) -> String {
        switch provider {
        case .codex: "◉"
        case .claude: "✳"
        case .cursor: "◆"
        case .gemini: "✦"
        case .copilot: "▣"
        default: "◇"
        }
    }

    private func currency(_ amount: Double, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f %@", amount, code)
    }

    private func updateTray() {
        guard let provider = self.selectedProvider else {
            PlatformTrayController.shared.installOrUpdate(state: .error, tooltip: "CodexBar · No provider")
            return
        }
        let state: CrossTrayIconState = if self.model.isRefreshing {
            .loading
        } else if provider.error != nil {
            .error
        } else if let remaining = provider.remainingPercent {
            if remaining <= 20 {
                .red
            } else if remaining <= 50 {
                .amber
            } else {
                .green
            }
        } else {
            .error
        }
        let quota = provider.remainingPercent.map { " · \(Int($0.rounded()))% left" } ?? ""
        PlatformTrayController.shared.installOrUpdate(
            state: state,
            tooltip: "CodexBar · \(provider.name)\(quota)")
    }
}

private struct MiniUsageLane: Identifiable {
    let id: String
    let label: String
    let window: RateWindow
}
