import AppKit
import ApplicationServices

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

    /// Never blocks on Accessibility: everything that needs it comes from the resolver cache and is
    /// filled in by `resolveDetails`. Keeping this cheap is what keeps the hotkey responsive.
    func listWindows() -> [WindowInfo] {
        candidates()
            .compactMap { candidate in
                let details = chromeProfiles.details(for: candidate)
                guard !details.isExcluded else { return nil }
                return makeWindow(candidate: candidate, profileName: details.profileName)
            }
            .sorted { lhs, rhs in
                lhs.sortKey.localizedStandardCompare(rhs.sortKey) == .orderedAscending
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
        let icon = candidate.app.icon ?? NSWorkspace.shared.icon(forFileType: "app")
        icon.size = NSSize(width: 64, height: 64)
        return WindowInfo(
            id: candidate.id,
            ownerPID: candidate.ownerPID,
            ownerName: candidate.ownerName,
            profileName: profileName,
            title: candidate.title,
            bounds: candidate.bounds,
            appIcon: icon
        )
    }
}

private extension WindowInfo {
    var sortKey: String {
        [
            ownerName,
            profileName ?? "",
            title,
            String(id)
        ].joined(separator: "\u{0}")
    }
}

struct ChromeWindowDetails {
    static let included = ChromeWindowDetails(profileName: nil, isExcluded: false)

    let profileName: String?
    let isExcluded: Bool
}

/// Resolves Chrome-family profile names and filters non-standard Chrome windows.
///
/// The Accessibility part (window subrole, and the tree walk used when the profile can't be read
/// from the process arguments) is slow and can block for as long as the target app takes to answer,
/// so it is cached per window and only ever computed off the main thread.
final class ChromeProfileResolver {
    private let lock = NSLock()
    private var localStateCache: [URL: [String: String]] = [:]
    private var argumentsCache: [pid_t: [String]] = [:]
    private var windowDetailsCache: [CGWindowID: ChromeWindowDetails] = [:]

    /// Synchronous, non-blocking. Unresolved Chrome windows are shown (never hidden) with whatever
    /// profile name the process arguments give us, and corrected once `resolveMissingDetails` runs.
    func details(for candidate: WindowCandidate) -> ChromeWindowDetails {
        guard isChromeFamily(candidate.app) else { return .included }

        lock.lock()
        let cached = windowDetailsCache[candidate.id]
        lock.unlock()
        if let cached { return cached }

        return ChromeWindowDetails(profileName: profileNameFromArguments(candidate: candidate), isExcluded: false)
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

        var didResolve = false
        for candidate in candidates where isChromeFamily(candidate.app) && !resolvedWindowIDs.contains(candidate.id) {
            let details = resolveDetails(for: candidate)
            lock.lock()
            windowDetailsCache[candidate.id] = details
            lock.unlock()
            didResolve = true
        }

        return didResolve || !staleWindowIDs.isEmpty
    }

    private func resolveDetails(for candidate: WindowCandidate) -> ChromeWindowDetails {
        guard let window = axWindow(app: candidate.app, windowID: candidate.id) else {
            return ChromeWindowDetails(profileName: profileNameFromArguments(candidate: candidate), isExcluded: false)
        }

        let role = axString(window, attribute: kAXRoleAttribute)
        let subrole = axString(window, attribute: kAXSubroleAttribute)
        guard role == kAXWindowRole, subrole == kAXStandardWindowSubrole else {
            return ChromeWindowDetails(profileName: nil, isExcluded: true)
        }

        if let profileName = profileNameFromArguments(candidate: candidate) {
            return ChromeWindowDetails(profileName: profileName, isExcluded: false)
        }

        let userDataDirectories = self.userDataDirectories(for: candidate)
        let profileName = profileNameFromAccessibility(window: window, userDataDirectories: userDataDirectories)
        return ChromeWindowDetails(profileName: profileName, isExcluded: false)
    }

    private func profileNameFromArguments(candidate: WindowCandidate) -> String? {
        let arguments = arguments(for: candidate.ownerPID)
        guard let profileDirectory = profileDirectory(from: arguments) else { return nil }

        if let userDataDirectory = userDataDirectory(from: arguments),
           let name = displayName(for: profileDirectory, userDataDirectory: userDataDirectory) {
            return name
        }

        for directory in userDataDirectories(for: candidate) {
            if let name = displayName(for: profileDirectory, userDataDirectory: directory) {
                return name
            }
        }

        return profileDirectory
    }

    private func userDataDirectories(for candidate: WindowCandidate) -> [URL] {
        let arguments = arguments(for: candidate.ownerPID)
        return userDataDirectory(from: arguments).map { [$0] } ?? defaultUserDataDirectories(for: candidate.app)
    }

    private func arguments(for pid: pid_t) -> [String] {
        lock.lock()
        let cached = argumentsCache[pid]
        lock.unlock()
        if let cached { return cached }

        let arguments = processArguments(pid: pid)
        lock.lock()
        argumentsCache[pid] = arguments
        lock.unlock()
        return arguments
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

    private func profileDirectory(from arguments: [String]) -> String? {
        argumentValue(named: "--profile-directory", in: arguments)
    }

    private func userDataDirectory(from arguments: [String]) -> URL? {
        argumentValue(named: "--user-data-dir", in: arguments).map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
    }

    private func argumentValue(named name: String, in arguments: [String]) -> String? {
        for (index, argument) in arguments.enumerated() {
            if argument == name, arguments.indices.contains(index + 1) {
                return arguments[index + 1]
            }
            if argument.hasPrefix(name + "=") {
                return String(argument.dropFirst(name.count + 1))
            }
        }
        return nil
    }

    private func defaultUserDataDirectories(for app: NSRunningApplication) -> [URL] {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let applicationSupport else { return [] }

        switch app.bundleIdentifier {
        case "com.microsoft.edgemac":
            return [applicationSupport.appendingPathComponent("Microsoft Edge")]
        case "com.brave.Browser":
            return [applicationSupport.appendingPathComponent("BraveSoftware/Brave-Browser")]
        case "org.chromium.Chromium":
            return [applicationSupport.appendingPathComponent("Chromium")]
        default:
            return [
                applicationSupport.appendingPathComponent("Google/Chrome"),
                applicationSupport.appendingPathComponent("Google/Chrome Beta"),
                applicationSupport.appendingPathComponent("Google/Chrome Canary")
            ]
        }
    }

    private func profileNameFromAccessibility(window: AXUIElement, userDataDirectories: [URL]) -> String? {
        let knownProfileNames = userDataDirectories.flatMap { profileNames(userDataDirectory: $0) }
        guard !knownProfileNames.isEmpty else { return nil }
        return firstProfileName(in: window, profileNames: knownProfileNames)
    }

    private func axWindow(app: NSRunningApplication, windowID: CGWindowID) -> AXUIElement? {
        let appElement = AXSupport.application(pid: app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else {
            return nil
        }

        return windows.first { axWindowNumber($0) == windowID }
    }

    private func profileNames(userDataDirectory: URL) -> [String] {
        let names = loadProfileNames(userDataDirectory: userDataDirectory).values
        return names
            .filter { !$0.isEmpty && $0 != "Person 1" && $0 != "Default" }
            .sorted { $0.count > $1.count }
    }

    private func firstProfileName(in element: AXUIElement, profileNames: [String]) -> String? {
        var visited = 0
        return firstProfileName(in: element, profileNames: profileNames, visited: &visited)
    }

    private func firstProfileName(in element: AXUIElement, profileNames: [String], visited: inout Int) -> String? {
        visited += 1
        guard visited < 500 else { return nil }

        for attribute in [
            kAXTitleAttribute,
            kAXDescriptionAttribute,
            kAXValueAttribute,
            kAXHelpAttribute
        ] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
                  let text = value as? String else { continue }
            if let match = profileNames.first(where: { text.localizedCaseInsensitiveContains($0) }) {
                return match
            }
        }

        var childrenValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
              let children = childrenValue as? [AXUIElement] else {
            return nil
        }

        for child in children {
            if let match = firstProfileName(in: child, profileNames: profileNames, visited: &visited) {
                return match
            }
        }
        return nil
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

    private func displayName(for profileDirectory: String, userDataDirectory: URL) -> String? {
        lock.lock()
        var cache = localStateCache[userDataDirectory]
        lock.unlock()

        if cache == nil {
            let loaded = loadProfileNames(userDataDirectory: userDataDirectory)
            lock.lock()
            localStateCache[userDataDirectory] = loaded
            lock.unlock()
            cache = loaded
        }
        return cache?[profileDirectory]
    }

    private func loadProfileNames(userDataDirectory: URL) -> [String: String] {
        let localStateURL = userDataDirectory.appendingPathComponent("Local State")
        guard let data = try? Data(contentsOf: localStateURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let infoCache = profile["info_cache"] as? [String: Any] else {
            return [:]
        }

        var result: [String: String] = [:]
        for (directory, value) in infoCache {
            guard let details = value as? [String: Any],
                  let name = details["name"] as? String,
                  !name.isEmpty else { continue }
            result[directory] = name
        }
        return result
    }

    private func processArguments(pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > 0 else {
            return []
        }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, u_int(mib.count), &buffer, &size, nil, 0) == 0, size >= MemoryLayout<Int32>.size else {
            return []
        }

        let argc = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard argc > 0 else { return [] }

        var offset = MemoryLayout<Int32>.size
        while offset < size, buffer[offset] != 0 {
            offset += 1
        }
        while offset < size, buffer[offset] == 0 {
            offset += 1
        }

        var arguments: [String] = []
        for _ in 0..<argc {
            guard offset < size else { break }
            let start = offset
            while offset < size, buffer[offset] != 0 {
                offset += 1
            }
            if start < offset, let argument = String(bytes: buffer[start..<offset], encoding: .utf8) {
                arguments.append(argument)
            }
            while offset < size, buffer[offset] == 0 {
                offset += 1
            }
        }
        return arguments
    }
}
