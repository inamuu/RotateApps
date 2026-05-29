import AppKit
import ApplicationServices

struct WindowInfo: Identifiable {
    let id: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let title: String
    let bounds: CGRect
    let appIcon: NSImage
}

final class WindowEnumerator {
    func listWindows() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return rawWindows.compactMap { info in
            guard
                let windowID = info[kCGWindowNumber as String] as? UInt32,
                let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                let layer = info[kCGWindowLayer as String] as? Int,
                layer == 0,
                ownerPID != ProcessInfo.processInfo.processIdentifier,
                let ownerName = info[kCGWindowOwnerName as String] as? String,
                let boundsDict = info[kCGWindowBounds as String] as? [String: Any]
            else { return nil }

            guard let app = NSRunningApplication(processIdentifier: ownerPID),
                  app.activationPolicy == .regular else { return nil }

            let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) ?? .zero
            guard bounds.width > 80, bounds.height > 60 else { return nil }
            return makeWindow(windowID: windowID, ownerPID: ownerPID, ownerName: ownerName, info: info, bounds: bounds, app: app)
        }
    }

    private func makeWindow(windowID: UInt32, ownerPID: pid_t, ownerName: String, info: [String: Any], bounds: CGRect, app: NSRunningApplication) -> WindowInfo {
        let title = (info[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled Window"
        let icon = app.icon ?? NSWorkspace.shared.icon(forFileType: "app")
        icon.size = NSSize(width: 64, height: 64)
        return WindowInfo(id: windowID, ownerPID: ownerPID, ownerName: ownerName, title: title, bounds: bounds, appIcon: icon)
    }
}
