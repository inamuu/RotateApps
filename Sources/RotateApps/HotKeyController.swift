import AppKit
import Carbon

final class HotKeyController {
    enum Direction {
        case forward
        case backward
    }

    var onPressed: ((Direction) -> Void)?
    var onReleased: (() -> Void)?

    private let settings: SettingsStore
    /// `GetEventDispatcherTarget` receives hotkeys without Accessibility permission,
    /// unlike `GetApplicationEventTarget`.
    private let eventTarget = GetEventDispatcherTarget()
    private var hotKeyRef: EventHotKeyRef?
    private var reverseHotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var flagsMonitor: Any?
    private var releaseSafetyTimer: Timer?
    private var isTrackingRelease = false
    private var didDisableNativeSwitcher = false

    init(settings: SettingsStore) {
        self.settings = settings
        settings.onHotKeyChange = { [weak self] in self?.restart() }
    }

    func start() {
        installEventHandlerIfNeeded()
        registerHotKey()
    }

    func restart() {
        unregisterHotKey()
        registerHotKey()
    }

    /// Must be called before the process exits: the native switcher state persists.
    func restoreNativeAppSwitcher() {
        guard didDisableNativeSwitcher else { return }
        NativeAppSwitcher.setEnabled(true)
        didDisableNativeSwitcher = false
    }

    deinit {
        unregisterHotKey()
        restoreNativeAppSwitcher()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        stopReleaseTracking()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(eventTarget, { _, event, userData in
            guard let userData else { return noErr }
            let controller = Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue()
            controller.handleHotKeyPressed(event: event)
            return noErr
        }, 1, &eventType, selfPointer, &eventHandler)
    }

    private func registerHotKey() {
        let hotKey = settings.hotKey
        updateNativeAppSwitcher(for: hotKey)

        let hotKeyID = EventHotKeyID(signature: OSType(0x52544150), id: 1)
        RegisterEventHotKey(hotKey.keyCode, hotKey.carbonModifiers, hotKeyID, eventTarget, 0, &hotKeyRef)

        if hotKey.carbonModifiers & UInt32(shiftKey) == 0 {
            let reverseHotKeyID = EventHotKeyID(signature: OSType(0x52544150), id: 2)
            RegisterEventHotKey(hotKey.keyCode, hotKey.carbonModifiers | UInt32(shiftKey), reverseHotKeyID, eventTarget, 0, &reverseHotKeyRef)
        }
    }

    /// macOS routes `Command + Tab` to its own switcher before any application hotkey, so the
    /// system shortcut has to be switched off while RotateApps owns that combination.
    private func updateNativeAppSwitcher(for hotKey: HotKey) {
        let shouldDisable = hotKey.conflictsWithNativeAppSwitcher
        guard shouldDisable != didDisableNativeSwitcher else { return }
        NativeAppSwitcher.setEnabled(!shouldDisable)
        didDisableNativeSwitcher = shouldDisable
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let reverseHotKeyRef {
            UnregisterEventHotKey(reverseHotKeyRef)
            self.reverseHotKeyRef = nil
        }
    }

    private func handleHotKeyPressed(event: EventRef?) {
        var hotKeyID = EventHotKeyID()
        if let event {
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
        }
        beginReleaseTracking()
        onPressed?(hotKeyID.id == 2 ? .backward : .forward)
    }

    private func beginReleaseTracking() {
        guard !isTrackingRelease else { return }
        isTrackingRelease = true
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleModifiers(event.modifierFlags)
        }
        // A global monitor can miss the release (secure input fields, Space switches, permission
        // hiccups). Polling the live modifier state guarantees the panel never stays up.
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.handleModifiers(NSEvent.modifierFlags)
        }
        RunLoop.main.add(timer, forMode: .common)
        releaseSafetyTimer = timer
    }

    private func handleModifiers(_ modifiers: NSEvent.ModifierFlags) {
        guard isTrackingRelease else { return }
        let requiredFlags = NSEvent.ModifierFlags(carbonModifiers: settings.hotKey.carbonModifiers)
        guard !modifiers.contains(requiredFlags) else { return }
        stopReleaseTracking()
        onReleased?()
    }

    private func stopReleaseTracking() {
        isTrackingRelease = false
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
        releaseSafetyTimer?.invalidate()
        releaseSafetyTimer = nil
    }
}

extension HotKey {
    /// True for the combinations macOS binds to its own application switcher.
    var conflictsWithNativeAppSwitcher: Bool {
        let modifiersIgnoringShift = carbonModifiers & ~UInt32(shiftKey)
        return keyCode == HotKey.commandTab.keyCode && modifiersIgnoringShift == UInt32(cmdKey)
    }
}

extension NSEvent.ModifierFlags {
    init(carbonModifiers: UInt32) {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        self = flags
    }
}
