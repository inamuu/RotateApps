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

final class WindowEnumerator {
    private let chromeProfiles = ChromeProfileResolver()

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
            if chromeProfiles.shouldExcludeWindow(for: app, windowID: windowID) {
                return nil
            }
            return makeWindow(windowID: windowID, ownerPID: ownerPID, ownerName: ownerName, info: info, bounds: bounds, app: app)
        }
        .sorted { lhs, rhs in
            lhs.sortKey.localizedStandardCompare(rhs.sortKey) == .orderedAscending
        }
    }

    private func makeWindow(windowID: UInt32, ownerPID: pid_t, ownerName: String, info: [String: Any], bounds: CGRect, app: NSRunningApplication) -> WindowInfo {
        let title = (info[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Untitled Window"
        let icon = app.icon ?? NSWorkspace.shared.icon(forFileType: "app")
        icon.size = NSSize(width: 64, height: 64)
        return WindowInfo(
            id: windowID,
            ownerPID: ownerPID,
            ownerName: ownerName,
            profileName: chromeProfiles.profileName(for: app, pid: ownerPID, windowID: windowID),
            title: title,
            bounds: bounds,
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

final class ChromeProfileResolver {
    private var localStateCache: [URL: [String: String]] = [:]

    func profileName(for app: NSRunningApplication, pid: pid_t, windowID: CGWindowID) -> String? {
        guard isChromeFamily(app) else { return nil }
        let arguments = processArguments(pid: pid)
        let userDataDirectories = userDataDirectory(from: arguments).map { [$0] } ?? defaultUserDataDirectories(for: app)

        if let profileDirectory = profileDirectory(from: arguments) {
            if let userDataDirectory = userDataDirectory(from: arguments),
               let name = displayName(for: profileDirectory, userDataDirectory: userDataDirectory) {
                return name
            }

            for directory in userDataDirectories {
                if let name = displayName(for: profileDirectory, userDataDirectory: directory) {
                    return name
                }
            }

            return profileDirectory
        }

        return profileNameFromAccessibility(app: app, windowID: windowID, userDataDirectories: userDataDirectories)
    }

    func shouldExcludeWindow(for app: NSRunningApplication, windowID: CGWindowID) -> Bool {
        guard isChromeFamily(app) else { return false }
        guard let window = axWindow(app: app, windowID: windowID) else { return false }

        let role = axString(window, attribute: kAXRoleAttribute)
        let subrole = axString(window, attribute: kAXSubroleAttribute)
        if role == kAXWindowRole, subrole == kAXStandardWindowSubrole {
            return false
        }

        return true
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

    private func profileNameFromAccessibility(app: NSRunningApplication, windowID: CGWindowID, userDataDirectories: [URL]) -> String? {
        let knownProfileNames = userDataDirectories.flatMap { profileNames(userDataDirectory: $0) }
        guard !knownProfileNames.isEmpty else { return nil }

        guard let window = axWindow(app: app, windowID: windowID) else {
            return nil
        }

        return firstProfileName(in: window, profileNames: knownProfileNames)
    }

    private func axWindow(app: NSRunningApplication, windowID: CGWindowID) -> AXUIElement? {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
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
        let cache = localStateCache[userDataDirectory] ?? loadProfileNames(userDataDirectory: userDataDirectory)
        localStateCache[userDataDirectory] = cache
        return cache[profileDirectory]
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
