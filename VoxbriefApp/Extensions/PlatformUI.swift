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
