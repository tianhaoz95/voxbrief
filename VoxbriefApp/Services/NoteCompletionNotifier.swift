import UserNotifications

/// Fires a local notification when a keyboard-triggered recording finishes processing, so the
/// user doesn't have to stay in Voxbrief -- or remember to check back -- waiting for it. Purely
/// on-device: `UNUserNotificationCenter`'s local (not remote) notification API, no backend or
/// APNs involved, consistent with this app having no server component at all.
public enum NoteCompletionNotifier {
    public static func notifyReady() {
        schedule(
            title: "Ready to paste",
            body: "Your Voxbrief note is ready. Switch back to where you were typing to paste it in."
        )
    }

    public static func notifyFailed() {
        schedule(
            title: "Voxbrief couldn't finish",
            body: "Something went wrong processing your recording. Open Voxbrief to see what happened."
        )
    }

    private static func schedule(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        // Safe to call every time: after the first ask, iOS just reports the existing decision
        // instead of re-prompting, so this never shows a second permission dialog.
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            center.add(request)
        }
    }
}
