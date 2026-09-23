import XCTest
@testable import Voxbrief

final class FormattingExtensionsTests: XCTestCase {
    func testTimeIntervalFormattedDuration() {
        let durationZero: TimeInterval = 0
        XCTAssertEqual(durationZero.formattedDuration, "00:00")

        let durationSeconds: TimeInterval = 45
        XCTAssertEqual(durationSeconds.formattedDuration, "00:45")

        let durationMinutes: TimeInterval = 125
        XCTAssertEqual(durationMinutes.formattedDuration, "02:05")
    }

    func testDateRelativeOrFormattedString() {
        let now = Date()
        XCTAssertTrue(now.relativeOrFormattedString.hasPrefix("Today, "))

        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        XCTAssertTrue(yesterday.relativeOrFormattedString.hasPrefix("Yesterday, "))
    }

    func testDateFullFormattedString() {
        let now = Date()
        let full = now.fullFormattedString
        XCTAssertFalse(full.isEmpty)

        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .short
        XCTAssertEqual(full, formatter.string(from: now))
    }
}
