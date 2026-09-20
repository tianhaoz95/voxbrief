import XCTest
@testable import Voxbrief

final class LLMCopywriterServiceTests: XCTestCase {
    
    var service: LLMCopywriterService!
    
    override func setUp() {
        super.setUp()
        service = LLMCopywriterService()
    }
    
    func testRequirementsConvertedToBulletPoints() async throws {
        let transcript = "So um we need to build an apple watch complication. Requirement is to support on-device speech recognition. Make sure to format requirements as bullets."
        
        let result = try await service.processTranscript(transcript)
        
        XCTAssertFalse(result.requirements.isEmpty, "Requirements should be extracted")
        XCTAssertTrue(result.cleanedMarkdown.contains("### 🎯 Requirements"), "Markdown should contain Requirements header")
        XCTAssertTrue(result.cleanedMarkdown.contains("- Build an Apple Watch complication") || result.cleanedMarkdown.contains("- Support on-device speech recognition"), "Requirements should be formatted with bullet points")
    }
    
    func testEnumeratedConditionsUseNumberedFormatting() async throws {
        let transcript = "First condition is if wifi is connected sync immediately. Second condition is if battery is low pause heavy background tasks. Finally notify user when complete."
        
        let result = try await service.processTranscript(transcript)
        
        XCTAssertFalse(result.conditions.isEmpty, "Conditions should be extracted")
        XCTAssertTrue(result.cleanedMarkdown.contains("### 🔢 Enumerated Conditions & Workflow"), "Markdown should contain Conditions header")
        XCTAssertTrue(result.cleanedMarkdown.contains("1. ") && result.cleanedMarkdown.contains("2. "), "Conditions should be numbered sequentially")
    }
    
    func testFillerRemovalAndGrammarFixes() async throws {
        let transcript = "um uh so basically we need to test the ios and watchos asr pipeline with the llm api."
        
        let result = try await service.processTranscript(transcript)
        
        XCTAssertFalse(result.cleanedMarkdown.contains(" um "), "Filler 'um' should be removed")
        XCTAssertFalse(result.cleanedMarkdown.contains(" uh "), "Filler 'uh' should be removed")
        XCTAssertTrue(result.cleanedMarkdown.contains("iOS"), "ios should be capitalized to iOS")
        XCTAssertTrue(result.cleanedMarkdown.contains("watchOS"), "watchos should be capitalized to watchOS")
        XCTAssertTrue(result.cleanedMarkdown.contains("ASR"), "asr should be capitalized to ASR")
        XCTAssertTrue(result.cleanedMarkdown.contains("LLM"), "llm should be capitalized to LLM")
        XCTAssertTrue(result.cleanedMarkdown.contains("API"), "api should be capitalized to API")
    }
    
    func testActionItemsChecklistExtraction() async throws {
        let transcript = "Todo remember to submit app review notes before Friday. Also assign to Sarah for QA."
        
        let result = try await service.processTranscript(transcript)
        
        XCTAssertFalse(result.actionItems.isEmpty, "Action items should be extracted")
        XCTAssertTrue(result.cleanedMarkdown.contains("- [ ]"), "Action items should use markdown task list syntax")
    }

    // MARK: - Light Rewrite Mode

    func testLightModeDoesNotRestructureIntoSections() async throws {
        let transcript = "First condition is if wifi is connected sync immediately. Requirement is to support on-device speech recognition. Todo remember to submit app review notes."

        let result = try await service.processTranscript(transcript, mode: .light)

        XCTAssertTrue(result.requirements.isEmpty, "Light mode should not extract requirements")
        XCTAssertTrue(result.conditions.isEmpty, "Light mode should not extract conditions")
        XCTAssertTrue(result.actionItems.isEmpty, "Light mode should not extract action items")
        XCTAssertFalse(result.cleanedMarkdown.contains("### 🎯 Requirements"), "Light mode markdown should have no section headers")
        XCTAssertFalse(result.cleanedMarkdown.contains("### 🔢 Enumerated Conditions & Workflow"), "Light mode markdown should have no section headers")
        XCTAssertFalse(result.cleanedMarkdown.contains("- [ ]"), "Light mode markdown should have no checklist formatting")
    }

    func testLightModeStillFixesTyposAndFillerWords() async throws {
        let transcript = "um uh so basically we need to test the ios and watchos asr pipeline with the llm api."

        let result = try await service.processTranscript(transcript, mode: .light)

        XCTAssertFalse(result.cleanedMarkdown.contains(" um "), "Filler 'um' should be removed")
        XCTAssertFalse(result.cleanedMarkdown.contains(" uh "), "Filler 'uh' should be removed")
        XCTAssertTrue(result.cleanedMarkdown.contains("iOS"), "ios should be capitalized to iOS")
        XCTAssertTrue(result.cleanedMarkdown.contains("watchOS"), "watchos should be capitalized to watchOS")
        XCTAssertTrue(result.cleanedMarkdown.contains("ASR"), "asr should be capitalized to ASR")
        XCTAssertTrue(result.cleanedMarkdown.contains("LLM"), "llm should be capitalized to LLM")
        XCTAssertTrue(result.cleanedMarkdown.contains("API"), "api should be capitalized to API")
    }

    func testLightModeRemovesWhisperSpecialTokens() async throws {
        let transcript = "Writing on board [ breathing heavily ] [ Laughter ] [ Inaudible Remark ] So, kind of, what are you doing?"

        let result = try await service.processTranscript(transcript, mode: .light)

        XCTAssertFalse(result.cleanedMarkdown.contains("["), "Bracketed ASR annotations should be stripped")
        XCTAssertFalse(result.cleanedMarkdown.contains("]"), "Bracketed ASR annotations should be stripped")
        XCTAssertFalse(result.cleanedMarkdown.contains("breathing heavily"), "Non-speech annotation content should be gone")
        XCTAssertFalse(result.cleanedMarkdown.contains("Laughter"), "Non-speech annotation content should be gone")
        XCTAssertFalse(result.cleanedMarkdown.contains("Inaudible"), "Non-speech annotation content should be gone")
        XCTAssertTrue(result.cleanedMarkdown.contains("Writing on board"), "Actual spoken content should be preserved")
        XCTAssertTrue(result.cleanedMarkdown.contains("what are you doing"), "Actual spoken content should be preserved")
    }

    func testLightModePreservesOriginalSentenceOrder() async throws {
        let transcript = "First we open the app. Then we tap record. Finally we review the transcript."

        let result = try await service.processTranscript(transcript, mode: .light)

        let openRange = result.cleanedMarkdown.range(of: "open the app")
        let tapRange = result.cleanedMarkdown.range(of: "tap record")
        let reviewRange = result.cleanedMarkdown.range(of: "review the transcript")

        XCTAssertNotNil(openRange, "Original wording should be preserved verbatim")
        XCTAssertNotNil(tapRange, "Original wording should be preserved verbatim")
        XCTAssertNotNil(reviewRange, "Original wording should be preserved verbatim")
        if let openRange, let tapRange, let reviewRange {
            XCTAssertTrue(openRange.lowerBound < tapRange.lowerBound, "Sentence order should be preserved")
            XCTAssertTrue(tapRange.lowerBound < reviewRange.lowerBound, "Sentence order should be preserved")
        }
    }

    func testFullModeUnaffectedByModeParameter() async throws {
        let transcript = "So um we need to build an apple watch complication. Requirement is to support on-device speech recognition."

        let result = try await service.processTranscript(transcript, mode: .full)

        XCTAssertFalse(result.requirements.isEmpty, "Explicit .full mode should still extract requirements")
        XCTAssertTrue(result.cleanedMarkdown.contains("### 🎯 Requirements"), "Explicit .full mode should still restructure into sections")
    }

    // MARK: - Personal Dictionary

    func testDictionaryInstructionBlockIsEmptyForNoEntries() {
        let block = service.dictionaryInstructionBlock([])

        XCTAssertEqual(block, "")
    }

    func testDictionaryInstructionBlockContainsEachTerm() {
        let dictionary = [
            DictionaryEntry(term: "Voxbrief"),
            DictionaryEntry(term: "Kubernetes")
        ]

        let block = service.dictionaryInstructionBlock(dictionary)

        XCTAssertTrue(block.contains("Voxbrief"))
        XCTAssertTrue(block.contains("Kubernetes"))
    }

    func testDictionaryInstructionBlockIncludesContextHintWhenPresent() {
        let dictionary = [
            DictionaryEntry(term: "Voxbrief", contextHint: "our project's codename"),
            DictionaryEntry(term: "Kubernetes")
        ]

        let block = service.dictionaryInstructionBlock(dictionary)

        XCTAssertTrue(block.contains("Voxbrief (our project's codename)"), "An entry with a hint should render as \"term (hint)\"")
        XCTAssertTrue(block.contains("Kubernetes"))
        XCTAssertFalse(block.contains("Kubernetes ("), "An entry with no hint should render as a bare term")
    }

    func testDictionaryInstructionBlockTrimsWhitespaceOnlyHint() {
        let dictionary = [DictionaryEntry(term: "Voxbrief", contextHint: "   ")]

        let block = service.dictionaryInstructionBlock(dictionary)

        XCTAssertFalse(block.contains("Voxbrief ("), "A whitespace-only hint should be treated as no hint")
    }

    func testDictionaryInstructionBlockRespectsTermCap() {
        let dictionary = (1...(LLMCopywriterService.maxDictionaryTermsInPrompt + 10)).map {
            DictionaryEntry(term: "Term\($0)")
        }

        let block = service.dictionaryInstructionBlock(dictionary)

        XCTAssertTrue(block.contains("Term1"))
        XCTAssertFalse(block.contains("Term\(LLMCopywriterService.maxDictionaryTermsInPrompt + 10)"), "Terms beyond the cap should not appear")
    }

    func testProcessTranscriptDefaultsToNoDictionary() async throws {
        // Existing call sites (no dictionary argument) must keep compiling and behaving as before.
        let result = try await service.processTranscript("We need to build the auth flow.")

        XCTAssertFalse(result.requirements.isEmpty)
    }
}
