#if os(Linux)
import Dispatch
import Gtk
import GtkCHelpers

private typealias GtkRootResizeCallback =
    @convention(c) (UnsafeMutableRawPointer?, CustomWidgetSize) -> Void

/// Coalesces GTK's live-resize allocation stream before it reaches SwiftCrossUI.
///
/// SwiftCrossUI performs minimum, unbounded, and final layout probes for every root
/// allocation. During an interactive drag those synchronous passes can block GTK from
/// processing the next pointer event. The native root still receives each allocation;
/// only the expensive shared Swift layout callback is delayed until the stream has been
/// quiet for a short interval.
@MainActor
enum LinuxWindowResizeCoalescer {
    private static var contexts: [UInt: ResizeContext] = [:]

    static func install(on window: Gtk.ApplicationWindow) {
        guard let root = window.getChild() as? CustomRootWidget else { return }
        let rawRoot = UnsafeMutableRawPointer(root.widgetPointer)
        let identity = UInt(bitPattern: rawRoot)
        guard self.contexts[identity] == nil else { return }

        let customRoot = rawRoot.assumingMemoryBound(to: GtkCustomRootWidget.self)
        guard let originalCallback = customRoot.pointee.resize_callback else { return }
        let context = ResizeContext(
            originalCallback: originalCallback,
            originalData: customRoot.pointee.resize_callback_data)
        self.contexts[identity] = context
        gtk_custom_root_widget_set_resize_callback(
            customRoot,
            coalescedGtkRootResizeCallback,
            Unmanaged.passUnretained(context).toOpaque())
    }
}

private final class ResizeContext: @unchecked Sendable {
    private let originalCallback: GtkRootResizeCallback
    private let originalData: UnsafeMutableRawPointer?
    private var latestSize: CustomWidgetSize?
    private var pendingWorkItem: DispatchWorkItem?
    private var generation: UInt64 = 0

    init(
        originalCallback: @escaping GtkRootResizeCallback,
        originalData: UnsafeMutableRawPointer?)
    {
        self.originalCallback = originalCallback
        self.originalData = originalData
    }

    func receive(_ size: CustomWidgetSize) {
        self.latestSize = size
        self.generation &+= 1
        let scheduledGeneration = self.generation
        self.pendingWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self,
                  self.generation == scheduledGeneration,
                  let latestSize = self.latestSize
            else { return }
            self.pendingWorkItem = nil
            self.originalCallback(self.originalData, latestSize)
        }
        self.pendingWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(120),
            execute: workItem)
    }
}

private let coalescedGtkRootResizeCallback: GtkRootResizeCallback = { data, size in
    guard let data else { return }
    let context = Unmanaged<ResizeContext>.fromOpaque(data).takeUnretainedValue()
    context.receive(size)
}
#endif
