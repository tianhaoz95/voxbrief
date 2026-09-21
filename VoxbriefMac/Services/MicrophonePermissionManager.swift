import AVFoundation
import AppKit

/// Tracks microphone authorization for the Permissions section in `PreferencesView`.
///
/// `NSApplication.didBecomeActiveNotification` is not a reliable signal here: Voxbrief is an
/// `LSUIElement` (menu-bar-only, no Dock icon) app, and such accessory apps don't reliably
/// participate in the normal activate/deactivate lifecycle a foreground app gets, so that
/// notification can fire (or not) independently of the user actually returning from System
/// Settings. Instead this polls `AVCaptureDevice.authorizationStatus(for:)` on a timer -- cheap
/// enough to run continuously -- and stops once authorized.
@MainActor
public final class MicrophonePermissionManager: ObservableObject {
    public static let shared = MicrophonePermissionManager()

    @Published public private(set) var isAuthorized: Bool = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

    private var pollTimer: Timer?

    public init() {
        startPolling()
    }

    deinit {
        pollTimer?.invalidate()
    }

    public func refresh() {
        isAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        if isAuthorized {
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

    /// Called from the Preferences "Open System Settings" button. `.notDetermined` (the app has
    /// never actually asked) can only be resolved by `requestAccess` itself -- that's also what
    /// registers this app in System Settings' Microphone list in the first place, so there's
    /// nothing meaningful to "open" yet. Once already `.denied`/`.restricted`, the OS won't
    /// re-prompt, so only then does deep-linking into System Settings make sense.
    public func requestOrOpenSystemSettings() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            Task {
                let granted = await AVCaptureDevice.requestAccess(for: .audio)
                self.isAuthorized = granted
                self.startPolling()
            }
        default:
            openSystemSettings()
            startPolling()
        }
    }

    public func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }
}
