import Foundation

/// Shared storage for handing a finished voice note's text back to `VoxbriefKeyboard` once the
/// main `Voxbrief` app (opened via the keyboard's "Record" button, see `KeyboardView`) finishes
/// processing it.
///
/// Both targets need the same App Group entitlement (`group.com.jacksonzhou666.voxbrief`) for this
/// `UserDefaults` suite to be visible to both -- the keyboard extension additionally needs the
/// user to have granted it "Allow Full Access" in Settings, since App Groups are one of the
/// capabilities iOS blocks from a keyboard extension without it (same gate as network access or
/// the microphone). `defaults` is `nil` when that isn't the case, and every call here degrades to
/// a harmless no-op rather than crashing.
///
/// There is deliberately no way for the main app to force the user back into the host app it was
/// opened from -- iOS has no public API for an app to programmatically return to its caller (see
/// CLAUDE.md). The keyboard just checks for a pending result every time it becomes active again
/// (i.e. whenever the user manually switches back), which is the best available approximation.
public enum KeyboardHandoff {
    public static let appGroupID = "group.com.jacksonzhou666.voxbrief"
    private static let pendingTextKey = "keyboard_pending_paste_text"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    /// Called by the main app once a keyboard-triggered note finishes processing.
    public static func setPendingPaste(_ text: String) {
        defaults?.set(text, forKey: pendingTextKey)
    }

    /// Called by the keyboard extension every time it becomes active. Returns and clears the
    /// pending text, if any, so it's only ever inserted once even if checked repeatedly.
    public static func consumePendingPaste() -> String? {
        guard let defaults, let text = defaults.string(forKey: pendingTextKey), !text.isEmpty else { return nil }
        defaults.removeObject(forKey: pendingTextKey)
        return text
    }

    // MARK: - Setup status (read by the main app's Settings screen -- see KeyboardSetupStatus)

    private static let fullAccessConfirmedKey = "keyboard_full_access_confirmed"

    /// Called by the keyboard extension every time it becomes active with `hasFullAccess == true`.
    /// This is the only way the main app can ever learn Full Access was granted --
    /// `UIInputViewController.hasFullAccess` is readable only from inside the extension itself.
    /// Only ever writes `true`; when access isn't granted this is simply never called, and the
    /// write likely wouldn't reach the shared container in that case anyway (see the type's doc
    /// comment on `defaults`).
    public static func reportFullAccessGranted() {
        defaults?.set(true, forKey: fullAccessConfirmedKey)
    }

    /// Best-effort and one-directional: `true` once the keyboard has confirmed Full Access at
    /// least once (the last time it actually ran); `false` both when it's genuinely not granted
    /// *and* when the keyboard has simply never run yet -- there's no way to tell those two apart
    /// from the main app. Can also go stale if the user grants Full Access, then later revokes it
    /// without the keyboard running again in between; there's no negative signal to catch that.
    public static func isFullAccessConfirmed() -> Bool {
        defaults?.bool(forKey: fullAccessConfirmedKey) ?? false
    }
}
