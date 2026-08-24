import Dispatch

/// A type that produces valueless observations.
public class Publisher {
    /// The id for the next observation (ids are used to cancel observations).
    private var nextObservationId = 0
    /// All current observations keyed by their id (ids are used to cancel observations).
    private var observations: [Int: () -> Void] = [:]
    /// Human-readable tag for debugging purposes.
    private var tag: String?
    /// Preserves observation order without dropping or delaying events.
    private let serialUpdateHandlingQueue = DispatchQueue(
        label: "SwiftCrossUI UI update delivery")

    /// Creates a new independent publisher.
    public init() {}

    /// Publishes a change to all observers serially on the current thread.
    public func send() {
        for observation in self.observations.values {
            observation()
        }
    }

    /// Registers a handler to observe future events.
    public func observe(with closure: @escaping () -> Void) -> Cancellable {
        let id = self.nextObservationId
        self.observations[id] = closure
        self.nextObservationId += 1

        return Cancellable { [weak self] in
            guard let self else { return }
            self.observations[id] = nil
        }
        .tag(with: self.tag)
    }

    /// Links the publisher to an upstream, meaning that observations from the upstream
    /// effectively get forwarded to all observers of this publisher as well.
    public func link(toUpstream publisher: Publisher) -> Cancellable {
        let cancellable = publisher.observe(with: {
            self.send()
        })
        cancellable.tag(with: "\(self.tag ?? "no tag") <-> \(cancellable.tag ?? "no tag")")
        return cancellable
    }

    @discardableResult
    func tag(with tag: @autoclosure () -> String?) -> Self {
        #if DEBUG
        self.tag = tag()
        #endif
        return self
    }

    /// Delivers every observation to the renderer's main thread in FIFO order.
    ///
    /// CodexBar intentionally does not merge, drop, debounce, or delay UI state
    /// changes. The delivery queue waits only for the native UI-thread action to
    /// finish, preventing re-entrant view-graph mutation without adding a pause.
    func observeAsUIUpdater(
        backend: some BaseAppBackend,
        action: @escaping @MainActor @Sendable () -> Void) -> Cancellable
    {
        let serialUpdateHandlingQueue = self.serialUpdateHandlingQueue
        return self.observe {
            serialUpdateHandlingQueue.async {
                let completed = DispatchSemaphore(value: 0)
                backend.runInMainThread {
                    action()
                    completed.signal()
                }
                completed.wait()
            }
        }
    }
}
