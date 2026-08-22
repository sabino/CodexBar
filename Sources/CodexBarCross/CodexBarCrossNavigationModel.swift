import CodexBarCore
import CodexBarCrossSupport
import SwiftCrossUI

@MainActor
final class CodexBarCrossNavigationModel: SwiftCrossUI.ObservableObject {
    @SwiftCrossUI.Published private(set) var state = CodexBarCrossNavigationState()
    @SwiftCrossUI.Published private(set) var searchQuery = ""

    @discardableResult
    func select(_ section: CodexBarCrossSection) -> Bool {
        var state = self.state
        guard state.select(section) else { return false }
        self.state = state
        return true
    }

    @discardableResult
    func select(_ provider: UsageProvider) -> Bool {
        var state = self.state
        guard state.select(provider) else { return false }
        self.state = state
        return true
    }

    func setSearchQuery(_ query: String) {
        guard self.searchQuery != query else { return }
        self.searchQuery = query
    }
}
