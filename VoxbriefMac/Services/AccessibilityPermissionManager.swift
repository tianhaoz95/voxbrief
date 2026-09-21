import AppKit
import ApplicationServices

/// Tracks whether this app is trusted for Accessibility -- required both to install the global
/// hotkey event tap (`GlobalHotkeyManager`) and to post the synthetic Cmd+V paste (`PasteInjector`).
///
/// Granting happens outside the app, in System Settings > Privacy & Security > Accessibility, so
/// there's no in-app callback for it. `NSApplication.didBecomeActiveNotification` is not a reliable
/// signal for this: Voxbrief is an `LSUIElement` (menu-bar-only, no Dock icon) app, and such
/// accessory apps don't reliably participate in the normal activate/deactivate lifecycle a
/// foreground app gets, so that notification can fire (or not) independently of the user actually
/// returning from System Settings. Instead this polls `AXIsProcessTrusted()` on a timer -- cheap
/// enough to run continuously -- and stops once trusted.
@MainActor
public final class AccessibilityPermissionManager: ObservableObject {
    public static let shared = AccessibilityPermissionManager()

    private static let hasPromptedKey = "accessibility_has_prompted"

    @Published public private(set) var isTrusted: Bool = AXIsProcessTrusted()

    private var pollTimer: Timer?

    public init() {
        startPolling()
    }

    deinit {
        pollTimer?.invalidate()
    }

    public func refresh() {
        isTrusted = AXIsProcessTrusted()
        if isTrusted {
            pollTimer?.invalidate()
            pollTimer = nil
        } else {
            startPolling()
        }
    }

    private func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    /// The single entry point the UI should call for the "Grant Accessibility Access" action.
    ///
    /// The OS only shows its native "would like to control this computer" trust dialog the first
    /// time a given build is asked (via `AXIsProcessTrustedWithOptions` with the prompt option) --
    /// after that it silently returns the current status with no dialog. So the first tap shows
    /// that native dialog (which itself offers a button straight into the right System Settings
    /// pane) and nothing else; only once we know no dialog is coming do we deep-link into System
    /// Settings ourselves, so we never race ahead of a dialog the user hasn't seen yet.
    public func requestAccessOrOpenSettings() {
        if isTrusted {
            return
        }
        let hasPromptedBefore = UserDefaults.standard.bool(forKey: Self.hasPromptedKey)
        if !hasPromptedBefore {
            UserDefaults.standard.set(true, forKey: Self.hasPromptedKey)
            requestPrompt()
        } else {
            openSystemSettings()
        }
        startPolling()
    }

    /// Triggers the system's built-in "would like to control this computer" dialog on its own,
    /// without opening System Settings. Exposed for callers that want just the prompt; prefer
    /// `requestAccessOrOpenSettings()` for UI "grant access" buttons.
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
