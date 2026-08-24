import Foundation

struct CodexBarCrossPreferences: Codable, Equatable {
    var appLanguage = "System"
    var preferredCurrency = "Automatic"
    var launchAtLogin = true

    var refreshInterval = "5 minutes"
    var refreshOnOpen = true
    var statusChecksEnabled = true

    var depletedNotifications = true
    var thresholdNotifications = false
    var predictiveNotifications = false
    var warningThreshold = 20
    var quietHoursEnabled = false
    var resetCelebration = "Subtle"

    var menuBarIconStyle = "Provider icon"
    var highContrastIcon = false
    var mergeProviderIcons = true
    var showPercentageInTray = true
    var switcherRows = "5 providers"

    var showProviderHeader = true
    var showUsageBars = true
    var showResetTimes = true
    var showAccount = true
    var showPlan = true
    var showCost = true
    var hideSensitiveValues = false

    var historyEnabled = true
    var historyWindow = "1 year"
    var surfaceStyle = "Automatic"
    var rendererMode = "Automatic"
    var diagnosticsEnabled = false
    var verboseProviderErrors = false

    var historyDays: Int {
        switch self.historyWindow {
        case "7 days": 7
        case "30 days": 30
        case "90 days": 90
        case "6 months": 180
        default: 365
        }
    }

    var usesSolidSurfaces: Bool {
        switch self.surfaceStyle {
        case "Solid": true
        case "Layered": false
        default:
            #if os(macOS)
            false
            #else
            true
            #endif
        }
    }
}

@MainActor
struct CodexBarCrossPreferencesStore {
    private static let storageKey = "CodexBarCross.preferences.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> CodexBarCrossPreferences {
        guard let data = self.defaults.data(forKey: Self.storageKey) else {
            return CodexBarCrossPreferences()
        }
        if let preferences = try? JSONDecoder().decode(CodexBarCrossPreferences.self, from: data) {
            return preferences
        }
        guard var payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return CodexBarCrossPreferences()
        }
        payload["surfaceStyle"] = payload["surfaceStyle"] ?? "Automatic"
        payload["rendererMode"] = payload["rendererMode"] ?? "Automatic"
        guard let migrated = try? JSONSerialization.data(withJSONObject: payload),
              let preferences = try? JSONDecoder().decode(CodexBarCrossPreferences.self, from: migrated)
        else {
            return CodexBarCrossPreferences()
        }
        return preferences
    }

    func save(_ preferences: CodexBarCrossPreferences) {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        self.defaults.set(data, forKey: Self.storageKey)
    }
}
