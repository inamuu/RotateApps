import AppKit
import ApplicationServices
import CoreGraphics

enum Permissions {
    static func requestAccessibilityIfNeeded(prompt: Bool = false) {
        let trusted = AXIsProcessTrusted()
        guard prompt || !trusted else { return }
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static var hasScreenRecording: Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestScreenRecordingIfNeeded(prompt: Bool = false) {
        guard prompt || !hasScreenRecording else { return }
        _ = CGRequestScreenCaptureAccess()
    }
}
