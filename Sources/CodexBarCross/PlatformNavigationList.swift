import CodexBarCrossSupport
import SwiftCrossUI

struct PlatformNavigationItem: Identifiable, Equatable {
    let id: CodexBarCrossSection
    let title: String
    let symbol: String
}

#if os(Linux)
import Gtk
import GtkBackend

/// Native GTK navigation rows avoid rebuilding the SwiftCrossUI sidebar layout for
/// button press and release state while retaining the shared route binding.
struct PlatformNavigationList: GtkWidgetRepresentable {
    final class Coordinator {
        struct Row {
            let id: CodexBarCrossSection
            let container: Gtk.Box
            let symbol: Gtk.Label
            let title: Gtk.Label
        }

        let list = Gtk.ListBox()
        var items: [PlatformNavigationItem] = []
        var rows: [Row] = []
        var select: ((CodexBarCrossSection) -> Void)?
        var appliedSelection: CodexBarCrossSection?
    }

    let items: [PlatformNavigationItem]
    let selection: Binding<CodexBarCrossSection?>

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeGtkWidget(context: Context) -> Gtk.ListBox {
        let list = context.coordinator.list
        list.selectionMode = .none
        list.expandHorizontally = true
        list.css.set(properties: [
            CSSProperty(key: "background", value: "transparent"),
            CSSProperty(key: "padding", value: "0"),
        ], clear: true)
        return list
    }

    func updateGtkWidget(_ list: Gtk.ListBox, context: Context) {
        let coordinator = context.coordinator
        coordinator.select = { section in
            self.selection.wrappedValue = section
        }
        if coordinator.items != self.items {
            Self.rebuildRows(coordinator: coordinator, items: self.items)
        }
        Self.synchronizeSelection(
            coordinator: coordinator,
            selection: self.selection.wrappedValue)
        list.sensitive = context.environment.isEnabled
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        gtkWidget _: Gtk.ListBox,
        context _: Context) -> ViewSize
    {
        ViewSize(max(proposal.width ?? 200, 200), 244)
    }

    private static func rebuildRows(
        coordinator: Coordinator,
        items: [PlatformNavigationItem])
    {
        coordinator.list.removeAll()
        coordinator.rows.removeAll(keepingCapacity: true)
        coordinator.appliedSelection = nil

        for item in items {
            let row = Gtk.Box(orientation: .horizontal, spacing: 10)
            row.expandHorizontally = true
            row.marginTop = 2
            row.marginBottom = 2
            row.marginStart = 0
            row.marginEnd = 0

            let symbol = Gtk.Label(string: item.symbol)
            symbol.widthChars = 2
            symbol.xalign = 0.5
            symbol.css.set(properties: [.fontSize(12)], clear: true)

            let title = Gtk.Label(string: item.title)
            title.expandHorizontally = true
            title.horizontalAlignment = .fill
            title.xalign = 0
            title.singleLineMode = true
            title.css.set(properties: [.fontSize(13)], clear: true)

            row.add(symbol)
            row.add(title)

            let click = Gtk.GestureClick()
            click.released = { [weak coordinator] _, _, _, _ in
                coordinator?.select?(item.id)
            }
            row.addEventController(click)
            coordinator.list.append(row)
            coordinator.rows.append(Coordinator.Row(
                id: item.id,
                container: row,
                symbol: symbol,
                title: title))
        }
        coordinator.items = items
    }

    private static func synchronizeSelection(
        coordinator: Coordinator,
        selection: CodexBarCrossSection?)
    {
        guard coordinator.appliedSelection != selection else { return }
        coordinator.appliedSelection = selection

        for row in coordinator.rows {
            let isSelected = row.id == selection
            row.container.css.set(properties: [
                CSSProperty(
                    key: "background",
                    value: isSelected ? "rgba(31, 100, 112, 0.82)" : "transparent"),
                CSSProperty(key: "border-radius", value: "8px"),
                CSSProperty(key: "padding", value: "7px 6px"),
            ], clear: true)
            let foreground = isSelected
                ? "rgba(248, 249, 252, 0.98)"
                : "rgba(226, 228, 235, 0.92)"
            row.symbol.css.set(properties: [
                CSSProperty(key: "color", value: foreground),
                .fontSize(12),
            ], clear: true)
            row.title.css.set(properties: [
                CSSProperty(key: "color", value: foreground),
                .fontSize(13),
            ], clear: true)
        }
    }
}

#else

struct PlatformNavigationList: View {
    let items: [PlatformNavigationItem]
    let selection: Binding<CodexBarCrossSection?>

    var body: some View {
        VStack(spacing: 2) {
            ForEach(self.items) { item in
                Button {
                    self.selection.wrappedValue = item.id
                } label: {
                    HStack(spacing: 10) {
                        Text(item.symbol)
                        Text(item.title)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(self.selection.wrappedValue == item.id
                        ? Color(red: 0.12, green: 0.39, blue: 0.44, opacity: 0.82)
                        : Color.clear)
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
    }
}

#endif
