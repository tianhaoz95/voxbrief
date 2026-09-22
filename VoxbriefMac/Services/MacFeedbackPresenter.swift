import AppKit
import Foundation
import SwiftUI
#if canImport(FeedbackKit)
import FeedbackKit
#endif

/// Presents the FeedbackKit submission interface on macOS, ensuring a suitable host window
/// is active and visible even when Voxbrief is running in the background as a menu bar app.
@MainActor
public enum MacFeedbackPresenter {
    private static var lastTriggerTime: TimeInterval = 0
    private static var temporaryHostWindow: NSWindow?

    public static func openFeedback() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTriggerTime > 0.5 else { return }
        lastTriggerTime = now

        #if canImport(FeedbackKit)
        NSApp.activate(ignoringOtherApps: true)

        let targetWindow = NSApp.keyWindow ?? NSApp.windows.first(where: {
            $0.isVisible && $0.canBecomeKey && !($0 is NSPanel)
        })

        if let targetWindow {
            targetWindow.makeKeyAndOrderFront(nil)
            DispatchQueue.main.async {
                FeedbackKit.presentAndSubmit(from: targetWindow) { _ in }
            }
        } else {
            // No window currently open -- create a lightweight host window for FeedbackKit
            // to sheet onto, and tear it down automatically when feedback submission completes or cancels.
            let hostWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            hostWindow.title = "Voxbrief Feedback"
            hostWindow.isReleasedWhenClosed = false
            hostWindow.center()

            let backgroundView = NSHostingView(rootView: FeedbackHostBackgroundView())
            hostWindow.contentView = backgroundView
            hostWindow.makeKeyAndOrderFront(nil)
            temporaryHostWindow = hostWindow

            DispatchQueue.main.async {
                FeedbackKit.presentAndSubmit(from: hostWindow) { _ in
                    hostWindow.close()
                    temporaryHostWindow = nil
                }
            }
        }
        #endif
    }
}

/// Fallback background canvas displayed inside a freshly created host window
/// when the user invokes the feedback shortcut while all other app windows were closed.
private struct FeedbackHostBackgroundView: View {
    var body: some View {
        ZStack {
            AppPageBackground()
            VStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("Voxbrief")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                Text("Feedback & Diagnostics")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 760, minHeight: 560)
    }
}
