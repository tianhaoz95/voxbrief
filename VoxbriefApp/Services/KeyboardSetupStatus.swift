import Foundation

/// Best-effort detection of whether the user has added "Voxbrief" as a keyboard and granted it
/// Full Access, so Settings can show one status row instead of just a blind "Open Settings"
/// button (see `SettingsView`).
///
/// Neither signal has a fully-documented public API:
/// - **Added**: reads the `AppleKeyboards` key from standard `UserDefaults` -- a long-standing,
///   widely-used convention (not officially documented, but stable across iOS versions and relied
///   on by many published third-party keyboard apps) listing every currently-enabled keyboard's
///   identifier. If a future iOS version ever changes this, it just degrades to reporting
///   `.notAdded`, which only means the button always offers to open Settings -- never breaks
///   anything, just becomes less informative.
/// - **Full Access**: `UIInputViewController.hasFullAccess` is only readable from inside the
///   keyboard extension itself, so `KeyboardViewController` reports it into the same shared App
///   Group `KeyboardHandoff` already uses for the paste hand-off, and this just reads that back.
public enum KeyboardSetupStatus {
    case notAdded
    case addedFullAccessUnconfirmed
    case ready

    public static var current: KeyboardSetupStatus {
        guard isKeyboardAdded else { return .notAdded }
        return KeyboardHandoff.isFullAccessConfirmed() ? .ready : .addedFullAccessUnconfirmed
    }

    private static let keyboardBundleIdentifier = "com.jacksonzhou666.voxbrief.app.keyboard"

    private static var isKeyboardAdded: Bool {
        guard let keyboards = UserDefaults.standard.array(forKey: "AppleKeyboards") as? [String] else {
            return false
        }
        return keyboards.contains { $0.contains(keyboardBundleIdentifier) }
    }
}
