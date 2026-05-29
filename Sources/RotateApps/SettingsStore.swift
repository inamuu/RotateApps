import AppKit
import Carbon

struct HotKey: Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32
    var displayName: String
}

final class SettingsStore {
    private enum Key {
        static let hotKeyCode = "hotKeyCode"
        static let hotKeyModifiers = "hotKeyModifiers"
        static let hotKeyDisplayName = "hotKeyDisplayName"
        static let itemSize = "itemSize"
        static let showThumbnails = "showThumbnails"
    }

    var onChange: (() -> Void)?

    var hotKey: HotKey {
        get {
            let defaults = UserDefaults.standard
            let keyCode = defaults.object(forKey: Key.hotKeyCode) as? Int ?? 48
            let modifiers = defaults.object(forKey: Key.hotKeyModifiers) as? Int ?? Int(optionKey)
            let displayName = defaults.string(forKey: Key.hotKeyDisplayName) ?? "Option + Tab"
            return HotKey(keyCode: UInt32(keyCode), carbonModifiers: UInt32(modifiers), displayName: displayName)
        }
        set {
            let defaults = UserDefaults.standard
            defaults.set(Int(newValue.keyCode), forKey: Key.hotKeyCode)
            defaults.set(Int(newValue.carbonModifiers), forKey: Key.hotKeyModifiers)
            defaults.set(newValue.displayName, forKey: Key.hotKeyDisplayName)
            onChange?()
        }
    }

    var itemSize: CGFloat {
        get {
            let value = UserDefaults.standard.double(forKey: Key.itemSize)
            return value > 0 ? CGFloat(value) : 150
        }
        set {
            UserDefaults.standard.set(Double(newValue), forKey: Key.itemSize)
            onChange?()
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
            onChange?()
        }
    }
}
