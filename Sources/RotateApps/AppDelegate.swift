import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private var statusItem: NSStatusItem?
    private var hotKeyController: HotKeyController?
    private var switcherController: SwitcherController?
    private var preferencesWindow: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let switcherController = SwitcherController(settings: settings)
        let hotKeyController = HotKeyController(settings: settings)
        hotKeyController.onPressed = { [weak switcherController] direction in
            switcherController?.cycle(direction: direction)
        }
        hotKeyController.onReleased = { [weak switcherController] in
            switcherController?.commitSelection()
        }
        self.switcherController = switcherController
        self.hotKeyController = hotKeyController

        setupStatusItem()
        hotKeyController.start()
        Permissions.requestAccessibilityIfNeeded()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.2.swap", accessibilityDescription: "RotateApps")

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Request Accessibility Permission", action: #selector(requestAccessibility), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Request Screen Recording Permission", action: #selector(requestScreenRecording), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Reset macOS Permissions", action: #selector(resetPermissions), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit RotateApps", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func openPreferences() {
        if preferencesWindow == nil {
            preferencesWindow = PreferencesWindowController(settings: settings, hotKeyController: hotKeyController)
        }
        preferencesWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func requestAccessibility() {
        Permissions.requestAccessibilityIfNeeded(prompt: true)
    }

    @objc private func requestScreenRecording() {
        Permissions.requestScreenRecordingIfNeeded(prompt: true)
    }

    @objc private func resetPermissions() {
        let accessibilityResult = resetTCC(service: "Accessibility")
        let screenCaptureResult = resetTCC(service: "ScreenCapture")

        let alert = NSAlert()
        alert.messageText = "macOS permissions reset"
        alert.informativeText = [
            "Accessibility: \(accessibilityResult)",
            "Screen Recording: \(screenCaptureResult)",
            "Quit and reopen RotateApps, then request the permissions again."
        ].joined(separator: "\n")
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func resetTCC(service: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", service, "com.inamuu.RotateApps"]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0 ? "reset" : "failed"
        } catch {
            return "failed"
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
