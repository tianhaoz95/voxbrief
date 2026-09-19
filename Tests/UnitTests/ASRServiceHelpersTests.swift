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
}
