import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
private func AXUIElementGetWindowID(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

final class SwitcherController {
    /// Thumbnails older than this are re-captured during a warm-up. Sessions themselves refresh
    /// more eagerly (see `SwitcherItemView`), so this only bounds how stale the first frame can be.
    private static let warmUpThumbnailMaxAge: TimeInterval = 30

    private let settings: SettingsStore
    private let enumerator = WindowEnumerator()
    private let panel: SwitcherPanel
    private var isShowing = false
    private var windows: [WindowInfo] = []
    private var selectedIndex = 0
    private var sessionID = 0

    init(settings: SettingsStore) {
        self.settings = settings
        // Built once at launch: creating the panel and its blur view is too slow for the hotkey path.
        self.panel = SwitcherPanel(settings: settings)
    }

    func warmUpWindowDetails() {
        enumerator.warmUp()
        if settings.showThumbnails {
            ThumbnailCache.shared.warmUp(windowIDs: enumerator.visibleWindowIDs(), maxAge: Self.warmUpThumbnailMaxAge)
        }
    }

    func cycle(direction: HotKeyController.Direction) {
        if !isShowing {
            sessionID += 1
            windows = enumerator.listWindows()
            selectedIndex = initialSelection(direction: direction)
            showPanel()
            refreshAfterResolvingDetails()
        } else {
            selectedIndex = nextSelection(direction: direction)
            panel.update(windows: windows, selectedIndex: selectedIndex)
        }
    }

    /// The first list is built without Accessibility, so a brand-new Chrome window may still be
    /// missing its profile badge or be a popup that should not be listed. Once the resolver has
    /// filled its cache the list is rebuilt, but in the order already on screen: shuffling the grid
    /// under the user's fingers is exactly the "stuck" feeling this avoids.
    private func refreshAfterResolvingDetails() {
        let session = sessionID
        enumerator.resolveDetails { [weak self] changed in
            guard let self, changed, session == self.sessionID, self.isShowing else { return }
            let refreshed = self.enumerator.listWindows()
            guard !refreshed.isEmpty else { return }

            let refreshedByID = Dictionary(refreshed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var merged = self.windows.compactMap { refreshedByID[$0.id] }
            let knownIDs = Set(merged.map(\.id))
            merged += refreshed.filter { !knownIDs.contains($0.id) }

            let selectedWindowID = self.windows.indices.contains(self.selectedIndex) ? self.windows[self.selectedIndex].id : nil
            self.windows = merged
            self.selectedIndex = selectedWindowID.flatMap { id in merged.firstIndex { $0.id == id } }
                ?? min(self.selectedIndex, merged.count - 1)
            self.panel.update(windows: merged, selectedIndex: self.selectedIndex)
        }
    }

    func commitSelection() {
        guard isShowing else { return }
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
        panel.update(windows: windows, selectedIndex: selectedIndex)
        panel.show()
        isShowing = true
    }

    private func closePanel() {
        panel.hide()
        isShowing = false
        windows.removeAll()
        selectedIndex = 0
    }

    /// Starts from the window that currently has focus, so a single press always lands on a
    /// different window instead of on wherever the sorted list happens to begin.
    private func initialSelection(direction: HotKeyController.Direction) -> Int {
        guard windows.count > 1 else { return 0 }
        let currentIndex = enumerator.frontmostWindowID.flatMap { id in
            windows.firstIndex { $0.id == id }
        } ?? 0
        switch direction {
        case .forward:
            return (currentIndex + 1) % windows.count
        case .backward:
            return (currentIndex - 1 + windows.count) % windows.count
        }
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

    /// The app is activated right away on the main thread; picking and raising the exact window
    /// needs Accessibility round-trips that can take up to `activationTimeout`, so those run in the
    /// background where they cannot delay the next hotkey press.
    private func activate(window: WindowInfo) {
        NSRunningApplication(processIdentifier: window.ownerPID)?.activate()

        DispatchQueue.global(qos: .userInteractive).async {
            let appElement = AXSupport.application(pid: window.ownerPID, timeout: AXSupport.activationTimeout)
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
            guard result == .success, let axWindows = value as? [AXUIElement],
                  let axWindow = Self.bestMatch(in: axWindows, target: window) else { return }

            Self.focus(axWindow: axWindow, appElement: appElement)
            // Some apps reorder their windows while activating; a second pass after they settle
            // makes sure the chosen window ends up on top.
            usleep(50_000)
            Self.focus(axWindow: axWindow, appElement: appElement)
        }
    }

    private static func focus(axWindow: AXUIElement, appElement: AXUIElement) {
        AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, axWindow)
        AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(axWindow, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
    }

    private static func bestMatch(in axWindows: [AXUIElement], target: WindowInfo) -> AXUIElement? {
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

    private static func axWindowNumber(_ axWindow: AXUIElement) -> CGWindowID? {
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

    private static func axTitle(_ axWindow: AXUIElement) -> String? {
        var axTitle: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &axTitle)
        return axTitle as? String
    }

    private static func axBounds(_ axWindow: AXUIElement) -> CGRect? {
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

    private static func boundsScore(_ bounds: CGRect, target: CGRect) -> CGFloat {
        abs(bounds.minX - target.minX)
            + abs(bounds.minY - target.minY)
            + abs(bounds.width - target.width)
            + abs(bounds.height - target.height)
    }
}
