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
    private let model: CodexBarCrossModel

    init() {
        #if os(Linux)
        let preferences = CodexBarCrossPreferencesStore().load()
        if preferences.rendererMode == "Low-memory software", getenv("GSK_RENDERER") == nil {
            setenv("GSK_RENDERER", "cairo", 0)
        }
        #endif
        self.model = CodexBarCrossModel()
    }

    var body: some Scene {
        Window("CodexBar", id: "mini") {
            CodexBarMiniView(model: self.model)
        }
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: 420, height: 720)
        .windowResizability(.contentMinSize)

        Window("CodexBar Settings", id: "settings") {
            CodexBarRootView(model: self.model)
        }
        .defaultLaunchBehavior(.suppressed)
        .defaultSize(width: 980, height: 680)
        .windowResizability(.contentMinSize)
    }
}
