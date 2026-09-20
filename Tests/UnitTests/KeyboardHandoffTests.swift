import XCTest
@testable import Voxbrief

final class KeyboardHandoffTests: XCTestCase {

    override func tearDown() {
        // Leave no pending payload behind for other tests/runs sharing the same App Group suite.
        _ = KeyboardHandoff.consumePendingPaste()
        super.tearDown()
    }

    func testConsumePendingPasteReturnsNilWhenNothingIsPending() {
        XCTAssertNil(KeyboardHandoff.consumePendingPaste(), "Should start with nothing pending")
    }

    func testSetThenConsumeRoundTrips() {
        KeyboardHandoff.setPendingPaste("Hello from Voxbrief")

        XCTAssertEqual(KeyboardHandoff.consumePendingPaste(), "Hello from Voxbrief")
    }

    func testConsumeClearsThePendingValueSoItIsOnlyDeliveredOnce() {
        KeyboardHandoff.setPendingPaste("Only once")

        XCTAssertEqual(KeyboardHandoff.consumePendingPaste(), "Only once")
        XCTAssertNil(KeyboardHandoff.consumePendingPaste(), "A second consume should find nothing left")
    }

    func testSettingANewValueOverwritesAnyPreviousPendingValue() {
        KeyboardHandoff.setPendingPaste("First")
        KeyboardHandoff.setPendingPaste("Second")

        XCTAssertEqual(KeyboardHandoff.consumePendingPaste(), "Second")
    }
}
