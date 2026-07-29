import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
private func AXUIElementGetWindowID(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

final class SwitcherController {
    private let settings: SettingsStore
    private let enumerator = WindowEnumerator()
    private var panel: SwitcherPanel?
    private var windows: [WindowInfo] = []
    private var selectedIndex = 0
    private var sessionID = 0

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func warmUpWindowDetails() {
        enumerator.warmUp()
    }

    func cycle(direction: HotKeyController.Direction) {
        if panel == nil {
            sessionID += 1
            windows = enumerator.listWindows()
            selectedIndex = initialSelection(direction: direction)
            showPanel()
            refreshAfterResolvingDetails()
        } else {
            selectedIndex = nextSelection(direction: direction)
            panel?.update(windows: windows, selectedIndex: selectedIndex)
        }
    }

    /// The first list is built without Accessibility, so Chrome popups may still be in it and some
    /// profile badges may be missing. Rebuild once the resolver has filled its cache.
    private func refreshAfterResolvingDetails() {
        let session = sessionID
        enumerator.resolveDetails { [weak self] changed in
            guard let self, changed, session == self.sessionID, let panel = self.panel else { return }
            let selectedWindowID = self.windows.indices.contains(self.selectedIndex) ? self.windows[self.selectedIndex].id : nil
            let refreshed = self.enumerator.listWindows()
            guard !refreshed.isEmpty, refreshed.map(\.id) != self.windows.map(\.id) else { return }
            self.windows = refreshed
            self.selectedIndex = selectedWindowID.flatMap { id in refreshed.firstIndex { $0.id == id } }
                ?? min(self.selectedIndex, refreshed.count - 1)
            panel.update(windows: refreshed, selectedIndex: self.selectedIndex)
        }
    }

    func commitSelection() {
        guard windows.indices.contains(selectedIndex) else {
            closePanel()
            return
        }
        let target = windows[selectedIndex]
        closePanel()
        activate(window: target)
    }

    private func showPanel() {
        guard !windows.isEmpty else { return }
        let panel = SwitcherPanel(settings: settings)
        panel.update(windows: windows, selectedIndex: selectedIndex)
        panel.show()
        self.panel = panel
    }

    private func closePanel() {
        panel?.close()
        panel = nil
        windows.removeAll()
        selectedIndex = 0
    }

    private func initialSelection(direction: HotKeyController.Direction) -> Int {
        guard windows.count > 1 else { return 0 }
        return direction == .forward ? 1 : windows.count - 1
    }

    private func nextSelection(direction: HotKeyController.Direction) -> Int {
        guard !windows.isEmpty else { return 0 }
        switch direction {
        case .forward:
            return (selectedIndex + 1) % windows.count
        case .backward:
            return (selectedIndex - 1 + windows.count) % windows.count
        }
    }

    private func activate(window: WindowInfo) {
        let appElement = AXSupport.application(pid: window.ownerPID, timeout: AXSupport.activationTimeout)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let axWindows = value as? [AXUIElement] else {
            NSRunningApplication(processIdentifier: window.ownerPID)?.activate(options: [.activateIgnoringOtherApps])
            return
        }

        NSRunningApplication(processIdentifier: window.ownerPID)?.activate(options: [.activateIgnoringOtherApps])
        if let axWindow = bestMatch(in: axWindows, target: window) {
            focus(axWindow: axWindow, appElement: appElement)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.focus(axWindow: axWindow, appElement: appElement)
            }
        }
    }

    private func focus(axWindow: AXUIElement, appElement: AXUIElement) {
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, axWindow)
        AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(axWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
    }

    private func bestMatch(in axWindows: [AXUIElement], target: WindowInfo) -> AXUIElement? {
        if let exactNumber = axWindows.first(where: { axWindowNumber($0) == target.id }) {
            return exactNumber
        }

        let candidates = axWindows.compactMap { axWindow -> (window: AXUIElement, score: CGFloat)? in
            guard let bounds = axBounds(axWindow) else { return nil }
            return (axWindow, boundsScore(bounds, target: target.bounds))
        }

        if let nearest = candidates.min(by: { $0.score < $1.score }), nearest.score < 80 {
            return nearest.window
        }

        return axWindows.first { axTitle($0) == target.title }
    }

    private func axWindowNumber(_ axWindow: AXUIElement) -> CGWindowID? {
        var windowID: CGWindowID = 0
        if AXUIElementGetWindowID(axWindow, &windowID) == .success, windowID != 0 {
            return windowID
        }

        var axWindowNumber: CFTypeRef?
        if AXUIElementCopyAttributeValue(axWindow, "AXWindowNumber" as CFString, &axWindowNumber) == .success,
           let number = axWindowNumber as? NSNumber {
            return number.uint32Value
        }
        return nil
    }

    private func axTitle(_ axWindow: AXUIElement) -> String? {
        var axTitle: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &axTitle)
        return axTitle as? String
    }

    private func axBounds(_ axWindow: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue else {
            return nil
        }

        let positionAXValue = positionValue as! AXValue
        let sizeAXValue = sizeValue as! AXValue
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionAXValue, .cgPoint, &position),
              AXValueGetValue(sizeAXValue, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: position, size: size)
    }

    private func boundsScore(_ bounds: CGRect, target: CGRect) -> CGFloat {
        abs(bounds.minX - target.minX)
            + abs(bounds.minY - target.minY)
            + abs(bounds.width - target.width)
            + abs(bounds.height - target.height)
    }
}
