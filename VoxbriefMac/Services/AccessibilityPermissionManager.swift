import AppKit
import ApplicationServices

/// Tracks whether this app is trusted for Accessibility -- required both to install the global
/// hotkey event tap (`GlobalHotkeyManager`) and to post the synthetic Cmd+V paste (`PasteInjector`).
///
/// Granting happens outside the app, in System Settings > Privacy & Security > Accessibility, so
/// there's no in-app callback for it -- this re-checks whenever the app regains focus (the natural
/// moment right after a user comes back from System Settings) rather than polling on a timer.
@MainActor
public final class AccessibilityPermissionManager: ObservableObject {
    public static let shared = AccessibilityPermissionManager()

    @Published public private(set) var isTrusted: Bool = AXIsProcessTrusted()

    private var didBecomeActiveObserver: NSObjectProtocol?

    public init() {
        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    deinit {
        if let didBecomeActiveObserver {
            NotificationCenter.default.removeObserver(didBecomeActiveObserver)
        }
    }

    public func refresh() {
        isTrusted = AXIsProcessTrusted()
    }

    /// Prompts the system's built-in "would like to control this computer" dialog, which offers a
    /// direct link into the right System Settings pane. Safe to call repeatedly.
    @discardableResult
    public func requestPrompt() -> Bool {
        let options: [String: Bool] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        isTrusted = trusted
        return trusted
    }

    public func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
