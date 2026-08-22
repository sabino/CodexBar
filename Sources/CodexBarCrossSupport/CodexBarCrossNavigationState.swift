import CodexBarCore

public enum CodexBarCrossSection: String, CaseIterable {
    case general = "General"
    case spend = "Usage & Spend"
    case notifications = "Notifications"
    case menuBar = "Menu Bar"
    case menu = "Menu"
    case advanced = "Advanced"
    case about = "About"
}

public struct CodexBarCrossNavigationState: Equatable {
    public enum Route: Equatable {
        case section(CodexBarCrossSection)
        case provider(UsageProvider)
    }

    public private(set) var route: Route

    public init(section: CodexBarCrossSection = .general) {
        self.route = .section(section)
    }

    public var section: CodexBarCrossSection? {
        guard case let .section(section) = self.route else { return nil }
        return section
    }

    public var provider: UsageProvider? {
        guard case let .provider(provider) = self.route else { return nil }
        return provider
    }

    @discardableResult
    public mutating func select(_ section: CodexBarCrossSection) -> Bool {
        self.setRoute(.section(section))
    }

    @discardableResult
    public mutating func select(_ provider: UsageProvider) -> Bool {
        self.setRoute(.provider(provider))
    }

    private mutating func setRoute(_ route: Route) -> Bool {
        guard self.route != route else { return false }
        self.route = route
        return true
    }
}
