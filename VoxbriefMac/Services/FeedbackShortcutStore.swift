import AppKit
import Foundation

/// Manages persistence, preset selection, and interactive key recording
/// for the feedback shortcut setting on macOS.
@MainActor
public final class FeedbackShortcutStore: ObservableObject {
    public static let shared = FeedbackShortcutStore()

    public static let storageKey = "feedback_shortcut_config"

    @Published public var currentShortcut: FeedbackShortcut {
        didSet {
            save()
        }
    }

    @Published public var isRecording: Bool = false

    private var recordingMonitor: Any?
    private var localAppMonitor: Any?

    public init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(FeedbackShortcut.self, from: data) {
            self.currentShortcut = decoded
        } else {
            self.currentShortcut = .defaultShortcut
        }
    }

    /// Presets index matching `currentShortcut`, or `-1` if it is a custom combination.
    public var selectedPresetIndex: Int {
        get {
            for (index, preset) in FeedbackShortcut.presets.enumerated() {
                if preset.shortcut.keyCode == currentShortcut.keyCode &&
                    preset.shortcut.command == currentShortcut.command &&
                    preset.shortcut.option == currentShortcut.option &&
                    preset.shortcut.control == currentShortcut.control &&
                    preset.shortcut.shift == currentShortcut.shift {
                    return index
                }
            }
            return -1
        }
        set {
            guard newValue >= 0, newValue < FeedbackShortcut.presets.count else { return }
            var updated = FeedbackShortcut.presets[newValue].shortcut
            updated.isEnabled = currentShortcut.isEnabled
            currentShortcut = updated
        }
    }

    public var isCustomShortcut: Bool {
        selectedPresetIndex == -1
    }

    public func resetToDefault() {
        cancelRecording()
        currentShortcut = .defaultShortcut
    }

    public func toggleRecording() {
        if isRecording {
            cancelRecording()
        } else {
            startRecording()
        }
    }

    public func startRecording() {
        isRecording = true
        if let monitor = recordingMonitor {
            NSEvent.removeMonitor(monitor)
            recordingMonitor = nil
        }

        recordingMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }

            // Escape without modifiers cancels recording
            let rawModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            if event.keyCode == 0x35 && rawModifiers.isEmpty {
                self.cancelRecording()
                return nil
            }

            let hasCmd = rawModifiers.contains(.command)
            let hasOpt = rawModifiers.contains(.option)
            let hasCtrl = rawModifiers.contains(.control)
            let hasShift = rawModifiers.contains(.shift)

            let isFunctionKey = (event.keyCode >= 0x7A && event.keyCode <= 0x78) ||
                (event.keyCode >= 0x60 && event.keyCode <= 0x67) ||
                (event.keyCode >= 0x6D && event.keyCode <= 0x6F) ||
                event.keyCode == 0x63 || event.keyCode == 0x76

            // Require at least one modifier key or a dedicated function key
            guard hasCmd || hasOpt || hasCtrl || hasShift || isFunctionKey else {
                return nil
            }

            let label = Self.displayName(for: event)
            self.currentShortcut = FeedbackShortcut(
                isEnabled: true,
                keyCode: event.keyCode,
                keyDisplay: label,
                command: hasCmd,
                option: hasOpt,
                control: hasCtrl,
                shift: hasShift
            )
            self.cancelRecording()
            return nil
        }
    }

    public func cancelRecording() {
        isRecording = false
        if let monitor = recordingMonitor {
            NSEvent.removeMonitor(monitor)
            recordingMonitor = nil
        }
    }

    /// Installs a local key monitor so that whenever Voxbrief has focus,
    /// pressing the shortcut triggers the feedback page and suppresses the key event.
    public func startLocalMonitor(onTrigger: @escaping () -> Void) {
        guard localAppMonitor == nil else { return }
        localAppMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            guard !self.isRecording else { return event }

            if self.currentShortcut.matches(nsEvent: event) {
                onTrigger()
                return nil
            }
            return event
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(currentShortcut) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    /// Produces a human-friendly representation for a key event's primary glyph.
    public static func displayName(for event: NSEvent) -> String {
        switch event.keyCode {
        case 0x24: return "Return"
        case 0x30: return "Tab"
        case 0x31: return "Space"
        case 0x33: return "Delete"
        case 0x35: return "Esc"
        case 0x7E: return "↑"
        case 0x7D: return "↓"
        case 0x7B: return "←"
        case 0x7C: return "→"
        case 0x7A: return "F1"
        case 0x78: return "F2"
        case 0x63: return "F3"
        case 0x76: return "F4"
        case 0x60: return "F5"
        case 0x61: return "F6"
        case 0x62: return "F7"
        case 0x64: return "F8"
        case 0x65: return "F9"
        case 0x6D: return "F10"
        case 0x67: return "F11"
        case 0x6F: return "F12"
        default:
            if let chars = event.charactersIgnoringModifiers, !chars.isEmpty {
                return chars.uppercased()
            }
            return String(format: "0x%02X", event.keyCode)
        }
    }
}
