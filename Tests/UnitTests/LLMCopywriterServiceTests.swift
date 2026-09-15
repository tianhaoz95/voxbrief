import XCTest
@testable import VoiceNote

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
}
