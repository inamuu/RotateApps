import AppKit
import Carbon

final class PreferencesWindowController: NSWindowController {
    private let settings: SettingsStore
    private weak var hotKeyController: HotKeyController?
    private let hotKeyButton = NSButton(title: "", target: nil, action: nil)
    private let sizeSlider = NSSlider(value: 150, minValue: 110, maxValue: 240, target: nil, action: nil)
    private let thumbnailCheck = NSButton(checkboxWithTitle: "Show window thumbnails", target: nil, action: nil)
    private var localKeyMonitor: Any?
    private var isRecordingShortcut = false

    init(settings: SettingsStore, hotKeyController: HotKeyController?) {
        self.settings = settings
        self.hotKeyController = hotKeyController
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 210),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "RotateApps Preferences"
        super.init(window: window)
        setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        guard let contentView = window?.contentView else { return }

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 22, left: 22, bottom: 22, right: 22)
        stack.translatesAutoresizingMaskIntoConstraints = false

        hotKeyButton.title = settings.hotKey.displayName
        hotKeyButton.target = self
        hotKeyButton.action = #selector(recordShortcut)

        let hotKeyRow = labeledRow(label: "Shortcut", control: hotKeyButton)

        sizeSlider.doubleValue = Double(settings.itemSize)
        sizeSlider.target = self
        sizeSlider.action = #selector(sizeChanged)
        let sizeRow = labeledRow(label: "Switcher size", control: sizeSlider)

        thumbnailCheck.state = settings.showThumbnails ? .on : .off
        thumbnailCheck.target = self
        thumbnailCheck.action = #selector(thumbnailChanged)

        stack.addArrangedSubview(hotKeyRow)
        stack.addArrangedSubview(sizeRow)
        stack.addArrangedSubview(thumbnailCheck)
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    private func labeledRow(label: String, control: NSView) -> NSView {
        let text = NSTextField(labelWithString: label)
        text.font = .systemFont(ofSize: 13, weight: .medium)
        text.widthAnchor.constraint(equalToConstant: 120).isActive = true

        let row = NSStackView(views: [text, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    @objc private func recordShortcut() {
        isRecordingShortcut = true
        hotKeyButton.title = "Press shortcut..."
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.captureShortcut(event)
            return nil
        }
    }

    private func captureShortcut(_ event: NSEvent) {
        guard isRecordingShortcut else { return }
        let carbonModifiers = event.modifierFlags.carbonModifiers
        guard carbonModifiers != 0 else { return }
        let displayName = ShortcutFormatter.displayName(for: event)
        settings.hotKey = HotKey(keyCode: UInt32(event.keyCode), carbonModifiers: carbonModifiers, displayName: displayName)
        hotKeyButton.title = displayName
        isRecordingShortcut = false
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    @objc private func sizeChanged() {
        settings.itemSize = CGFloat(sizeSlider.doubleValue)
    }

    @objc private func thumbnailChanged() {
        settings.showThumbnails = thumbnailCheck.state == .on
    }
}

extension NSEvent.ModifierFlags {
    var carbonModifiers: UInt32 {
        var modifiers: UInt32 = 0
        if contains(.option) { modifiers |= UInt32(optionKey) }
        if contains(.command) { modifiers |= UInt32(cmdKey) }
        if contains(.control) { modifiers |= UInt32(controlKey) }
        if contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }
}

enum ShortcutFormatter {
    static func displayName(for event: NSEvent) -> String {
        var parts: [String] = []
        if event.modifierFlags.contains(.control) { parts.append("Control") }
        if event.modifierFlags.contains(.option) { parts.append("Option") }
        if event.modifierFlags.contains(.shift) { parts.append("Shift") }
        if event.modifierFlags.contains(.command) { parts.append("Command") }
        parts.append(keyName(for: event.keyCode, fallback: event.charactersIgnoringModifiers))
        return parts.joined(separator: " + ")
    }

    private static func keyName(for keyCode: UInt16, fallback: String?) -> String {
        if keyCode == 48 { return "Tab" }
        if keyCode == 53 { return "Esc" }
        if keyCode == 36 { return "Return" }
        return fallback?.uppercased() ?? "\(keyCode)"
    }
}
