import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Cross-platform semantic colors for the SwiftUI views shared between the iOS app and
/// `VoxbriefMac` (see `NoteDetailView`, `PersonalDictionaryView`, etc.) so their body code doesn't
/// need per-platform branches sprinkled through it just to pick a system background shade.
extension Color {
    static var appGroupedBackground: Color {
        #if os(iOS)
        Color(UIColor.systemGroupedBackground)
        #elseif os(macOS)
        Color(NSColor.windowBackgroundColor)
        #endif
    }

    static var appSecondaryBackground: Color {
        #if os(iOS)
        Color(UIColor.secondarySystemBackground)
        #elseif os(macOS)
        Color(NSColor.controlBackgroundColor)
        #endif
    }

    static var appTertiaryFill: Color {
        #if os(iOS)
        Color(UIColor.tertiarySystemFill)
        #elseif os(macOS)
        Color(NSColor.quaternaryLabelColor).opacity(0.3)
        #endif
    }
}

#if os(macOS)
/// Wraps `NSVisualEffectView` configured with the exact same `.sidebar` material
/// `NavigationSplitView`/`List(.sidebar)` use for the Mac app's sidebar column, so other surfaces
/// can match it pixel-for-pixel instead of approximating it with a flat `NSColor` -- sidebar
/// vibrancy blends with whatever's behind the window, so a flat color only ever looks right under
/// one specific appearance/wallpaper combination.
private struct SidebarMaterialView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
#endif

/// Page-level background for the shared iOS/macOS note views -- plain grouped background on iOS,
/// the same vibrancy material as `VoxbriefMac`'s sidebar on macOS, so `NotesBrowserView`'s
/// `NavigationSplitView` reads as one continuous surface instead of two visibly different grays
/// between the sidebar and the detail pane.
struct AppPageBackground: View {
    var body: some View {
        #if os(iOS)
        Color.appGroupedBackground
        #elseif os(macOS)
        SidebarMaterialView()
        #endif
    }
}

/// Cross-platform "copy this string to the system pasteboard."
enum PlatformPasteboard {
    static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

#if canImport(FeedbackKit)
import FeedbackKit

public enum FeedbackSettings {
    public static let shakeEnabledKey = "feedback_shake_enabled"

    public static var isShakeEnabled: Bool {
        get { UserDefaults.standard.object(forKey: shakeEnabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: shakeEnabledKey)
        }
    }

    public static func setupTriggers() {
        #if os(iOS)
        FeedbackKit.enableShakeToReport {
            guard isShakeEnabled else { return nil }
            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }?
                .rootViewController
        }
        #endif
    }
}

public struct FeedbackScreenModifier: ViewModifier {
    let screenName: String

    public func body(content: Content) -> some View {
        content.onAppear {
            FeedbackKit.currentScreen = screenName
        }
    }
}

extension View {
    public func trackFeedbackScreen(_ name: String) -> some View {
        modifier(FeedbackScreenModifier(screenName: name))
    }
}
#else
public enum FeedbackSettings {
    public static let shakeEnabledKey = "feedback_shake_enabled"
}

extension View {
    public func trackFeedbackScreen(_ name: String) -> some View {
        self
    }
}
#endif
