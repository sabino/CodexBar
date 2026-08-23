import CodexBarCore
import SwiftCrossUI

struct PlatformProviderListItem: Identifiable, Equatable {
    enum State: Equatable {
        case connected
        case attention
        case ready
        case disabled
    }

    let id: UsageProvider
    let title: String
    let symbol: String
    let iconPath: String?
    let state: State
}

#if os(Linux)
import Gtk
import GtkBackend

/// The GTK shim owns native row layout so SwiftCrossUI does not eagerly re-layout every provider
/// while the window resizes. Provider behavior and selection remain in the shared Swift model.
struct PlatformProviderList: GtkWidgetRepresentable {
    final class Coordinator {
        struct Row {
            let id: UsageProvider
            let container: Gtk.Box
            let title: Gtk.Label
            let status: Gtk.Label
        }

        let list = Gtk.ListBox()
        var items: [PlatformProviderListItem] = []
        var rows: [Row] = []
        var select: ((UsageProvider) -> Void)?
        var appliedSelection: UsageProvider?
    }

    let items: () -> [PlatformProviderListItem]
    let selection: Binding<UsageProvider?>

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeGtkWidget(context: Context) -> Gtk.ScrolledWindow {
        let scrollView = Gtk.ScrolledWindow()
        scrollView.expandHorizontally = true
        scrollView.expandVertically = true
        scrollView.setScrollBarPresence(hasVerticalScrollBar: true, hasHorizontalScrollBar: false)
        // Disable GTK's transient overlay thumb so a long provider list always has a visible
        // scrolling affordance, including under tiling window managers with no window chrome.
        scrollView.setProperty(named: "overlay-scrolling", newValue: false)
        scrollView.css.set(properties: [
            CSSProperty(key: "background", value: "transparent"),
            CSSProperty(key: "border", value: "none"),
        ], clear: true)

        let list = context.coordinator.list
        list.selectionMode = .single
        list.activateOnSingleClick = true
        list.expandHorizontally = true
        list.css.set(properties: [
            CSSProperty(key: "background", value: "transparent"),
            CSSProperty(key: "padding", value: "0"),
        ], clear: true)
        scrollView.setChild(list)
        return scrollView
    }

    func updateGtkWidget(_ scrollView: Gtk.ScrolledWindow, context: Context) {
        let coordinator = context.coordinator
        coordinator.select = { provider in
            self.selection.wrappedValue = provider
        }

        let items = self.items()
        if coordinator.items != items {
            Self.rebuildRows(coordinator: coordinator, items: items)
        }
        Self.synchronizeSelection(
            coordinator: coordinator,
            selection: self.selection.wrappedValue)

        scrollView.sensitive = context.environment.isEnabled
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        gtkWidget _: Gtk.ScrolledWindow,
        context _: Context) -> ViewSize
    {
        // The sidebar has a fixed outer width and this list is its flexible remainder.
        // Asking Gtk for the natural size walks every provider row during each
        // SwiftCrossUI probe, including every intermediate live-resize event.
        ViewSize(
            max(proposal.width ?? 180, 180),
            max(proposal.height ?? 120, 120))
    }

    private static func rebuildRows(
        coordinator: Coordinator,
        items: [PlatformProviderListItem])
    {
        coordinator.list.removeAll()
        coordinator.rows.removeAll(keepingCapacity: true)
        coordinator.appliedSelection = nil

        for item in items {
            let row = Gtk.Box(orientation: .horizontal, spacing: 8)
            row.expandHorizontally = true
            row.marginTop = 5
            row.marginBottom = 5
            row.marginStart = 8
            row.marginEnd = 8

            let artwork: Gtk.Widget
            if let iconPath = item.iconPath {
                let icon = Gtk.Image(filename: iconPath)
                icon.pixelSize = 18
                icon.setSizeRequest(width: 20, height: 20)
                artwork = icon
            } else {
                let symbol = Gtk.Label(string: item.symbol)
                symbol.widthChars = 2
                symbol.xalign = 0.5
                symbol.css.set(properties: [
                    CSSProperty(key: "color", value: "rgba(196, 201, 214, 0.82)"),
                    .fontSize(12),
                ], clear: true)
                artwork = symbol
            }

            let title = Gtk.Label(string: item.title)
            title.expandHorizontally = true
            title.horizontalAlignment = .fill
            title.xalign = 0
            title.ellipsize = .end
            title.singleLineMode = true
            title.css.set(properties: [
                CSSProperty(key: "color", value: "rgba(242, 243, 247, 0.96)"),
                .fontSize(13),
            ], clear: true)

            let status = Gtk.Label(string: "●")
            status.css.set(properties: [
                CSSProperty(key: "color", value: Self.statusColor(item.state)),
                .fontSize(10),
            ], clear: true)

            row.add(artwork)
            row.add(title)
            row.add(status)

            let click = Gtk.GestureClick()
            click.released = { [weak coordinator] _, _, _, _ in
                coordinator?.select?(item.id)
            }
            row.addEventController(click)
            coordinator.list.append(row)
            coordinator.rows.append(Coordinator.Row(
                id: item.id,
                container: row,
                title: title,
                status: status))
        }
        coordinator.items = items
    }

    private static func synchronizeSelection(
        coordinator: Coordinator,
        selection: UsageProvider?)
    {
        guard coordinator.appliedSelection != selection else { return }
        coordinator.appliedSelection = selection
        guard let selection,
              let index = coordinator.rows.firstIndex(where: { $0.id == selection })
        else {
            coordinator.list.unselectAll()
            return
        }
        coordinator.list.selectRow(at: index)
    }

    private static func statusColor(_ state: PlatformProviderListItem.State) -> String {
        switch state {
        case .connected: "rgb(89, 214, 148)"
        case .attention: "rgb(235, 107, 107)"
        case .ready: "rgb(110, 176, 232)"
        case .disabled: "rgba(150, 154, 166, 0.55)"
        }
    }
}

#else

/// AppKit and WinUI use SwiftCrossUI's native selectable-list backend through the same API.
struct PlatformProviderList: View {
    let items: () -> [PlatformProviderListItem]
    let selection: Binding<UsageProvider?>

    var body: some View {
        ScrollView {
            List(self.items(), selection: self.selection) { item in
                HStack(spacing: 8) {
                    ProviderArtwork(provider: item.id, fallback: item.symbol)
                        .frame(width: 18, height: 18)
                    Text(item.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Circle()
                        .fill(self.statusColor(item.state))
                        .frame(width: 7, height: 7)
                }
            }
        }
    }

    private func statusColor(_ state: PlatformProviderListItem.State) -> Color {
        switch state {
        case .connected: Color(red: 0.35, green: 0.84, blue: 0.58)
        case .attention: Color(red: 0.92, green: 0.42, blue: 0.42)
        case .ready: Color(red: 0.43, green: 0.69, blue: 0.91)
        case .disabled: Color(white: 0.58, opacity: 0.55)
        }
    }
}

#endif
