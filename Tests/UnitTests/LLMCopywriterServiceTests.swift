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

    // MARK: - Cold-load warm-up

    func testWarmUpCompletesWithoutThrowing() async {
        // On the Simulator (where this test runs), OnDeviceLLMService.isSupportedOnThisDevice is
        // false, so this exercises the "safe no-op" path -- the real on-device warm-up path is
        // exercised on-device only, same as generate() itself (see CLAUDE.md).
        await service.warmUp()
    }

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

    // MARK: - Multi-template classification & generation
    //
    // `processTranscript` never reaches `processWithOnDeviceLLMFull` itself on the Simulator
    // (where these tests run) -- OnDeviceLLMService.isSupportedOnThisDevice is false there, so
    // every test above actually exercises the rule-based fallback. These helpers are tested
    // directly instead, as small, pure, data-in/data-out functions independent of
    // OnDeviceLLMService.shared.generate -- the same reasoning dictionaryInstructionBlock's own
    // `internal` visibility already established.

    func testResolveTemplateExactNameMatch() {
        let raw = "{\"template\": \"Email\"}"
        let resolved = service.resolveTemplate(fromClassificationRaw: raw, candidates: NoteTemplate.builtIns, fallback: NoteTemplate.generalNotes)

        XCTAssertEqual(resolved.id, NoteTemplate.email.id)
    }

    func testResolveTemplateCaseInsensitiveMatch() {
        let raw = "{\"template\": \"short tweet\"}"
        let resolved = service.resolveTemplate(fromClassificationRaw: raw, candidates: NoteTemplate.builtIns, fallback: NoteTemplate.generalNotes)

        XCTAssertEqual(resolved.id, NoteTemplate.shortTweet.id)
    }

    func testResolveTemplateFallsBackOnUnknownName() {
        let raw = "{\"template\": \"Something Made Up\"}"
        let resolved = service.resolveTemplate(fromClassificationRaw: raw, candidates: NoteTemplate.builtIns, fallback: NoteTemplate.generalNotes)

        XCTAssertEqual(resolved.id, NoteTemplate.generalNotes.id)
    }

    func testResolveTemplateFallsBackOnUnparsableResponse() {
        let raw = "not json at all"
        let resolved = service.resolveTemplate(fromClassificationRaw: raw, candidates: NoteTemplate.builtIns, fallback: NoteTemplate.generalNotes)

        XCTAssertEqual(resolved.id, NoteTemplate.generalNotes.id)
    }

    func testEffectiveFallbackTemplatePrefersGeneralNotesWhenPresent() {
        let fallback = service.effectiveFallbackTemplate(in: NoteTemplate.builtIns)

        XCTAssertEqual(fallback.id, NoteTemplate.generalNotes.id)
    }

    /// Simulates the user disabling General Notes via `TemplateStore.setEnabled` -- the effective
    /// fallback must not silently resurrect a template the user turned off.
    func testEffectiveFallbackTemplateUsesFirstTemplateWhenGeneralNotesExcluded() {
        let subset = [NoteTemplate.email, NoteTemplate.shortTweet]
        let fallback = service.effectiveFallbackTemplate(in: subset)

        XCTAssertEqual(fallback.id, NoteTemplate.email.id)
    }

    func testEffectiveFallbackTemplateFallsBackToGlobalDefaultForEmptyList() {
        let fallback = service.effectiveFallbackTemplate(in: [])

        XCTAssertEqual(fallback.id, NoteTemplate.fallbackDefault.id)
    }

    func testResolveTemplateRespectsExplicitFallbackOverGeneralNotes() {
        // Even when the raw response is unparsable, resolveTemplate must use whatever `fallback`
        // it's given -- not silently prefer General Notes -- since this is how a disabled General
        // Notes template stays excluded end-to-end.
        let raw = "not json at all"
        let resolved = service.resolveTemplate(fromClassificationRaw: raw, candidates: [NoteTemplate.email, NoteTemplate.shortTweet], fallback: NoteTemplate.email)

        XCTAssertEqual(resolved.id, NoteTemplate.email.id)
    }

    func testBuildClassificationSystemPromptListsEveryTemplate() {
        let prompt = service.buildClassificationSystemPrompt(templates: NoteTemplate.builtIns)

        for template in NoteTemplate.builtIns {
            XCTAssertTrue(prompt.contains(template.name), "Prompt should list \(template.name)")
            XCTAssertTrue(prompt.contains(template.summary), "Prompt should list \(template.name)'s summary")
        }
    }

    func testBuildGenerationSystemPromptContainsSectionFieldKeysAndInstructions() {
        let prompt = service.buildGenerationSystemPrompt(template: NoteTemplate.email, dictionary: [])

        XCTAssertTrue(prompt.contains("\"subject\""))
        XCTAssertTrue(prompt.contains("\"body\""))
        XCTAssertTrue(prompt.contains(NoteTemplate.email.sections[0].instructions))
    }

    func testBuildGenerationSystemPromptIncludesDictionaryBlockWhenNonEmpty() {
        let dictionary = [DictionaryEntry(term: "Voxbrief")]
        let prompt = service.buildGenerationSystemPrompt(template: NoteTemplate.generalNotes, dictionary: dictionary)

        XCTAssertTrue(prompt.contains("Voxbrief"))
    }

    func testParseGenerationResponseExtractsArraySections() throws {
        let raw = """
        {"title": "Ship the feature", "summary": "A quick update", "requirements": ["Ship it"], "conditions": [], "actionItems": [], "tags": ["#Tasks"]}
        """
        let parsed = try service.parseGenerationResponse(raw, template: NoteTemplate.designDoc)

        XCTAssertEqual(parsed.title, "Ship the feature")
        XCTAssertEqual(parsed.summary, "A quick update")
        XCTAssertEqual(parsed.tags, ["#Tasks"])
        XCTAssertEqual(parsed.sections.first(where: { $0.title == NoteTemplate.designDoc.sections[0].title })?.items, ["Ship it"])
    }

    func testParseGenerationResponseAcceptsBareStringForParagraphSection() throws {
        let raw = """
        {"title": "Quick note", "summary": "A quick note", "notes": "Just a single paragraph of prose.", "tags": []}
        """
        let parsed = try service.parseGenerationResponse(raw, template: NoteTemplate.generalNotes)

        XCTAssertEqual(parsed.sections.first?.items, ["Just a single paragraph of prose."])
    }

    func testParseGenerationResponseDefaultsMissingSectionToEmpty() throws {
        let raw = """
        {"title": "Quick note", "summary": "A quick note", "tags": []}
        """
        let parsed = try service.parseGenerationResponse(raw, template: NoteTemplate.generalNotes)

        XCTAssertEqual(parsed.sections.first?.items, [])
    }

    func testParseGenerationResponseThrowsOnUnparsableText() {
        XCTAssertThrowsError(try service.parseGenerationResponse("not json at all", template: NoteTemplate.generalNotes))
    }

    func testAssembleMarkdownRendersEachSectionStyleCorrectly() {
        let sections = [
            TemplateSectionContent(title: "Bullets", style: .bullet, items: ["One", "Two"]),
            TemplateSectionContent(title: "Numbers", style: .numbered, items: ["One", "Two"]),
            TemplateSectionContent(title: "Checks", style: .checklist, items: ["One"]),
            TemplateSectionContent(title: "Prose", style: .paragraph, items: ["One sentence."])
        ]
        let markdown = service.assembleMarkdown(title: "Title", summary: "Summary", sections: sections)

        XCTAssertTrue(markdown.contains("- One\n- Two"))
        XCTAssertTrue(markdown.contains("1. One\n2. Two"))
        XCTAssertTrue(markdown.contains("- [ ] One"))
        XCTAssertTrue(markdown.contains("One sentence."))
    }

    /// Regression pin: a Design-Doc-shaped `sections` array must still produce byte-identical
    /// markdown to what the old fixed three-block `assembleMarkdown` produced.
    func testAssembleMarkdownDesignDocShapeMatchesOriginalFormat() {
        let sections = [
            TemplateSectionContent(title: NoteTemplate.designDoc.sections[0].title, style: .bullet, items: ["Ship it"]),
            TemplateSectionContent(title: NoteTemplate.designDoc.sections[1].title, style: .numbered, items: ["If X then Y"]),
            TemplateSectionContent(title: NoteTemplate.designDoc.sections[2].title, style: .checklist, items: ["Follow up"])
        ]
        let markdown = service.assembleMarkdown(title: "Title", summary: "Summary", sections: sections)

        XCTAssertTrue(markdown.contains("### 🎯 Requirements\n- Ship it"))
        XCTAssertTrue(markdown.contains("### 🔢 Enumerated Conditions & Workflow\n1. If X then Y"))
        XCTAssertTrue(markdown.contains("### ✅ Action Items\n- [ ] Follow up"))
    }

    func testLegacyFieldsDerivesArraysFromDesignDocSections() {
        let sections = [
            TemplateSectionContent(title: NoteTemplate.designDoc.sections[0].title, style: .bullet, items: ["Req A"]),
            TemplateSectionContent(title: NoteTemplate.designDoc.sections[1].title, style: .numbered, items: ["Cond A"]),
            TemplateSectionContent(title: NoteTemplate.designDoc.sections[2].title, style: .checklist, items: ["Action A"])
        ]
        let (requirements, conditions, actionItems) = LLMCopywriterService.legacyFields(from: sections)

        XCTAssertEqual(requirements, ["Req A"])
        XCTAssertEqual(conditions, ["Cond A"])
        XCTAssertEqual(actionItems, ["Action A"])
    }

    func testLegacyFieldsEmptyForNonDesignDocSections() {
        let sections = [TemplateSectionContent(title: "Body", style: .paragraph, items: ["Some email body."])]
        let (requirements, conditions, actionItems) = LLMCopywriterService.legacyFields(from: sections)

        XCTAssertEqual(requirements, [])
        XCTAssertEqual(conditions, [])
        XCTAssertEqual(actionItems, [])
    }

    // MARK: - LLM Model Switching & Selection Tests

    func testConfiguredLocalLLMModelNameDefaultsToLlama() {
        let prev = UserDefaults.standard.object(forKey: LLMCopywriterService.localLLMModelNameKey)
        UserDefaults.standard.removeObject(forKey: LLMCopywriterService.localLLMModelNameKey)
        defer {
            if let prev { UserDefaults.standard.set(prev, forKey: LLMCopywriterService.localLLMModelNameKey) }
            else { UserDefaults.standard.removeObject(forKey: LLMCopywriterService.localLLMModelNameKey) }
        }

        XCTAssertEqual(LLMCopywriterService.configuredLocalLLMModelName(), "llama3.2:1b")
    }

    func testConfiguredLocalLLMModelNameReadsCustomSetting() {
        let prev = UserDefaults.standard.object(forKey: LLMCopywriterService.localLLMModelNameKey)
        UserDefaults.standard.set("qwen2.5:7b", forKey: LLMCopywriterService.localLLMModelNameKey)
        defer {
            if let prev { UserDefaults.standard.set(prev, forKey: LLMCopywriterService.localLLMModelNameKey) }
            else { UserDefaults.standard.removeObject(forKey: LLMCopywriterService.localLLMModelNameKey) }
        }

        XCTAssertEqual(LLMCopywriterService.configuredLocalLLMModelName(), "qwen2.5:7b")
    }

    func testCleanupEngineLabelOllamaWithModel() {
        XCTAssertEqual(CleanupEngineLabel.ollama, "Ollama")
        XCTAssertEqual(CleanupEngineLabel.ollama(model: "llama3.2:3b"), "Ollama (llama3.2:3b)")
        XCTAssertEqual(CleanupEngineLabel.onDeviceLLM(model: "Qwen3-4B"), "On-Device LLM (Qwen3-4B)")
    }

    func testOnDeviceModelSelectionProperties() {
        XCTAssertEqual(OnDeviceModelSelection.auto.rawValue, "auto")
        XCTAssertEqual(OnDeviceModelSelection.small.rawValue, "small")
        XCTAssertEqual(OnDeviceModelSelection.large.rawValue, "large")

        XCTAssertEqual(OnDeviceModelSelection.auto.id, "auto")
        XCTAssertEqual(OnDeviceModelSelection.small.id, "small")
        XCTAssertEqual(OnDeviceModelSelection.large.id, "large")

        XCTAssertTrue(OnDeviceModelSelection.small.displayName.contains("0.6B"))
        XCTAssertTrue(OnDeviceModelSelection.large.displayName.contains("4B"))
        XCTAssertTrue(OnDeviceModelSelection.auto.displayName.contains("Auto"))
    }

    @MainActor
    func testOnDeviceLLMServiceModelPreferenceSwitching() {
        let service = OnDeviceLLMService.shared
        let prevPref = service.modelPreference
        defer {
            service.modelPreference = prevPref
        }

        service.modelPreference = .small
        XCTAssertEqual(service.modelPreference, .small)
        XCTAssertEqual(UserDefaults.standard.string(forKey: OnDeviceLLMService.modelPreferenceStorageKey), "small")

        service.modelPreference = .large
        XCTAssertEqual(service.modelPreference, .large)
        XCTAssertEqual(UserDefaults.standard.string(forKey: OnDeviceLLMService.modelPreferenceStorageKey), "large")

        service.modelPreference = .auto
        XCTAssertEqual(service.modelPreference, .auto)
        XCTAssertEqual(UserDefaults.standard.string(forKey: OnDeviceLLMService.modelPreferenceStorageKey), "auto")
    }

    @MainActor
    func testOnDeviceLLMServiceActiveModelRespectsPreferenceAndDownloadState() {
        let service = OnDeviceLLMService.shared
        let prevPref = service.modelPreference
        let prevState = service.largeModelState
        defer {
            service.modelPreference = prevPref
            service.setLargeModelStateForTesting(prevState)
        }

        // When large model is NOT ready:
        service.setLargeModelStateForTesting(.notDownloaded)
        service.modelPreference = .auto
        XCTAssertFalse(service.isUsingLargeModel)
        XCTAssertEqual(service.activeModelDisplayName, "Qwen3-0.6B")

        service.modelPreference = .large
        XCTAssertFalse(service.isUsingLargeModel, "Should fall back when large model is not ready")
        XCTAssertEqual(service.activeModelDisplayName, "Qwen3-0.6B")

        service.modelPreference = .small
        XCTAssertFalse(service.isUsingLargeModel)
        XCTAssertEqual(service.activeModelDisplayName, "Qwen3-0.6B")

        // When large model IS ready:
        service.setLargeModelStateForTesting(.ready)

        // 1. In .auto mode, it prefers large model
        service.modelPreference = .auto
        XCTAssertTrue(service.isUsingLargeModel)
        XCTAssertEqual(service.activeModelDisplayName, OnDeviceLLMService.largeModelDisplayName)

        // 2. In .large mode, it uses large model
        service.modelPreference = .large
        XCTAssertTrue(service.isUsingLargeModel)
        XCTAssertEqual(service.activeModelDisplayName, OnDeviceLLMService.largeModelDisplayName)

        // 3. In .small mode, it forces small model even though large model is ready!
        service.modelPreference = .small
        XCTAssertFalse(service.isUsingLargeModel)
        XCTAssertEqual(service.activeModelDisplayName, "Qwen3-0.6B")
    }
}
