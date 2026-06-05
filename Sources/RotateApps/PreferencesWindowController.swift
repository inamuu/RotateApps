import AppKit
import Carbon

final class PreferencesWindowController: NSWindowController {
    private let settings: SettingsStore
    private weak var hotKeyController: HotKeyController?
    private let hotKeyButton = NSButton(title: "", target: nil, action: nil)
    private let commandTabButton = NSButton(title: "Use Command + Tab", target: nil, action: nil)
    private let resetShortcutButton = NSButton(title: "Reset Default", target: nil, action: nil)
    private let sizeSlider = NSSlider(value: 150, minValue: 100, maxValue: 560, target: nil, action: nil)
    private let sizeValueLabel = NSTextField(labelWithString: "")
    private let themePopup = NSPopUpButton()
    private let thumbnailCheck = NSButton(checkboxWithTitle: "Show window thumbnails", target: nil, action: nil)
    private let saveButton = NSButton(title: "Save Settings", target: nil, action: nil)
    private let revertButton = NSButton(title: "Revert", target: nil, action: nil)
    private var localKeyMonitor: Any?
    private var isRecordingShortcut = false
    private var pendingHotKey: HotKey
    private var pendingItemSize: CGFloat
    private var pendingShowThumbnails: Bool
    private var pendingTheme: SwitcherTheme

    init(settings: SettingsStore, hotKeyController: HotKeyController?) {
        self.settings = settings
        self.hotKeyController = hotKeyController
        self.pendingHotKey = settings.hotKey
        self.pendingItemSize = settings.itemSize
        self.pendingShowThumbnails = settings.showThumbnails
        self.pendingTheme = settings.theme
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 380),
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
        stack.edgeInsets = NSEdgeInsets(top: 26, left: 28, bottom: 26, right: 28)
        stack.translatesAutoresizingMaskIntoConstraints = false

        hotKeyButton.title = pendingHotKey.displayName
        hotKeyButton.target = self
        hotKeyButton.action = #selector(recordShortcut)

        commandTabButton.target = self
        commandTabButton.action = #selector(useCommandTab)
        resetShortcutButton.target = self
        resetShortcutButton.action = #selector(resetShortcut)

        let shortcutControls = NSStackView(views: [hotKeyButton, commandTabButton, resetShortcutButton])
        shortcutControls.orientation = .horizontal
        shortcutControls.alignment = .centerY
        shortcutControls.spacing = 8
        let hotKeyRow = labeledRow(label: "Shortcut", control: shortcutControls)

        sizeSlider.doubleValue = Double(pendingItemSize)
        sizeSlider.target = self
        sizeSlider.action = #selector(sizeChanged)
        sizeValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        sizeValueLabel.alignment = .right
        sizeValueLabel.widthAnchor.constraint(equalToConstant: 54).isActive = true
        updateSizeValueLabel()
        let sizeControls = NSStackView(views: [sizeSlider, sizeValueLabel])
        sizeControls.orientation = .horizontal
        sizeControls.alignment = .centerY
        sizeControls.spacing = 10
        sizeSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 260).isActive = true
        let sizeRow = labeledRow(label: "Switcher size", control: sizeControls)

        for theme in SwitcherTheme.allCases {
            themePopup.addItem(withTitle: theme.displayName)
            themePopup.lastItem?.representedObject = theme.rawValue
        }
        themePopup.selectItem(withTitle: pendingTheme.displayName)
        themePopup.target = self
        themePopup.action = #selector(themeChanged)
        let themeRow = labeledRow(label: "Color theme", control: themePopup)

        thumbnailCheck.state = pendingShowThumbnails ? .on : .off
        thumbnailCheck.target = self
        thumbnailCheck.action = #selector(thumbnailChanged)

        saveButton.target = self
        saveButton.action = #selector(saveSettings)
        saveButton.keyEquivalent = "\r"
        revertButton.target = self
        revertButton.action = #selector(revertSettings)
        let actionRow = actionButtonRow()

        stack.addArrangedSubview(hotKeyRow)
        stack.addArrangedSubview(sizeRow)
        stack.addArrangedSubview(themeRow)
        stack.addArrangedSubview(thumbnailCheck)
        stack.addArrangedSubview(actionRow)
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
        text.widthAnchor.constraint(equalToConstant: 132).isActive = true

        let row = NSStackView(views: [text, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func actionButtonRow() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [spacer, revertButton, saveButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    @objc private func recordShortcut() {
        stopRecordingShortcut()
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
        pendingHotKey = HotKey(keyCode: UInt32(event.keyCode), carbonModifiers: carbonModifiers, displayName: displayName)
        hotKeyButton.title = displayName
        stopRecordingShortcut()
    }

    @objc private func useCommandTab() {
        stopRecordingShortcut()
        Permissions.requestAccessibilityIfNeeded(prompt: true)
        applyShortcut(.commandTab)
    }

    @objc private func resetShortcut() {
        stopRecordingShortcut()
        applyShortcut(.optionTab)
    }

    private func applyShortcut(_ hotKey: HotKey) {
        pendingHotKey = hotKey
        hotKeyButton.title = hotKey.displayName
    }

    private func stopRecordingShortcut() {
        isRecordingShortcut = false
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
    }

    @objc private func sizeChanged() {
        pendingItemSize = CGFloat(sizeSlider.doubleValue)
        updateSizeValueLabel()
    }

    @objc private func thumbnailChanged() {
        pendingShowThumbnails = thumbnailCheck.state == .on
    }

    @objc private func themeChanged() {
        guard let rawValue = themePopup.selectedItem?.representedObject as? String,
              let theme = SwitcherTheme(rawValue: rawValue) else { return }
        pendingTheme = theme
    }

    @objc private func saveSettings() {
        stopRecordingShortcut()
        if settings.itemSize != pendingItemSize {
            settings.itemSize = pendingItemSize
        }
        if settings.showThumbnails != pendingShowThumbnails {
            settings.showThumbnails = pendingShowThumbnails
        }
        if settings.theme != pendingTheme {
            settings.theme = pendingTheme
        }
        if settings.hotKey != pendingHotKey {
            settings.hotKey = pendingHotKey
        }
    }

    @objc private func revertSettings() {
        stopRecordingShortcut()
        pendingHotKey = settings.hotKey
        pendingItemSize = settings.itemSize
        pendingShowThumbnails = settings.showThumbnails
        pendingTheme = settings.theme
        hotKeyButton.title = pendingHotKey.displayName
        sizeSlider.doubleValue = Double(pendingItemSize)
        updateSizeValueLabel()
        thumbnailCheck.state = pendingShowThumbnails ? .on : .off
        themePopup.selectItem(withTitle: pendingTheme.displayName)
    }

    private func updateSizeValueLabel() {
        sizeValueLabel.stringValue = "\(Int(round(pendingItemSize))) px"
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
