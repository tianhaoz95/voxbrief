import AppKit
import CoreGraphics
import Foundation

public enum PasteInjectorError: LocalizedError {
    case notTrusted
    case eventCreationFailed

    public var errorDescription: String? {
        switch self {
        case .notTrusted:
            return "Voxbrief isn't trusted for Accessibility yet, so it can't paste into other apps."
        case .eventCreationFailed:
            return "Could not synthesize the paste keystroke."
        }
    }
}

/// Delivers the cleaned-up capture into whatever text field was focused when the capture started.
///
/// Uses the clipboard + a synthesized Cmd+V rather than the Accessibility API's direct
/// "set the focused element's value" call: the clipboard+paste path is what a human paste does,
/// so it works uniformly across native AppKit fields, Electron apps, and web text areas, several
/// of which don't implement AX value-setting correctly. The tradeoff is that it briefly touches
/// the system pasteboard -- this snapshots whatever was there beforehand and restores it right
/// after, so the user's actual clipboard contents survive a capture.
@MainActor
public final class PasteInjector {
    private static let virtualKeyV: CGKeyCode = 0x09

    public init() {}

    /// Copies `text` to the pasteboard, synthesizes Cmd+V, then restores whatever the pasteboard
    /// held before the capture. Throws without touching the pasteboard if not Accessibility-trusted.
    public func paste(_ text: String) async throws {
        guard AXIsProcessTrusted() else {
            throw PasteInjectorError.notTrusted
        }

        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        try synthesizePasteKeystroke()

        // Give the target app's paste handler time to actually read the pasteboard before it
        // gets restored out from under it.
        try? await Task.sleep(nanoseconds: 300_000_000)

        pasteboard.clearContents()
        if let previousString {
            pasteboard.setString(previousString, forType: .string)
        }
    }

    private func synthesizePasteKeystroke() throws {
        guard
            let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: Self.virtualKeyV, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: Self.virtualKeyV, keyDown: false)
        else {
            throw PasteInjectorError.eventCreationFailed
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
