import SwiftCrossUI

#if os(Linux)
import CGtk
import Gtk
import GtkBackend

/// Uses GTK's picker directly so its popup remains interactive inside the SwiftCrossUI
/// settings hierarchy. The shared picker adapter currently adds an extra fixed container
/// that lets the control focus but prevents its popup from being presented.
struct PlatformPicker: GtkWidgetRepresentable {
    final class Coordinator {
        let picker = Gtk.DropDown(strings: [])
        var options: [String] = []
        var select: ((String?) -> Void)?
        var isSynchronizing = false
    }

    let options: [String]
    let selection: Binding<String?>

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeGtkWidget(context: Context) -> Gtk.DropDown {
        let coordinator = context.coordinator
        let picker = coordinator.picker
        picker.notifySelected = { [weak coordinator] picker, _ in
            guard let coordinator, !coordinator.isSynchronizing else { return }
            let invalidSelection = Int(Int32(bitPattern: GTK_INVALID_LIST_POSITION))
            let value = picker.selected == invalidSelection
                ? nil
                : coordinator.options[safe: picker.selected]
            coordinator.select?(value)
        }
        return picker
    }

    func updateGtkWidget(_ picker: Gtk.DropDown, context: Context) {
        let coordinator = context.coordinator
        coordinator.select = { value in
            self.selection.wrappedValue = value
        }
        coordinator.isSynchronizing = true
        defer { coordinator.isSynchronizing = false }

        if coordinator.options != self.options {
            Self.replaceOptions(of: picker, with: self.options)
            coordinator.options = self.options
        }

        let invalidSelection = Int(Int32(bitPattern: GTK_INVALID_LIST_POSITION))
        let selectedIndex = self.selection.wrappedValue
            .flatMap(self.options.firstIndex(of:)) ?? invalidSelection
        if picker.selected != selectedIndex {
            picker.selected = selectedIndex
        }
        picker.sensitive = context.environment.isEnabled
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
