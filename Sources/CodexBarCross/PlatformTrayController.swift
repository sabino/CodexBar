#if CrossPlatformApp

import CodexBarCore
import CPlatformTray
import Foundation

#if os(macOS)
import AppKit
#endif

@MainActor
final class PlatformTrayController {
    static let shared = PlatformTrayController()

    private enum Action: Int32 {
        case activate = 0
        case refresh = 1
        case settings = 2
        case about = 3
        case quit = 4
        case show = 5
    }

    private var installed = false
    private weak var model: CodexBarCrossModel?
    private var selectedProviderID: UsageProvider?
    #if os(macOS)
    private var statusItem: NSStatusItem?
    private let actionTarget = TrayActionTarget()
    #endif

    func configure(model: CodexBarCrossModel) {
        self.model = model
    }

    func installOrUpdate(
        state: CrossTrayIconState,
        tooltip: String,
        provider: UsageProvider? = nil)
    {
        if let provider {
            self.selectedProviderID = provider
        }
        guard let iconURL = TrayIconStore.url(for: state) else { return }
        #if os(macOS)
        if self.statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.target = self.actionTarget
            item.button?.action = #selector(TrayActionTarget.activate(_:))
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
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
                codexbarTrayAction,
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

    fileprivate func perform(rawAction: Int32) {
        guard let action = Action(rawValue: rawAction) else { return }
        switch action {
        case .activate:
            PlatformWindowController.shared.toggleMini()
        case .show:
            PlatformWindowController.shared.showMini()
        case .refresh:
            guard let model = self.model,
                  let provider = self.selectedProviderID
                  ?? model.providers.first(where: \.enabled)?.id
            else { return }
            Task { await model.refresh(provider) }
        case .settings:
            self.model?.select(.general)
            PlatformWindowController.shared.hideMini()
            PlatformWindowController.shared.showSettings()
        case .about:
            self.model?.select(.about)
            PlatformWindowController.shared.hideMini()
            PlatformWindowController.shared.showSettings()
        case .quit:
            PlatformWindowController.shared.terminateApplication()
        }
    }

    #if os(macOS)
    fileprivate func showContextMenu() {
        guard let button = self.statusItem?.button else { return }
        let menu = NSMenu(title: "CodexBar")
        let header = NSMenuItem(title: "CodexBar", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(self.menuItem("Show CodexBar", action: #selector(TrayActionTarget.showMini)))
        menu.addItem(self.menuItem("Refresh", action: #selector(TrayActionTarget.refresh)))
        menu.addItem(self.menuItem("Settings…", action: #selector(TrayActionTarget.settings)))
        menu.addItem(self.menuItem("About CodexBar", action: #selector(TrayActionTarget.about)))
        menu.addItem(.separator())
        menu.addItem(self.menuItem("Quit", action: #selector(TrayActionTarget.quit)))
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: 0, y: button.bounds.height + 4),
            in: button)
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self.actionTarget
        return item
    }
    #endif
}

#if os(macOS)
@MainActor
private final class TrayActionTarget: NSObject {
    @objc func activate(_: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            PlatformTrayController.shared.showContextMenu()
        } else {
            PlatformTrayController.shared.perform(rawAction: 0)
        }
    }

    @objc func showMini() {
        PlatformTrayController.shared.perform(rawAction: 5)
    }

    @objc func refresh() {
        PlatformTrayController.shared.perform(rawAction: 1)
    }

    @objc func settings() {
        PlatformTrayController.shared.perform(rawAction: 2)
    }

    @objc func about() {
        PlatformTrayController.shared.perform(rawAction: 3)
    }

    @objc func quit() {
        PlatformTrayController.shared.perform(rawAction: 4)
    }
}
#else
private let codexbarTrayAction: @convention(c) (Int32, UnsafeMutableRawPointer?) -> Void = { action, _ in
    #if os(Linux)
    // The StatusNotifierItem is registered on GTK's thread-default main context,
    // so its GDBus callback is already executing on the native UI thread.
    MainActor.assumeIsolated {
        PlatformTrayController.shared.perform(rawAction: action)
    }
    #else
    Task { @MainActor in
        PlatformTrayController.shared.perform(rawAction: action)
    }
    #endif
}
#endif

#endif
