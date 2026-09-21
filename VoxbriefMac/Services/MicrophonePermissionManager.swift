import AVFoundation
import AppKit

/// Tracks microphone authorization for the Permissions section in `PreferencesView`. Mirrors
/// `AccessibilityPermissionManager`'s shape: republishes on `didBecomeActiveNotification` so the
/// checkmark updates the moment the user comes back from System Settings, without polling.
@MainActor
public final class MicrophonePermissionManager: ObservableObject {
    public static let shared = MicrophonePermissionManager()

    @Published public private(set) var isAuthorized: Bool = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized

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
        isAuthorized = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
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
            }
        default:
            openSystemSettings()
        }
    }

    public func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") else { return }
        NSWorkspace.shared.open(url)
    }
}
