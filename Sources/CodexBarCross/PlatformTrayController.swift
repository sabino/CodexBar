#if CrossPlatformApp

import CPlatformTray
import Foundation

#if os(macOS)
import AppKit
#endif

@MainActor
final class PlatformTrayController {
    static let shared = PlatformTrayController()

    private var installed = false
    #if os(macOS)
    private var statusItem: NSStatusItem?
    private let actionTarget = TrayActionTarget()
    #endif

    func installOrUpdate(state: CrossTrayIconState, tooltip: String) {
        guard let iconURL = TrayIconStore.url(for: state) else { return }
        #if os(macOS)
        if self.statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.target = self.actionTarget
            item.button?.action = #selector(TrayActionTarget.activate)
            item.button?.toolTip = tooltip
            self.statusItem = item
        }
        if let image = NSImage(contentsOf: iconURL) {
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = false
            self.statusItem?.button?.image = image
        }
        self.statusItem?.button?.toolTip = tooltip
        self.installed = true
        #else
        if self.installed {
            codexbar_tray_update(iconURL.path, tooltip)
        } else {
            self.installed = codexbar_tray_install(
                iconURL.path,
                tooltip,
                codexbarTrayActivated,
                nil)
        }
        #endif
    }

    func remove() {
        #if os(macOS)
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        self.statusItem = nil
        #else
        codexbar_tray_remove()
        #endif
        self.installed = false
    }
}

#if os(macOS)
@MainActor
private final class TrayActionTarget: NSObject {
    @objc func activate() {
        PlatformWindowController.shared.toggleMini()
    }
}
#else
private let codexbarTrayActivated: @convention(c) (UnsafeMutableRawPointer?) -> Void = { _ in
    Task { @MainActor in
        PlatformWindowController.shared.toggleMini()
    }
}
#endif

#endif
