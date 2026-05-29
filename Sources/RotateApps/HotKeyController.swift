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
    private var hotKeyRef: EventHotKeyRef?
    private var reverseHotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var flagsMonitor: Any?
    private var isTrackingRelease = false

    init(settings: SettingsStore) {
        self.settings = settings
        settings.onChange = { [weak self] in self?.restart() }
    }

    func start() {
        installEventHandlerIfNeeded()
        registerHotKey()
    }

    func restart() {
        unregisterHotKey()
        registerHotKey()
    }

    deinit {
        unregisterHotKey()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData else { return noErr }
            let controller = Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue()
            controller.handleHotKeyPressed(event: event)
            return noErr
        }, 1, &eventType, selfPointer, &eventHandler)
    }

    private func registerHotKey() {
        let hotKey = settings.hotKey
        var hotKeyID = EventHotKeyID(signature: OSType(0x52544150), id: 1)
        RegisterEventHotKey(hotKey.keyCode, hotKey.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        if hotKey.carbonModifiers & UInt32(shiftKey) == 0 {
            var reverseHotKeyID = EventHotKeyID(signature: OSType(0x52544150), id: 2)
            RegisterEventHotKey(hotKey.keyCode, hotKey.carbonModifiers | UInt32(shiftKey), reverseHotKeyID, GetApplicationEventTarget(), 0, &reverseHotKeyRef)
        }
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
        onPressed?(hotKeyID.id == 2 ? .backward : .forward)
        beginReleaseTracking()
    }

    private func beginReleaseTracking() {
        guard !isTrackingRelease else { return }
        isTrackingRelease = true
        flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let hotKey = settings.hotKey
        let requiredFlags = NSEvent.ModifierFlags(carbonModifiers: hotKey.carbonModifiers)
        if !event.modifierFlags.contains(requiredFlags) {
            stopReleaseTracking()
            onReleased?()
        }
    }

    private func stopReleaseTracking() {
        isTrackingRelease = false
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
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
