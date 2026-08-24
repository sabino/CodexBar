#if CrossPlatformApp

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
    private var settingsOpener: (@MainActor () -> Void)?

    func registerSettingsOpener(_ opener: @escaping @MainActor () -> Void) {
        self.settingsOpener = opener
    }

    #if os(Linux)
    private var miniWindow: Gtk.ApplicationWindow?
    private var settingsWindow: Gtk.ApplicationWindow?

    func attachMiniWindow(_ window: Gtk.ApplicationWindow) {
        self.miniWindow = window
        Self.enableHideOnClose(window)
        let pointer = UnsafeMutableRawPointer(window.widgetPointer)
            .assumingMemoryBound(to: GtkWindow.self)
        codexbar_configure_compact_x11_window(pointer)
    }

    func attachSettingsWindow(_ window: Gtk.ApplicationWindow) {
        self.settingsWindow = window
        window.onDestroy = { [weak self, weak window] _ in
            Task { @MainActor in
                guard let self, self.settingsWindow === window else { return }
                self.settingsWindow = nil
                PlatformMemory.releaseUnusedHeapPages()
            }
        }
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
        guard let settingsWindow = self.settingsWindow else { return }
        self.settingsWindow = nil
        settingsWindow.close()
        PlatformMemory.releaseUnusedHeapPages()
    }

    func showSettings() {
        if let settingsWindow {
            settingsWindow.present()
        } else {
            self.settingsOpener?()
        }
    }

    func terminateApplication() {
        guard let window = self.miniWindow ?? self.settingsWindow else { return }
        let pointer = UnsafeMutableRawPointer(window.widgetPointer)
            .assumingMemoryBound(to: GtkWindow.self)
        guard let application = gtk_window_get_application(pointer) else { return }
        g_application_quit(UnsafeMutableRawPointer(application).assumingMemoryBound(to: GApplication.self))
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

    func showSettings() {
        guard let settingsWindow else {
            self.settingsOpener?()
            return
        }
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func terminateApplication() {
        NSApp.terminate(nil)
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

    func showSettings() {
        guard let settingsWindow else {
            self.settingsOpener?()
            return
        }
        try? settingsWindow.appWindow.show(true)
    }

    func terminateApplication() {
        try? self.miniWindow?.close()
        try? self.settingsWindow?.close()
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

#endif
