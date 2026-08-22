import CodexBarCore
import CodexBarCrossSupport
import Testing

struct CodexBarCrossNavigationStateTests {
    @Test
    func `cached history opens without immediate maintenance`() {
        #expect(!CodexBarCrossHistoryLoadingPolicy.shouldRunImmediateMaintenance(
            cachedSnapshotLoaded: true,
            refreshOnOpen: true))
    }

    @Test
    func `first history load can start immediate maintenance`() {
        #expect(CodexBarCrossHistoryLoadingPolicy.shouldRunImmediateMaintenance(
            cachedSnapshotLoaded: false,
            refreshOnOpen: true))
        #expect(!CodexBarCrossHistoryLoadingPolicy.shouldRunImmediateMaintenance(
            cachedSnapshotLoaded: false,
            refreshOnOpen: false))
    }

    @Test
    func `selecting the active section is a no-op`() {
        var state = CodexBarCrossNavigationState()

        let changed = state.select(.general)

        #expect(!changed)
        #expect(state.section == .general)
        #expect(state.provider == nil)
    }

    @Test
    func `one route owns section and provider selection`() {
        var state = CodexBarCrossNavigationState()

        let selectedProvider = state.select(UsageProvider.codex)
        #expect(selectedProvider)
        #expect(state.section == nil)
        #expect(state.provider == .codex)
        let reselectedProvider = state.select(UsageProvider.codex)
        #expect(!reselectedProvider)

        let selectedSection = state.select(CodexBarCrossSection.notifications)
        #expect(selectedSection)
        #expect(state.section == .notifications)
        #expect(state.provider == nil)
    }
}
