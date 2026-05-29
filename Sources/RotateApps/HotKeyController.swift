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
    private var eventTap: CFMachPort?
    private var eventTapRunLoopSource: CFRunLoopSource?
    private var flagsMonitor: Any?
    private var isTrackingRelease = false

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
        uninstallEventTap()
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
        uninstallEventTap()
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
        if shouldUseEventTap(for: hotKey) {
            installEventTap()
            return
        }

        var hotKeyID = EventHotKeyID(signature: OSType(0x52544150), id: 1)
        RegisterEventHotKey(hotKey.keyCode, hotKey.carbonModifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        if hotKey.carbonModifiers & UInt32(shiftKey) == 0 {
            var reverseHotKeyID = EventHotKeyID(signature: OSType(0x52544150), id: 2)
            RegisterEventHotKey(hotKey.keyCode, hotKey.carbonModifiers | UInt32(shiftKey), reverseHotKeyID, GetApplicationEventTarget(), 0, &reverseHotKeyRef)
        }
    }

    private func shouldUseEventTap(for hotKey: HotKey) -> Bool {
        hotKey.keyCode == HotKey.commandTab.keyCode
            && hotKey.carbonModifiers & UInt32(cmdKey) != 0
    }

    private func installEventTap() {
        guard eventTap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<HotKeyController>.fromOpaque(userInfo).takeUnretainedValue()
                return controller.handleEventTap(type: type, event: event)
            },
            userInfo: selfPointer
        ) else { return }

        eventTap = tap
        eventTapRunLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let eventTapRunLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func uninstallEventTap() {
        if let eventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapRunLoopSource, .commonModes)
            self.eventTapRunLoopSource = nil
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }

    private func handleEventTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown, let direction = direction(for: event) else {
            if type == .flagsChanged {
                handleEventTapFlagsChanged(event)
            }
            return Unmanaged.passUnretained(event)
        }

        DispatchQueue.main.async { [weak self] in
            self?.onPressed?(direction)
            self?.beginReleaseTracking()
        }
        return nil
    }

    private func handleEventTapFlagsChanged(_ event: CGEvent) {
        guard isTrackingRelease else { return }
        let hotKey = settings.hotKey
        guard shouldUseEventTap(for: hotKey) else { return }
        if !event.flags.contains(carbonModifiers: hotKey.carbonModifiers) {
            DispatchQueue.main.async { [weak self] in
                self?.stopReleaseTracking()
                self?.onReleased?()
            }
        }
    }

    private func direction(for event: CGEvent) -> Direction? {
        let hotKey = settings.hotKey
        let keyCode = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCode == hotKey.keyCode else { return nil }

        let flags = event.flags
        guard flags.contains(carbonModifiers: hotKey.carbonModifiers) else { return nil }

        if hotKey.carbonModifiers & UInt32(shiftKey) == 0, flags.contains(.maskShift) {
            return .backward
        }
        return .forward
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

extension CGEventFlags {
    func contains(carbonModifiers: UInt32) -> Bool {
        if carbonModifiers & UInt32(optionKey) != 0, !contains(.maskAlternate) { return false }
        if carbonModifiers & UInt32(cmdKey) != 0, !contains(.maskCommand) { return false }
        if carbonModifiers & UInt32(controlKey) != 0, !contains(.maskControl) { return false }
        if carbonModifiers & UInt32(shiftKey) != 0, !contains(.maskShift) { return false }
        return true
    }
}
