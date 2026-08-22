@_spi(Backends) import SwiftCrossUI

/// Keeps previously visited conditional view branches alive instead of rebuilding their
/// complete native widget trees whenever the selection changes.
///
/// SwiftCrossUI's `EitherView` intentionally discards the inactive branch. That behavior is
/// appropriate for short-lived conditionals, but makes a settings sidebar expensive because
/// each click recreates every label, control, and card in the destination pane. This host is
/// renderer-neutral and lazy: it creates only the current branch, caches it by selection, and
/// updates a cached branch from the latest shared Swift view before displaying it again.
struct PersistentViewSwitcher<Selection: Hashable, Revision: Hashable, Displayed: View>: View {
    typealias Content = EmptyView

    let selection: Selection
    let revision: Revision
    let displayed: Displayed

    var body = EmptyView()

    init(
        selection: Selection,
        revision: Revision,
        @ViewBuilder content: () -> Displayed)
    {
        self.selection = selection
        self.revision = revision
        self.displayed = content()
    }

    func children(
        backend: some BaseAppBackend,
        snapshots: [ViewGraphSnapshotter.NodeSnapshot]?,
        environment: EnvironmentValues) -> any ViewGraphNodeChildren
    {
        PersistentViewSwitcherChildren<Selection, Revision>(
            selection: self.selection,
            revision: self.revision,
            displayed: self.displayed,
            backend: backend,
            snapshot: snapshots?.first,
            environment: environment)
    }

    func layoutableChildren(
        backend _: some BaseAppBackend,
        children _: any ViewGraphNodeChildren) -> [LayoutSystem.LayoutableChild]
    {
        []
    }

    func asWidget<Backend: BaseAppBackend>(
        _ children: any ViewGraphNodeChildren,
        backend: Backend) -> Backend.Widget
    {
        let children = Self.typed(children)
        let container = backend.createContainer()
        backend.insert(children.activeNode.getWidget().into(), into: container, at: 0)
        backend.setPosition(ofChildAt: 0, in: container, to: .zero)
        return container
    }

    func computeLayout<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children untypedChildren: any ViewGraphNodeChildren,
        proposedSize: ProposedViewSize,
        environment: EnvironmentValues,
        backend: Backend) -> ViewLayoutResult
    {
        let children = Self.typed(untypedChildren)
        var entry: PersistentViewSwitcherChildren<Selection, Revision>.Entry
        if let cachedEntry = children.entries[self.selection] {
            entry = cachedEntry
        } else {
            entry = .init(node: ErasedViewGraphNode(
                for: self.displayed,
                backend: backend,
                environment: environment))
            children.selectionOrder.append(self.selection)
        }

        children.pendingSelection = self.selection
        if entry.revision != self.revision {
            entry.revision = self.revision
            entry.layouts.removeAll(keepingCapacity: true)
            entry.layoutOrder.removeAll(keepingCapacity: true)
        }
        if !children.shouldCommitActiveNode,
           let result = entry.layouts[proposedSize]
        {
            entry.touch(proposedSize)
            children.entries[self.selection] = entry
            return result
        }

        var (viewTypeMatched, result) = entry.node.computeLayoutWithNewView(
            self.displayed,
            proposedSize,
            environment)
        if !viewTypeMatched {
            let replacement = ErasedViewGraphNode(
                for: self.displayed,
                backend: backend,
                environment: environment)
            entry.node = replacement
            (viewTypeMatched, result) = replacement.computeLayoutWithNewView(
                self.displayed,
                proposedSize,
                environment)
        }
        precondition(viewTypeMatched, "A newly created persistent view must match its source type")

        entry.store(result, for: proposedSize)
        children.entries[self.selection] = entry
        children.shouldCommitActiveNode = true
        return result
    }

    func commit<Backend: BaseAppBackend>(
        _ widget: Backend.Widget,
        children untypedChildren: any ViewGraphNodeChildren,
        layout: ViewLayoutResult,
        environment _: EnvironmentValues,
        backend: Backend)
    {
        let children = Self.typed(untypedChildren)
        if children.mountedSelection != children.pendingSelection {
            backend.removeAllChildren(of: widget)
            backend.insert(children.activeNode.getWidget().into(), into: widget, at: 0)
            backend.setPosition(ofChildAt: 0, in: widget, to: .zero)
            children.mountedSelection = children.pendingSelection
        }

        if children.shouldCommitActiveNode {
            _ = children.activeNode.commit()
            children.shouldCommitActiveNode = false
        }
        backend.setSize(of: widget, to: layout.size.vector)
    }

    private static func typed(
        _ children: any ViewGraphNodeChildren) -> PersistentViewSwitcherChildren<Selection, Revision>
    {
        guard let children = children as? PersistentViewSwitcherChildren<Selection, Revision> else {
            preconditionFailure("PersistentViewSwitcher received incompatible graph children")
        }
        return children
    }
}

@MainActor
private final class PersistentViewSwitcherChildren<Selection: Hashable, Revision: Hashable>:
    ViewGraphNodeChildren
{
    struct Entry {
        var node: ErasedViewGraphNode
        var layouts: [ProposedViewSize: ViewLayoutResult] = [:]
        var layoutOrder: [ProposedViewSize] = []
        var revision: Revision?

        mutating func touch(_ proposedSize: ProposedViewSize) {
            self.layoutOrder.removeAll { $0 == proposedSize }
            self.layoutOrder.append(proposedSize)
        }

        mutating func store(_ layout: ViewLayoutResult, for proposedSize: ProposedViewSize) {
            self.layouts[proposedSize] = layout
            self.touch(proposedSize)
            while self.layoutOrder.count > 12 {
                let evicted = self.layoutOrder.removeFirst()
                self.layouts.removeValue(forKey: evicted)
            }
        }
    }

    var entries: [Selection: Entry]
    var selectionOrder: [Selection]
    var mountedSelection: Selection
    var pendingSelection: Selection
    var shouldCommitActiveNode = true

    var activeNode: ErasedViewGraphNode {
        guard let node = self.entries[self.pendingSelection]?.node else {
            preconditionFailure("Persistent view selection has no corresponding graph node")
        }
        return node
    }

    var widgets: [AnyWidget] {
        self.selectionOrder.compactMap { self.entries[$0]?.node.getWidget() }
    }

    var erasedNodes: [ErasedViewGraphNode] {
        self.selectionOrder.compactMap { self.entries[$0]?.node }
    }

    init(
        selection: Selection,
        revision: Revision,
        displayed: some View,
        backend: some BaseAppBackend,
        snapshot: ViewGraphSnapshotter.NodeSnapshot?,
        environment: EnvironmentValues)
    {
        let node = ErasedViewGraphNode(
            for: displayed,
            backend: backend,
            snapshot: snapshot,
            environment: environment)
        self.entries = [selection: Entry(
            node: node,
            layouts: [:],
            layoutOrder: [],
            revision: revision)]
        self.selectionOrder = [selection]
        self.mountedSelection = selection
        self.pendingSelection = selection
    }
}
