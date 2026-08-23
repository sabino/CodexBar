#if os(Linux)
import CGtk
import CodexBarCrossSupport
import Gtk
import GtkCHelpers

private typealias GtkRootResizeCallback =
    @convention(c) (UnsafeMutableRawPointer?, CustomWidgetSize) -> Void
private typealias GtkSourceCallback =
    @convention(c) (UnsafeMutableRawPointer?) -> gboolean

/// Throttles GTK's live-resize allocation stream before it reaches SwiftCrossUI.
///
/// SwiftCrossUI performs minimum, unbounded, and final layout probes for every root
/// allocation. During an interactive drag those passes can block GTK from processing the
/// next pointer event. Deliver the leading allocation immediately, then the latest
/// allocation at a bounded cadence so the content follows an i3 resize without queuing a
/// complete Swift layout pass for every pointer event.
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
    private struct WindowSize: Equatable {
        let width: Int32
        let height: Int32
    }

    private static let deliveryIntervalMilliseconds: UInt32 = 140
    private static let quietPeriodMilliseconds: UInt32 = 45

    private let originalCallback: GtkRootResizeCallback
    private let originalData: UnsafeMutableRawPointer?
    private var deliveryState = CodexBarCrossLatestValueDeliveryState<WindowSize>()
    private var deliveryTimer: guint = 0
    private var quietTimer: guint = 0

    init(
        originalCallback: @escaping GtkRootResizeCallback,
        originalData: UnsafeMutableRawPointer?)
    {
        self.originalCallback = originalCallback
        self.originalData = originalData
    }

    func receive(_ size: CustomWidgetSize) {
        let shouldSchedule = self.deliveryState.receive(WindowSize(
            width: size.width,
            height: size.height))
        self.scheduleQuietDelivery()
        guard shouldSchedule else { return }
        if self.deliverLatest() {
            self.scheduleDeliveryWindow()
        }
    }

    @discardableResult
    private func deliverLatest() -> Bool {
        guard let latestSize = self.deliveryState.consumeLatest() else {
            _ = self.deliveryState.finishDeliveryWindow()
            return false
        }
        self.originalCallback(
            self.originalData,
            CustomWidgetSize(width: latestSize.width, height: latestSize.height))
        return true
    }

    private func scheduleDeliveryWindow() {
        self.deliveryTimer = g_timeout_add_full(
            0,
            guint(Self.deliveryIntervalMilliseconds),
            resizeDeliveryWindowExpired,
            Unmanaged.passUnretained(self).toOpaque(),
            nil)
    }

    func deliveryWindowExpired() {
        self.deliveryTimer = 0
        if self.deliveryState.finishDeliveryWindow() {
            if self.deliverLatest() {
                self.scheduleDeliveryWindow()
            }
        }
    }

    private func scheduleQuietDelivery() {
        if self.quietTimer != 0 {
            g_source_remove(self.quietTimer)
        }
        self.quietTimer = g_timeout_add_full(
            0,
            guint(Self.quietPeriodMilliseconds),
            resizeQuietPeriodExpired,
            Unmanaged.passUnretained(self).toOpaque(),
            nil)
    }

    func quietPeriodExpired() {
        self.quietTimer = 0
        if self.deliveryTimer != 0 {
            g_source_remove(self.deliveryTimer)
            self.deliveryTimer = 0
        }
        _ = self.deliverLatest()
        _ = self.deliveryState.finishDeliveryWindow()
    }
}

private let coalescedGtkRootResizeCallback: GtkRootResizeCallback = { data, size in
    guard let data else { return }
    let context = Unmanaged<ResizeContext>.fromOpaque(data).takeUnretainedValue()
    context.receive(size)
}

private let resizeDeliveryWindowExpired: GtkSourceCallback = { data in
    guard let data else { return 0 }
    let context = Unmanaged<ResizeContext>.fromOpaque(data).takeUnretainedValue()
    context.deliveryWindowExpired()
    return 0
}

private let resizeQuietPeriodExpired: GtkSourceCallback = { data in
    guard let data else { return 0 }
    let context = Unmanaged<ResizeContext>.fromOpaque(data).takeUnretainedValue()
    context.quietPeriodExpired()
    return 0
}
#endif
