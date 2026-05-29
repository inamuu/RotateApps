import AppKit
import Carbon

struct HotKey: Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var displayName: String

    static let optionTab = HotKey(keyCode: 48, carbonModifiers: UInt32(optionKey), displayName: "Option + Tab")
    static let commandTab = HotKey(keyCode: 48, carbonModifiers: UInt32(cmdKey), displayName: "Command + Tab")
}

enum SwitcherTheme: String, CaseIterable {
    case system
    case blue
    case graphite
    case green
    case rose

    var displayName: String {
        switch self {
        case .system: return "System"
        case .blue: return "Blue"
        case .graphite: return "Graphite"
        case .green: return "Green"
        case .rose: return "Rose"
        }
    }

    var accentColor: NSColor {
        switch self {
        case .system: return .controlAccentColor
        case .blue: return NSColor(calibratedRed: 0.27, green: 0.55, blue: 0.92, alpha: 1)
        case .graphite: return NSColor(calibratedRed: 0.62, green: 0.66, blue: 0.72, alpha: 1)
        case .green: return NSColor(calibratedRed: 0.22, green: 0.68, blue: 0.46, alpha: 1)
        case .rose: return NSColor(calibratedRed: 0.88, green: 0.38, blue: 0.55, alpha: 1)
        }
    }

    var cardColor: NSColor {
        switch self {
        case .system: return NSColor.windowBackgroundColor.withAlphaComponent(0.24)
        case .blue: return NSColor(calibratedRed: 0.07, green: 0.12, blue: 0.20, alpha: 0.42)
        case .graphite: return NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.16, alpha: 0.42)
        case .green: return NSColor(calibratedRed: 0.06, green: 0.16, blue: 0.12, alpha: 0.42)
        case .rose: return NSColor(calibratedRed: 0.18, green: 0.08, blue: 0.12, alpha: 0.42)
        }
    }

    var thumbnailColor: NSColor {
        switch self {
        case .system: return NSColor.black.withAlphaComponent(0.18)
        default: return accentColor.withAlphaComponent(0.16)
        }
    }
}

final class SettingsStore {
    private enum Key {
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let hotKeyDisplayName = "hotKeyDisplayName"
        static let itemSize = "itemSize"
        static let showThumbnails = "showThumbnails"
        static let theme = "theme"
    }

    var onHotKeyChange: (() -> Void)?

    var hotKey: HotKey {
        get {
            let defaults = UserDefaults.standard
            let keyCode = defaults.object(forKey: Key.hotKeyCode) as? Int ?? Int(HotKey.optionTab.keyCode)
            let modifiers = defaults.object(forKey: Key.hotKeyModifiers) as? Int ?? Int(HotKey.optionTab.carbonModifiers)
            let displayName = defaults.string(forKey: Key.hotKeyDisplayName) ?? HotKey.optionTab.displayName
            return HotKey(keyCode: UInt32(keyCode), carbonModifiers: UInt32(modifiers), displayName: displayName)
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(Int(newValue.keyCode), forKey: Key.hotKeyCode)
            defaults.set(Int(newValue.carbonModifiers), forKey: Key.hotKeyModifiers)
            defaults.set(newValue.displayName, forKey: Key.hotKeyDisplayName)
            onHotKeyChange?()
        }
    }

    var itemSize: CGFloat {
        get {
            let value = UserDefaults.standard.double(forKey: Key.itemSize)
            return value > 0 ? CGFloat(value) : 150
        }
        set {
            UserDefaults.standard.set(Double(newValue), forKey: Key.itemSize)
        }
    }

    var showThumbnails: Bool {
        get {
            if UserDefaults.standard.object(forKey: Key.showThumbnails) == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: Key.showThumbnails)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: Key.showThumbnails)
        }
    }

    var theme: SwitcherTheme {
        get {
            let rawValue = UserDefaults.standard.string(forKey: Key.theme) ?? SwitcherTheme.system.rawValue
            return SwitcherTheme(rawValue: rawValue) ?? .system
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Key.theme)
        }
    }
}
