import AppKit
import ApplicationServices
import UniformTypeIdentifiers

@_silgen_name("_AXUIElementGetWindow")
private func AXUIElementGetWindowID(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

struct WindowInfo: Identifiable {
    let id: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let profileName: String?
    let title: String
    let bounds: CGRect
    let appIcon: NSImage
}

/// A window straight out of the CoreGraphics window list, before any Accessibility lookup.
struct WindowCandidate {
    let id: CGWindowID
    let ownerPID: pid_t
    let ownerName: String
    let title: String
    let bounds: CGRect
    let app: NSRunningApplication
}

final class WindowEnumerator {
    private let chromeProfiles = ChromeProfileResolver()
    private var iconCache: [pid_t: NSImage] = [:]

    /// The focused window as of the last `listWindows()` call. The returned list is sorted for a
    /// stable grid, so rotation needs this to know where it starts from.
    private(set) var frontmostWindowID: CGWindowID?

    /// Never blocks on Accessibility: everything that needs it comes from the resolver cache and is
    /// filled in by `resolveDetails`. Keeping this cheap is what keeps the hotkey responsive.
    func listWindows() -> [WindowInfo] {
        // `candidates()` is in CoreGraphics front-to-back order, which this keeps until the sort.
        let candidates = candidates()
        let visible = candidates.compactMap { candidate -> WindowInfo? in
            let details = chromeProfiles.details(for: candidate)
            guard !details.isExcluded else { return nil }
            return makeWindow(candidate: candidate, profileName: details.profileName)
        }

        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        frontmostWindowID = visible.first { $0.ownerPID == frontmostPID }?.id ?? visible.first?.id

        let livePIDs = Set(candidates.map(\.ownerPID))
        iconCache = iconCache.filter { livePIDs.contains($0.key) }

        // Sorting by app, then profile, then window number keeps the grid stable across sessions.
        // Titles change every time a tab switches, so they are deliberately not part of the key.
        return visible.sorted { lhs, rhs in
            let byApp = lhs.ownerName.localizedStandardCompare(rhs.ownerName)
            if byApp != .orderedSame { return byApp == .orderedAscending }
            let byProfile = (lhs.profileName ?? "").localizedStandardCompare(rhs.profileName ?? "")
            if byProfile != .orderedSame { return byProfile == .orderedAscending }
            return lhs.id < rhs.id
        }
    }

    /// Window IDs the switcher would show right now, used to keep the thumbnail cache warm.
    func visibleWindowIDs() -> [CGWindowID] {
        candidates().compactMap { candidate in
            chromeProfiles.details(for: candidate).isExcluded ? nil : candidate.id
        }
    }

    /// Resolves the Accessibility-backed details (Chrome popup filtering, profile names) on a
    /// background queue. `completion` reports whether the cache changed, i.e. whether a visible
    /// list built before this call is now stale.
    func resolveDetails(completion: @escaping (Bool) -> Void) {
        let pending = candidates()
        DispatchQueue.global(qos: .userInitiated).async { [chromeProfiles] in
            let changed = chromeProfiles.resolveMissingDetails(for: pending)
            DispatchQueue.main.async { completion(changed) }
        }
    }

    /// Warms the cache so the first press after a window change is already accurate.
    func warmUp() {
        resolveDetails { _ in }
    }

    private func candidates() -> [WindowCandidate] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let rawWindows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        var appsByPID: [pid_t: NSRunningApplication?] = [:]
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

            let app: NSRunningApplication?
            if let known = appsByPID[ownerPID] {
                app = known
            } else {
                app = NSRunningApplication(processIdentifier: ownerPID)
                appsByPID[ownerPID] = app
            }
            guard let app, app.activationPolicy == .regular else { return nil }

            let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) ?? .zero
            guard bounds.width > 80, bounds.height > 60 else { return nil }

            let title = (info[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled Window"
            return WindowCandidate(
                id: windowID,
                ownerPID: ownerPID,
                ownerName: ownerName,
                title: title,
                bounds: bounds,
                app: app
            )
        }
    }

    private func makeWindow(candidate: WindowCandidate, profileName: String?) -> WindowInfo {
        WindowInfo(
            id: candidate.id,
            ownerPID: candidate.ownerPID,
            ownerName: candidate.ownerName,
            profileName: profileName,
            title: candidate.title,
            bounds: candidate.bounds,
            appIcon: icon(for: candidate.app)
        )
    }

    /// `NSRunningApplication.icon` hands back a shared image, so it is copied once per process
    /// instead of being resized in place on every listing.
    private func icon(for app: NSRunningApplication) -> NSImage {
        let pid = app.processIdentifier
        if let cached = iconCache[pid] { return cached }
        let source = app.icon ?? NSWorkspace.shared.icon(for: .application)
        let icon = (source.copy() as? NSImage) ?? source
        icon.size = NSSize(width: 64, height: 64)
        iconCache[pid] = icon
        return icon
    }
}

struct ChromeWindowDetails {
    static let included = ChromeWindowDetails(profileName: nil, isExcluded: false)
    static let excluded = ChromeWindowDetails(profileName: nil, isExcluded: true)

    let profileName: String?
    let isExcluded: Bool
}

/// Resolves Chrome-family profile names and filters non-standard Chrome windows.
///
/// Chrome puts the profile into its Accessibility window title (`Page - Google Chrome - Name`)
/// whenever more than one profile exists, so one attribute read per window is enough. The
/// CoreGraphics title cannot be used for this: it is truncated and lacks the suffix. Accessibility
/// calls block until the target answers, so results are cached per window and only ever computed
/// off the main thread.
final class ChromeProfileResolver {
    private let lock = NSLock()
    private var windowDetailsCache: [CGWindowID: ChromeWindowDetails] = [:]

    /// Synchronous, non-blocking. Unresolved Chrome windows are shown without a profile badge and
    /// corrected in place once `resolveMissingDetails` runs.
    func details(for candidate: WindowCandidate) -> ChromeWindowDetails {
        guard isChromeFamily(candidate.app) else { return .included }
        lock.lock()
        defer { lock.unlock() }
        return windowDetailsCache[candidate.id] ?? .included
    }

    /// Call from a background queue only.
    /// - Returns: whether any cache entry was added or removed.
    func resolveMissingDetails(for candidates: [WindowCandidate]) -> Bool {
        let liveWindowIDs = Set(candidates.map(\.id))

        lock.lock()
        let staleWindowIDs = windowDetailsCache.keys.filter { !liveWindowIDs.contains($0) }
        for windowID in staleWindowIDs {
            windowDetailsCache.removeValue(forKey: windowID)
        }
        let resolvedWindowIDs = Set(windowDetailsCache.keys)
        lock.unlock()

        let pending = candidates.filter { isChromeFamily($0.app) && !resolvedWindowIDs.contains($0.id) }
        guard !pending.isEmpty else { return !staleWindowIDs.isEmpty }

        var didResolve = false
        // One window-list fetch per process instead of one per window.
        for (pid, windows) in Dictionary(grouping: pending, by: \.ownerPID) {
            let axWindows = axWindowsByID(pid: pid)
            for candidate in windows {
                // Leave the entry unresolved when the app did not answer, so the next warm-up retries.
                guard let axWindow = axWindows[candidate.id] else { continue }
                let details = inspect(axWindow: axWindow)
                lock.lock()
                windowDetailsCache[candidate.id] = details
                lock.unlock()
                didResolve = true
            }
        }

        return didResolve || !staleWindowIDs.isEmpty
    }

    private func inspect(axWindow: AXUIElement) -> ChromeWindowDetails {
        let role = axString(axWindow, attribute: kAXRoleAttribute)
        let subrole = axString(axWindow, attribute: kAXSubroleAttribute)
        guard role == kAXWindowRole, subrole == kAXStandardWindowSubrole else {
            return .excluded
        }

        let title = axString(axWindow, attribute: kAXTitleAttribute) ?? ""
        return ChromeWindowDetails(profileName: Self.profileName(fromTitle: title), isExcluded: false)
    }

    /// `"Page title - Google Chrome - Alice (Work)"` -> `"Alice (Work)"`. The page title may itself
    /// contain ` - `, so the browser name is looked for in the second-to-last segment.
    static func profileName(fromTitle title: String) -> String? {
        let segments = title.components(separatedBy: " - ")
        guard segments.count >= 3 else { return nil }
        let browser = segments[segments.count - 2]
        guard ["Chrome", "Chromium", "Edge", "Brave"].contains(where: { browser.contains($0) }) else { return nil }
        let name = segments[segments.count - 1].trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private func isChromeFamily(_ app: NSRunningApplication) -> Bool {
        let bundleID = app.bundleIdentifier ?? ""
        let name = app.localizedName ?? ""
        return bundleID == "com.google.Chrome"
            || bundleID == "com.google.Chrome.beta"
            || bundleID == "com.google.Chrome.canary"
            || bundleID == "com.microsoft.edgemac"
            || bundleID == "com.brave.Browser"
            || bundleID == "org.chromium.Chromium"
            || name.contains("Chrome")
            || name.contains("Chromium")
            || name.contains("Brave Browser")
            || name.contains("Microsoft Edge")
    }

    private func axWindowsByID(pid: pid_t) -> [CGWindowID: AXUIElement] {
        let appElement = AXSupport.application(pid: pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else {
            return [:]
        }

        var result: [CGWindowID: AXUIElement] = [:]
        for window in windows {
            if let id = axWindowNumber(window), result[id] == nil {
                result[id] = window
            }
        }
        return result
    }

    private func axString(_ element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
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
}
