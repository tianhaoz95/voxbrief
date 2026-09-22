import XCTest
@testable import Voxbrief

/// Covers only `ASRService`'s pure static helpers -- `vocabularyPromptText` needs no live
/// WhisperKit model load, unlike a full `transcribeAudio` integration test.
final class ASRServiceHelpersTests: XCTestCase {

    func testEmptyVocabularyReturnsNil() {
        XCTAssertNil(ASRService.vocabularyPromptText(from: []))
    }

    func testWhitespaceOnlyEntriesAreFilteredOut() {
        XCTAssertNil(ASRService.vocabularyPromptText(from: ["", "   ", "\n"]))
    }

    func testTermsAreJoinedWithCommaSpace() {
        let result = ASRService.vocabularyPromptText(from: ["Voxbrief", "Kubernetes"])

        XCTAssertEqual(result, "Voxbrief, Kubernetes")
    }

    func testTermsAreTrimmed() {
        let result = ASRService.vocabularyPromptText(from: ["  Voxbrief  ", " Kubernetes"])

        XCTAssertEqual(result, "Voxbrief, Kubernetes")
    }

    func testCapEnforcedOnFirstNTerms() {
        let terms = (1...10).map { "Term\($0)" }

        let result = ASRService.vocabularyPromptText(from: terms, maxTerms: 3)

        XCTAssertEqual(result, "Term1, Term2, Term3")
    }

    // MARK: - ASRProgressTracker Tests

    func testProgressTrackerSingleWindowIncrementalUpdates() {
        var emissions: [String] = []
        let tracker = ASRProgressTracker { text in
            emissions.append(text)
        }

        let first = tracker.update(windowId: 0, text: "Hello")
        XCTAssertEqual(first, "Hello")

        let second = tracker.update(windowId: 0, text: "Hello world")
        XCTAssertEqual(second, "Hello world")

        XCTAssertEqual(emissions, ["Hello", "Hello world"])
    }

    func testProgressTrackerMultiWindowTransitions() {
        var emissions: [String] = []
        let tracker = ASRProgressTracker { text in
            emissions.append(text)
        }

        _ = tracker.update(windowId: 0, text: "This is window zero.")
        _ = tracker.update(windowId: 1, text: "And this is window one.")
        let final = tracker.update(windowId: 1, text: "And this is window one completed.")

        XCTAssertEqual(final, "This is window zero. And this is window one completed.")
        XCTAssertEqual(emissions.last, "This is window zero. And this is window one completed.")
    }

    func testProgressTrackerWhitespaceAndEmptyHandling() {
        var emissions: [String] = []
        let tracker = ASRProgressTracker { text in
            emissions.append(text)
        }

        let empty = tracker.update(windowId: 0, text: "    ")
        XCTAssertEqual(empty, "")
        XCTAssertTrue(emissions.isEmpty)

        let trimmed = tracker.update(windowId: 0, text: "   Speech detected   ")
        XCTAssertEqual(trimmed, "Speech detected")
        XCTAssertEqual(emissions, ["Speech detected"])
    }

    func testProgressTrackerMakeCallbackNilWhenNoHandler() {
        let passiveTracker = ASRProgressTracker(onProgress: nil)
        XCTAssertNil(passiveTracker.makeCallback())

        let activeTracker = ASRProgressTracker(onProgress: { _ in })
        XCTAssertNotNil(activeTracker.makeCallback())
    }
}
