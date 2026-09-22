import AppKit
import CoreGraphics
import Foundation

/// Represents a configurable keyboard shortcut to open the feedback submission page on macOS.
public struct FeedbackShortcut: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var keyCode: UInt16
    public var keyDisplay: String
    public var command: Bool
    public var option: Bool
    public var control: Bool
    public var shift: Bool

    public init(
        isEnabled: Bool = true,
        keyCode: UInt16 = 0x03, // 'F'
        keyDisplay: String = "F",
        command: Bool = true,
        option: Bool = true,
        control: Bool = true,
        shift: Bool = false
    ) {
        self.isEnabled = isEnabled
        self.keyCode = keyCode
        self.keyDisplay = keyDisplay
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
    }

    /// Human-readable glyph string conforming to macOS Human Interface Guidelines
    /// modifier symbol ordering: Control (⌃), Option (⌥), Shift (⇧), Command (⌘).
    public var displayString: String {
        guard isEnabled else { return "Disabled" }
        var result = ""
        if control { result += "⌃" }
        if option { result += "⌥" }
        if shift { result += "⇧" }
        if command { result += "⌘" }
        result += keyDisplay
        return result
    }

    /// Checks if a generic keycode and modifier flags match this shortcut configuration.
    public func matches(
        keyCode: UInt16,
        command: Bool,
        option: Bool,
        control: Bool,
        shift: Bool
    ) -> Bool {
        guard isEnabled else { return false }
        guard self.keyCode == keyCode else { return false }
        return self.command == command &&
            self.option == option &&
            self.control == control &&
            self.shift == shift
    }

    /// Checks whether a low-level `CGEvent` (from `CGEventTap`) matches this shortcut.
    public func matches(cgEvent: CGEvent) -> Bool {
        let eventCode = UInt16(cgEvent.getIntegerValueField(.keyboardEventKeycode))
        let flags = cgEvent.flags
        return matches(
            keyCode: eventCode,
            command: flags.contains(.maskCommand),
            option: flags.contains(.maskAlternate),
            control: flags.contains(.maskControl),
            shift: flags.contains(.maskShift)
        )
    }

    /// Checks whether an AppKit `NSEvent` (from local event monitors) matches this shortcut.
    public func matches(nsEvent: NSEvent) -> Bool {
        let flags = nsEvent.modifierFlags.intersection([.command, .option, .control, .shift])
        return matches(
            keyCode: nsEvent.keyCode,
            command: flags.contains(.command),
            option: flags.contains(.option),
            control: flags.contains(.control),
            shift: flags.contains(.shift)
        )
    }

    /// The default feedback shortcut: ⌃⌥⌘F.
    public static let defaultShortcut = FeedbackShortcut(
        isEnabled: true,
        keyCode: 0x03, // F
        keyDisplay: "F",
        command: true,
        option: true,
        control: true,
        shift: false
    )

    /// Curated presets for quick selection in Settings.
    public static let presets: [(name: String, shortcut: FeedbackShortcut)] = [
        ("⌃⌥⌘F (Control + Option + Command + F)", FeedbackShortcut(isEnabled: true, keyCode: 0x03, keyDisplay: "F", command: true, option: true, control: true, shift: false)),
        ("⌥⇧F (Option + Shift + F)", FeedbackShortcut(isEnabled: true, keyCode: 0x03, keyDisplay: "F", command: false, option: true, control: false, shift: true)),
        ("⌘⇧F (Command + Shift + F)", FeedbackShortcut(isEnabled: true, keyCode: 0x03, keyDisplay: "F", command: true, option: false, control: false, shift: true)),
        ("⌘⌥F (Command + Option + F)", FeedbackShortcut(isEnabled: true, keyCode: 0x03, keyDisplay: "F", command: true, option: true, control: false, shift: false)),
        ("⌃⌥F (Control + Option + F)", FeedbackShortcut(isEnabled: true, keyCode: 0x03, keyDisplay: "F", command: false, option: true, control: true, shift: false)),
    ]
}
