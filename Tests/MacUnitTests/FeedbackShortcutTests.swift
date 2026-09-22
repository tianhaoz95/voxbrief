import XCTest
@testable import VoxbriefMac

final class FeedbackShortcutTests: XCTestCase {
    func testDefaultShortcut() {
        let shortcut = FeedbackShortcut.defaultShortcut
        XCTAssertTrue(shortcut.isEnabled)
        XCTAssertEqual(shortcut.keyCode, 0x03)
        XCTAssertEqual(shortcut.keyDisplay, "F")
        XCTAssertTrue(shortcut.command)
        XCTAssertTrue(shortcut.option)
        XCTAssertTrue(shortcut.control)
        XCTAssertFalse(shortcut.shift)
        XCTAssertEqual(shortcut.displayString, "⌃⌥⌘F")
    }

    func testDisplayStringOrdering() {
        let shortcut = FeedbackShortcut(
            isEnabled: true,
            keyCode: 0x03,
            keyDisplay: "F",
            command: true,
            option: false,
            control: false,
            shift: true
        )
        XCTAssertEqual(shortcut.displayString, "⇧⌘F")

        let disabled = FeedbackShortcut(isEnabled: false)
        XCTAssertEqual(disabled.displayString, "Disabled")
    }

    func testCodableRoundTrip() throws {
        let original = FeedbackShortcut(
            isEnabled: true,
            keyCode: 0x0B, // B
            keyDisplay: "B",
            command: false,
            option: true,
            control: true,
            shift: true
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(FeedbackShortcut.self, from: data)
        XCTAssertEqual(original, decoded)
        XCTAssertEqual(decoded.displayString, "⌃⌥⇧B")
    }

    func testMatchesManualFlags() {
        let shortcut = FeedbackShortcut.defaultShortcut
        XCTAssertTrue(
            shortcut.matches(
                keyCode: 0x03,
                command: true,
                option: true,
                control: true,
                shift: false
            )
        )
        // Wrong keycode
        XCTAssertFalse(
            shortcut.matches(
                keyCode: 0x00,
                command: true,
                option: true,
                control: true,
                shift: false
            )
        )
        // Missing control
        XCTAssertFalse(
            shortcut.matches(
                keyCode: 0x03,
                command: true,
                option: true,
                control: false,
                shift: false
            )
        )
    }

    func testDisabledShortcutDoesNotMatch() {
        var shortcut = FeedbackShortcut.defaultShortcut
        shortcut.isEnabled = false
        XCTAssertFalse(
            shortcut.matches(
                keyCode: 0x03,
                command: true,
                option: true,
                control: true,
                shift: false
            )
        )
    }

    @MainActor
    func testStorePresets() {
        let store = FeedbackShortcutStore.shared
        store.resetToDefault()
        XCTAssertEqual(store.currentShortcut, FeedbackShortcut.defaultShortcut)
        XCTAssertEqual(store.selectedPresetIndex, 0)
        XCTAssertFalse(store.isCustomShortcut)

        // Select preset 2: ⌘⇧F
        store.selectedPresetIndex = 2
        XCTAssertEqual(store.currentShortcut.displayString, "⇧⌘F")
        XCTAssertEqual(store.selectedPresetIndex, 2)
        XCTAssertFalse(store.isCustomShortcut)

        // Set custom
        store.currentShortcut = FeedbackShortcut(
            isEnabled: true,
            keyCode: 0x0B,
            keyDisplay: "B",
            command: true,
            option: true,
            control: false,
            shift: false
        )
        XCTAssertTrue(store.isCustomShortcut)
        XCTAssertEqual(store.selectedPresetIndex, -1)
        XCTAssertEqual(store.currentShortcut.displayString, "⌥⌘B")

        // Reset
        store.resetToDefault()
        XCTAssertEqual(store.currentShortcut, FeedbackShortcut.defaultShortcut)
    }
}
