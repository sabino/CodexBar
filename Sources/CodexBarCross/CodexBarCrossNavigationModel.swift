#if CrossPlatformApp

import CodexBarCore
import CodexBarCrossSupport
import SwiftCrossUI

@MainActor
final class CodexBarCrossNavigationModel: SwiftCrossUI.ObservableObject {
    @SwiftCrossUI.Published private(set) var state = CodexBarCrossNavigationState()
    @SwiftCrossUI.Published private(set) var selectedSection: CodexBarCrossSection? = .general
    @SwiftCrossUI.Published private(set) var selectedProviderID: UsageProvider?
    @SwiftCrossUI.Published private(set) var searchQuery = ""

    var routeObservation: SwiftCrossUI.Published<CodexBarCrossNavigationState> {
        self._state
    }

    var sectionObservation: SwiftCrossUI.Published<CodexBarCrossSection?> {
        self._selectedSection
    }

    var providerObservation: SwiftCrossUI.Published<UsageProvider?> {
        self._selectedProviderID
    }

    var searchObservation: SwiftCrossUI.Published<String> {
        self._searchQuery
    }

    @discardableResult
    func select(_ section: CodexBarCrossSection) -> Bool {
        var state = self.state
        guard state.select(section) else { return false }
        self.publish(state)
        return true
    }

    @discardableResult
    func select(_ provider: UsageProvider) -> Bool {
        var state = self.state
        guard state.select(provider) else { return false }
        self.publish(state)
        return true
    }

    func setSearchQuery(_ query: String) {
        guard self.searchQuery != query else { return }
        self.searchQuery = query
    }

    private func publish(_ state: CodexBarCrossNavigationState) {
        let previous = self.state
        self.state = state
        if previous.section != state.section {
            self.selectedSection = state.section
        }
        if previous.provider != state.provider {
            self.selectedProviderID = state.provider
        }
    }
}

#endif
