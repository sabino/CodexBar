#if os(Linux)
import CGdkX11
import CGtk
import Gtk
#elseif os(macOS)
import AppKit
#elseif os(Windows)
import WinUI
#endif

@MainActor
final class PlatformWindowController {
    static let shared = PlatformWindowController()

    #if os(Linux)
    private weak var miniWindow: Gtk.ApplicationWindow?
    private weak var settingsWindow: Gtk.ApplicationWindow?

    func attachMiniWindow(_ window: Gtk.ApplicationWindow) {
        self.miniWindow = window
        Self.enableHideOnClose(window)
        let pointer = UnsafeMutableRawPointer(window.widgetPointer)
            .assumingMemoryBound(to: GtkWindow.self)
        codexbar_configure_compact_x11_window(pointer)
    }

    func attachSettingsWindow(_ window: Gtk.ApplicationWindow) {
        self.settingsWindow = window
        Self.enableHideOnClose(window)
    }

    func showMini() {
        self.miniWindow?.present()
    }

    func hideMini() {
        self.miniWindow?.hide()
    }

    func toggleMini() {
        guard let miniWindow = self.miniWindow else { return }
        if gtk_widget_get_visible(miniWindow.widgetPointer) != 0 {
            miniWindow.hide()
        } else {
            miniWindow.present()
        }
    }

    func hideSettings() {
        self.settingsWindow?.hide()
    }

    private static func enableHideOnClose(_ window: Gtk.ApplicationWindow) {
        let pointer = UnsafeMutableRawPointer(window.widgetPointer)
            .assumingMemoryBound(to: GtkWindow.self)
        gtk_window_set_hide_on_close(pointer, 1)
    }

    #elseif os(macOS)
    private weak var miniWindow: NSWindow?
    private weak var settingsWindow: NSWindow?
    private let hidingDelegate = HidingWindowDelegate()

    func attachMiniWindow(_ window: NSWindow) {
        self.miniWindow = window
        window.isReleasedWhenClosed = false
        window.delegate = self.hidingDelegate
    }

    func attachSettingsWindow(_ window: NSWindow) {
        self.settingsWindow = window
        window.isReleasedWhenClosed = false
        window.delegate = self.hidingDelegate
    }

    func showMini() {
        self.miniWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func hideMini() {
        self.miniWindow?.orderOut(nil)
    }

    func toggleMini() {
        if self.miniWindow?.isVisible == true {
            self.hideMini()
        } else {
            self.showMini()
        }
    }

    func hideSettings() {
        self.settingsWindow?.orderOut(nil)
    }

    #elseif os(Windows)
    private var miniWindow: WinUI.Window?
    private var settingsWindow: WinUI.Window?

    func attachMiniWindow(_ window: WinUI.Window) {
        self.miniWindow = window
    }

    func attachSettingsWindow(_ window: WinUI.Window) {
        self.settingsWindow = window
    }

    func showMini() {
        try? self.miniWindow?.appWindow.show(true)
    }

    func hideMini() {
        try? self.miniWindow?.appWindow.hide()
    }

    func toggleMini() {
        if self.miniWindow?.appWindow.isVisible == true {
            self.hideMini()
        } else {
            self.showMini()
        }
    }

    func hideSettings() {
        try? self.settingsWindow?.appWindow.hide()
    }
    #endif
}

#if os(macOS)
@MainActor
private final class HidingWindowDelegate: NSObject, NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
#endif
