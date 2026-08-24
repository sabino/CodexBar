#if CrossPlatformApp

@_spi(Backends) import SwiftCrossUI

#if os(Linux)
import CGtk
import Gtk
import GtkBackend

/// Mounts GTK's picker as the view-graph widget itself.
///
/// SwiftCrossUI's built-in picker and `GtkWidgetRepresentable` both place the
/// native control in a fixed container. GTK then creates the drop-down popover
/// against that intermediate surface, which can leave the popover with a stale
/// input grab after an i3 move or resize. Returning the `Gtk.DropDown` directly
/// keeps its popup, focus, and hit testing native.
struct PlatformPicker: View {
    typealias Content = EmptyView

    let options: [String]
    let selection: Binding<String?>
    var body = EmptyView()

    func children(
        backend: some BaseAppBackend,
        snapshots _: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment _: EnvironmentValues) -> any ViewGraphNodeChildren
    {
        guard backend is GtkBackend else {
            preconditionFailure("PlatformPicker requires GtkBackend on Linux")
        }
        let children = PlatformPickerChildren(picker: Gtk.DropDown(strings: []))
        children.picker.notifySelected = { [weak children] picker, _ in
            guard let children, !children.isSynchronizing else { return }
            let invalidSelection = Int(Int32(bitPattern: GTK_INVALID_LIST_POSITION))
            let value = picker.selected == invalidSelection
                ? nil
                : children.options[safe: picker.selected]
            children.select?(value)
        }
        return children
    }

    func layoutableChildren(
        backend _: some BaseAppBackend,
        children _: any ViewGraphNodeChildren) -> [LayoutSystem.LayoutableChild]
    {
        []
    }

    func asWidget<Backend: BaseAppBackend>(
        _ children: any ViewGraphNodeChildren,
        backend _: Backend) -> Backend.Widget
    {
        guard let widget = Self.typed(children).picker as? Backend.Widget else {
            preconditionFailure("PlatformPicker requires GtkBackend on Linux")
        }
        return widget
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children untypedChildren: any ViewGraphNodeChildren,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend) -> ViewLayoutResult
    {
        guard backend is GtkBackend else {
            preconditionFailure("PlatformPicker requires GtkBackend on Linux")
        }
        let children = Self.typed(untypedChildren)
        let picker = children.picker
        children.select = { value in
            self.selection.wrappedValue = value
        }
        children.isSynchronizing = true
        defer { children.isSynchronizing = false }

        if children.options != self.options {
            Self.replaceOptions(of: picker, with: self.options)
            children.options = self.options
        }

        let invalidSelection = Int(Int32(bitPattern: GTK_INVALID_LIST_POSITION))
        let selectedIndex = self.selection.wrappedValue
            .flatMap(self.options.firstIndex(of:)) ?? invalidSelection
        if picker.selected != selectedIndex {
            picker.selected = selectedIndex
        }
        picker.sensitive = environment.isEnabled

        let naturalSize = backend.naturalSize(of: widget)
        let size = naturalSize == SIMD2(-1, -1)
            ? proposedSize.replacingUnspecifiedDimensions(by: ViewSize(10, 10))
            : ViewSize(Double(naturalSize.x), Double(naturalSize.y))
        return ViewLayoutResult.leafView(size: size)
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children _: any ViewGraphNodeChildren,
        layout: ViewLayoutResult,
        environment _: EnvironmentValues,
        backend: Backend)
    {
        backend.setSize(of: widget, to: layout.size.vector)
    }

    private static func replaceOptions(of picker: Gtk.DropDown, with options: [String]) {
        let stringBuffers = options.map { $0.unsafeUTF8Copy() }
        let stringPointers = stringBuffers.map { UnsafePointer($0.baseAddress) }
        let pointerBuffer = stringPointers.unsafeCopy()
        defer {
            pointerBuffer.deallocate()
            stringBuffers.forEach { $0.deallocate() }
        }
        picker.model = gtk_string_list_new(pointerBuffer.baseAddress)
    }

    private static func typed(_ children: any ViewGraphNodeChildren) -> PlatformPickerChildren {
        guard let children = children as? PlatformPickerChildren else {
            preconditionFailure("PlatformPicker received incompatible graph children")
        }
        return children
    }
}

@MainActor
private final class PlatformPickerChildren: ViewGraphNodeChildren {
    let picker: Gtk.DropDown
    var options: [String] = []
    var select: ((String?) -> Void)?
    var isSynchronizing = false

    init(picker: Gtk.DropDown) {
        self.picker = picker
    }

    var widgets: [AnyWidget] {
        [AnyWidget(self.picker)]
    }

    var erasedNodes: [ErasedViewGraphNode] {
        []
    }
}

#else

struct PlatformPicker: View {
    let options: [String]
    let selection: Binding<String?>

    var body: some View {
        Picker(of: self.options, selection: self.selection)
    }
}

#endif

extension Collection {
    fileprivate subscript(safe index: Index) -> Element? {
        self.indices.contains(index) ? self[index] : nil
    }
}

#endif
