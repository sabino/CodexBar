public enum CodexBarCrossHistoryLoadingPolicy {
    public static func shouldRunImmediateMaintenance(
        cachedSnapshotLoaded: Bool,
        refreshOnOpen: Bool) -> Bool
    {
        refreshOnOpen && !cachedSnapshotLoaded
    }
}
