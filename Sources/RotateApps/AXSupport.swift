import ApplicationServices

/// Accessibility calls block the calling thread until the target app answers. The default
/// timeout is several seconds, which is long enough to freeze the hotkey path, so we keep a
/// short global default and only relax it where a slow answer is better than no answer.
enum AXSupport {
    static let inspectionTimeout: Float = 0.25
    static let activationTimeout: Float = 1.0

    /// Applies `inspectionTimeout` as the default for every element that has no explicit timeout.
    static func applyGlobalTimeout() {
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), inspectionTimeout)
    }

    static func application(pid: pid_t, timeout: Float = inspectionTimeout) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, timeout)
        return element
    }
}
