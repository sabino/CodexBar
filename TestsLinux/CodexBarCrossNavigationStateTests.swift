import CodexBarCore
import CodexBarCrossSupport
import Testing

struct CodexBarCrossNavigationStateTests {
    @Test
    func `resize delivery keeps only the latest value in a burst`() {
        var state = CodexBarCrossLatestValueDeliveryState<Int>()

        let schedulesFirstDelivery = state.receive(900)
        let schedulesSecondDelivery = state.receive(980)
        let schedulesThirdDelivery = state.receive(1120)
        #expect(schedulesFirstDelivery)
        #expect(!schedulesSecondDelivery)
        #expect(!schedulesThirdDelivery)
        #expect(state.consumeLatest() == 1120)
        let redeliversAfterBurst = state.finishDeliveryWindow()
        #expect(!redeliversAfterBurst)
        #expect(state.consumeLatest() == nil)
    }

    @Test
    func `resize delivery retains changes that arrive during cooldown`() {
        var state = CodexBarCrossLatestValueDeliveryState<Int>()

        let schedulesFirstDelivery = state.receive(900)
        #expect(schedulesFirstDelivery)
        #expect(state.consumeLatest() == 900)
        let schedulesDuringCooldown = state.receive(980)
        #expect(!schedulesDuringCooldown)
        let redeliversAfterChange = state.finishDeliveryWindow()
        #expect(redeliversAfterChange)
        #expect(state.consumeLatest() == 980)
        let redeliversAfterCatchUp = state.finishDeliveryWindow()
        #expect(!redeliversAfterCatchUp)

        let schedulesDuplicateDelivery = state.receive(980)
        #expect(schedulesDuplicateDelivery)
        #expect(state.consumeLatest() == nil)
        let redeliversDuplicate = state.finishDeliveryWindow()
        #expect(!redeliversDuplicate)
    }

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
