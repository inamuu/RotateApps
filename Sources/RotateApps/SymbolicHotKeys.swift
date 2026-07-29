import CoreGraphics
import Foundation

/// Identifiers of the native macOS symbolic hotkeys that collide with `Command + Tab`.
/// Discoverable by probing `CGSGetSymbolicHotKeyValue` over the first few hundred numbers.
private enum SymbolicHotKey: Int, CaseIterable {
    case commandTab = 1
    case commandShiftTab = 2
}

/// Enables/disables a system shortcut such as Command + Tab or Spotlight.
/// Private CoreGraphics API: the effect persists after the app is quit, so it must be restored.
@_silgen_name("CGSSetSymbolicHotKeyEnabled") @discardableResult
private func CGSSetSymbolicHotKeyEnabled(_ hotKey: Int, _ isEnabled: Bool) -> CGError

/// Owns the on/off state of the macOS built-in application switcher.
///
/// Turning it off is what lets RotateApps bind `Command + Tab` as an ordinary global hotkey
/// instead of racing the system through a `CGEventTap`.
enum NativeAppSwitcher {
    private static let disabledFlagKey = "nativeAppSwitcherDisabled"

    static func setEnabled(_ isEnabled: Bool) {
        for hotKey in SymbolicHotKey.allCases {
            CGSSetSymbolicHotKeyEnabled(hotKey.rawValue, isEnabled)
        }
        UserDefaults.standard.set(!isEnabled, forKey: disabledFlagKey)
    }

    /// The symbolic hotkey state survives the process, so a crash can leave the user without
    /// any application switcher. Restore it on the next launch before we re-apply our own state.
    static func restoreIfLeftDisabled() {
        guard UserDefaults.standard.bool(forKey: disabledFlagKey) else { return }
        setEnabled(true)
    }
}
