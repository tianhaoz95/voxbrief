import ApplicationServices
import CoreGraphics
import Foundation

/// Detects the "press both Command keys" gesture system-wide, regardless of which app currently
/// has focus, via a low-level `CGEventTap`. This is the default (and today, only) trigger for
/// starting a capture -- see `CaptureCoordinator`.
///
/// A `CGEventTap` (rather than `NSEvent.addGlobalMonitorForEvents`) is used because it's the
/// mechanism every real system-wide hotkey tool relies on, and it's exactly what Accessibility
/// trust gates: `start()` is a no-op until `AXIsProcessTrusted()` is true.
///
/// Left/right Command key state is read from the CGEvent flags' device-dependent bits (the
/// `NX_DEVICELCMDKEYMASK` / `NX_DEVICERCMDKEYMASK` values from the private `IOLLEvent.h` header --
/// undocumented but stable and widely relied on by other open-source hotkey tools, since the
/// public `CGEventFlags.maskCommand` bit alone can't tell left and right Command apart). This
/// needs verification on real hardware since it can't be exercised in a headless environment.
@MainActor
public final class GlobalHotkeyManager {
    // Carbon's kVK_Command / kVK_RightCommand -- hardcoded to avoid importing the Carbon module
    // for two integer constants.
    private static let leftCommandKeyCode: Int64 = 0x37
    private static let rightCommandKeyCode: Int64 = 0x36

    // NX_DEVICELCMDKEYMASK / NX_DEVICERCMDKEYMASK.
    private static let leftCommandDeviceFlag = CGEventFlags(rawValue: 0x0000_0008)
    private static let rightCommandDeviceFlag = CGEventFlags(rawValue: 0x0000_0010)

    public var onBothCommandKeysPressed: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var leftHeld = false
    private var rightHeld = false
    private var hasFiredForCurrentHold = false

    public init() {}

    deinit {
        // `stop()` touches main-actor state via CF APIs that are themselves not actor-isolated;
        // tearing down here best-effort mirrors `stop()` without needing actor hops in deinit.
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
    }

    public var isRunning: Bool { eventTap != nil }

    /// Installs the event tap. Requires Accessibility trust -- call after
    /// `AccessibilityPermissionManager.isTrusted` is true; returns `false` otherwise.
    @discardableResult
    public func start() -> Bool {
        guard eventTap == nil else { return true }
        guard AXIsProcessTrusted() else { return false }

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<GlobalHotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                MainActor.assumeIsolated {
                    manager.handle(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPointer
        ) else {
            return false
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    public func stop() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        leftHeld = false
        rightHeld = false
        hasFiredForCurrentHold = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // A disabled tap (e.g. the system suspending it under load) must be re-enabled or global
        // hotkey detection silently stops working until the app relaunches.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }
        guard type == .flagsChanged else { return }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == Self.leftCommandKeyCode || keyCode == Self.rightCommandKeyCode else { return }

        let flags = event.flags
        leftHeld = flags.contains(Self.leftCommandDeviceFlag)
        rightHeld = flags.contains(Self.rightCommandDeviceFlag)

        if !leftHeld && !rightHeld {
            hasFiredForCurrentHold = false
            return
        }

        if !hasFiredForCurrentHold && leftHeld && rightHeld {
            hasFiredForCurrentHold = true
            onBothCommandKeysPressed?()
        }
    }
}
