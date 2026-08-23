/// Tracks the newest value in a burst while allowing at most one scheduled delivery.
///
/// Platform renderers use this to keep live resize feedback current without processing
/// every intermediate allocation emitted by a window manager.
public struct CodexBarCrossLatestValueDeliveryState<Value: Equatable> {
    private var latestValue: Value?
    private var lastDeliveredValue: Value?
    private var hasOpenDeliveryWindow = false

    public init() {}

    /// Returns `true` when the caller should schedule a delivery callback.
    public mutating func receive(_ value: Value) -> Bool {
        self.latestValue = value
        guard !self.hasOpenDeliveryWindow else { return false }
        self.hasOpenDeliveryWindow = true
        return true
    }

    /// Consumes the newest distinct value while keeping the delivery window open.
    public mutating func consumeLatest() -> Value? {
        guard self.hasOpenDeliveryWindow else { return nil }
        guard let latestValue, latestValue != self.lastDeliveredValue else { return nil }
        self.lastDeliveredValue = latestValue
        return latestValue
    }

    /// Closes an idle delivery window or keeps it open when a newer value arrived.
    ///
    /// Returns `true` when the caller should immediately consume and deliver again.
    public mutating func finishDeliveryWindow() -> Bool {
        guard self.hasOpenDeliveryWindow else { return false }
        if self.latestValue != self.lastDeliveredValue {
            return true
        }
        self.hasOpenDeliveryWindow = false
        return false
    }
}
