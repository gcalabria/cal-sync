import Foundation

enum SyncDirection: String {
    case oneWay = "oneWay"
    case twoWay = "twoWay"

    var displayName: String {
        switch self {
        case .oneWay: return "One-way (A → B)"
        case .twoWay: return "Two-way (A ↔ B)"
        }
    }
}

class Settings {
    static let shared = Settings()
    static let didChangeNotification = Notification.Name("SettingsDidChange")

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let sourceCalendarId = "sourceCalendarId"
        static let destinationCalendarId = "destinationCalendarId"
        static let syncDirection = "syncDirection"
        static let syncIntervalMinutes = "syncIntervalMinutes"
        static let showStatusBarIcon = "showStatusBarIcon"
    }

    var sourceCalendarId: String? {
        get { defaults.string(forKey: Keys.sourceCalendarId) }
        set {
            defaults.set(newValue, forKey: Keys.sourceCalendarId)
            notifyChange()
        }
    }

    var destinationCalendarId: String? {
        get { defaults.string(forKey: Keys.destinationCalendarId) }
        set {
            defaults.set(newValue, forKey: Keys.destinationCalendarId)
            notifyChange()
        }
    }

    var syncDirection: SyncDirection {
        get {
            guard let raw = defaults.string(forKey: Keys.syncDirection) else { return .oneWay }
            return SyncDirection(rawValue: raw) ?? .oneWay
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.syncDirection)
            notifyChange()
        }
    }

    var syncIntervalMinutes: Int {
        get {
            let val = defaults.integer(forKey: Keys.syncIntervalMinutes)
            return val == 0 && !defaults.dictionaryRepresentation().keys.contains(Keys.syncIntervalMinutes) ? 30 : val
        }
        set {
            defaults.set(newValue, forKey: Keys.syncIntervalMinutes)
            notifyChange()
        }
    }

    var showStatusBarIcon: Bool {
        get {
            if defaults.object(forKey: Keys.showStatusBarIcon) == nil { return true }
            return defaults.bool(forKey: Keys.showStatusBarIcon)
        }
        set {
            defaults.set(newValue, forKey: Keys.showStatusBarIcon)
            notifyChange()
        }
    }

    private func notifyChange() {
        NotificationCenter.default.post(name: Settings.didChangeNotification, object: nil)
    }
}
