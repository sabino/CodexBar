import SwiftCrossUI

#if os(Linux)
import Glibc
import GtkBackend
#elseif os(macOS)
import AppKitBackend
#elseif os(Windows)
import WinUIBackend
#else
#error("CodexBarCross supports Linux, macOS, and Windows")
#endif

@main
struct CodexBarCrossApp: App {
    init() {
        #if os(Linux)
        // This UI is almost entirely text and simple vector shapes. GTK's Cairo
        // renderer avoids loading and warming a full GPU shader stack, which is
        // a large resident-memory cost for an always-on tray utility.
        if getenv("GSK_RENDERER") == nil {
            setenv("GSK_RENDERER", "cairo", 0)
        }
        #endif
    }

    var body: some Scene {
        WindowGroup("CodexBar") {
            CodexBarRootView()
        }
        .defaultSize(width: 980, height: 680)
        .windowResizability(.contentMinSize)
    }
}
