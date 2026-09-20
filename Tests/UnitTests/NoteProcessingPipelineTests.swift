import XCTest
@testable import Voxbrief

fileprivate final class MockASRService: ASRServiceProtocol {
    var stubTranscript = "stub transcript"
    /// When non-empty, each call pops the next value (falling back to `stubTranscript` once
    /// drained) -- lets a test give successive append calls distinct transcripts.
    var transcriptQueue: [String] = []
    private(set) var receivedVocabulary: [String] = []
    private(set) var receivedAudioURLs: [URL] = []
    private(set) var warmUpCallCount = 0

    func transcribeAudio(at fileURL: URL, vocabulary: [String]) async throws -> String {
        receivedVocabulary = vocabulary
        receivedAudioURLs.append(fileURL)
        if !transcriptQueue.isEmpty {
            return transcriptQueue.removeFirst()
        }
        return stubTranscript
    }

    func warmUp() async {
        warmUpCallCount += 1
    }
}

fileprivate final class MockLLMCopywriterService: LLMCopywriterServiceProtocol, @unchecked Sendable {
    private(set) var receivedDictionaries: [[DictionaryEntry]] = []
    private(set) var receivedTranscripts: [String] = []
    private(set) var warmUpCallCount = 0

    func processTranscript(_ rawTranscript: String, mode: RewriteMode, dictionary: [DictionaryEntry]) async throws -> LLMProcessingResult {
        receivedDictionaries.append(dictionary)
        receivedTranscripts.append(rawTranscript)
        return LLMProcessingResult(
            title: "Mock Title",
            summary: "Mock Summary",
            requirements: [],
            conditions: [],
            actionItems: [],
            cleanedMarkdown: "mock markdown",
            tags: [],
            engine: "mock"
        )
    }

    func warmUp() async {
        warmUpCallCount += 1
    }
}

@MainActor
final class NoteProcessingPipelineTests: XCTestCase {

    fileprivate var mockASR: MockASRService!
    fileprivate var mockLLM: MockLLMCopywriterService!
    var repository: NoteRepository!
    var dictionaryStore: PersonalDictionaryStore!
    var pipeline: NoteProcessingPipeline!

    var repositoryStorageURL: URL!
    var dictionaryStorageURL: URL!

    override func setUp() {
        super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
        repositoryStorageURL = tempDir.appendingPathComponent("test_pipeline_notes_\(UUID().uuidString).json")
        dictionaryStorageURL = tempDir.appendingPathComponent("test_pipeline_dictionary_\(UUID().uuidString).json")

        mockASR = MockASRService()
        mockLLM = MockLLMCopywriterService()
        repository = NoteRepository(customStorageURL: repositoryStorageURL)
        dictionaryStore = PersonalDictionaryStore(customStorageURL: dictionaryStorageURL)
        dictionaryStore.add(term: "Voxbrief", aliases: ["fox brief"])
        dictionaryStore.add(term: "Kubernetes")

        pipeline = NoteProcessingPipeline(
            asrService: mockASR,
            llmService: mockLLM,
            repository: repository,
            audioFileManager: AudioFileManager(),
            dictionaryStore: dictionaryStore
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: repositoryStorageURL)
        try? FileManager.default.removeItem(at: dictionaryStorageURL)
        super.tearDown()
    }

    func testProcessPassesDictionaryTermsAsASRVocabulary() async {
        let note = VoiceNote(id: UUID(), audioFileName: "recording.m4a", status: .syncing)
        repository.save(note)

        await pipeline.process(note: note)

        XCTAssertEqual(Set(mockASR.receivedVocabulary), Set(["Voxbrief", "Kubernetes"]))
    }

    func testProcessOnlyRunsTheFullRewriteNotLight() async {
        let note = VoiceNote(id: UUID(), audioFileName: "recording.m4a", status: .syncing)
        repository.save(note)

        await pipeline.process(note: note)

        // The light rewrite is never generated eagerly -- see generateLightCleanup.
        XCTAssertEqual(mockLLM.receivedDictionaries.count, 1, "process() should only run the .full Stage 2 pass")
        XCTAssertEqual(Set(mockLLM.receivedDictionaries[0].map(\.term)), Set(["Voxbrief", "Kubernetes"]))
        XCTAssertNil(repository.note(withId: note.id)?.lightCleanedNote)
    }

    func testProcessAppliesDeterministicCorrectionBeforeStage2() async {
        mockASR.stubTranscript = "Let's discuss fox brief today."
        let note = VoiceNote(id: UUID(), audioFileName: "recording.m4a", status: .syncing)
        repository.save(note)

        await pipeline.process(note: note)

        XCTAssertEqual(mockLLM.receivedTranscripts.first, "Let's discuss Voxbrief today.")
        XCTAssertEqual(repository.note(withId: note.id)?.rawTranscript, "Let's discuss Voxbrief today.")
    }

    func testReprocessWithLLMThreadsDictionaryWithoutCallingASR() async {
        let note = VoiceNote(id: UUID(), rawTranscript: "fox brief needs a fix.", status: .ready)
        repository.save(note)

        await pipeline.reprocessWithLLM(noteId: note.id)

        XCTAssertTrue(mockASR.receivedVocabulary.isEmpty, "reprocessWithLLM should never call ASR")
        XCTAssertEqual(mockLLM.receivedDictionaries.count, 1, "reprocessWithLLM should only run the .full Stage 2 pass")
        XCTAssertEqual(mockLLM.receivedTranscripts.first, "Voxbrief needs a fix.", "Dictionary correction should retroactively apply to the stored transcript")
    }

    func testReprocessWithLLMInvalidatesAStaleLightCleanup() async {
        let note = VoiceNote(id: UUID(), rawTranscript: "fox brief needs a fix.", status: .ready, lightCleanedNote: "stale text", lightCleanupEngine: "mock")
        repository.save(note)

        await pipeline.reprocessWithLLM(noteId: note.id)

        let updated = repository.note(withId: note.id)
        XCTAssertNil(updated?.lightCleanedNote, "A transcript change should invalidate the old light rewrite rather than leave stale text")
        XCTAssertNil(updated?.lightCleanupEngine)
    }

    // MARK: - Lazy light cleanup

    func testGenerateLightCleanupIsANoOpUntilCalledExplicitly() async {
        let note = VoiceNote(id: UUID(), audioFileName: "recording.m4a", status: .syncing)
        repository.save(note)
        await pipeline.process(note: note)
        XCTAssertNil(repository.note(withId: note.id)?.lightCleanedNote)

        await pipeline.generateLightCleanup(noteId: note.id)

        let updated = repository.note(withId: note.id)
        XCTAssertNotNil(updated?.lightCleanedNote)
        XCTAssertEqual(updated?.lightCleanupEngine, "mock")
        XCTAssertEqual(mockLLM.receivedDictionaries.count, 2, "the process() full pass, then this explicit .light call")
    }

    func testGenerateLightCleanupDoesNothingWhenNoteIsNotReady() async {
        let note = VoiceNote(id: UUID(), status: .transcribingASR)
        repository.save(note)

        await pipeline.generateLightCleanup(noteId: note.id)

        XCTAssertNil(repository.note(withId: note.id)?.lightCleanedNote)
        XCTAssertTrue(mockLLM.receivedDictionaries.isEmpty)
    }

    func testGenerateLightCleanupDoesNothingWhenAlreadyGenerated() async {
        let note = VoiceNote(id: UUID(), rawTranscript: "already have a transcript.", status: .ready, lightCleanedNote: "already generated", lightCleanupEngine: "mock")
        repository.save(note)

        await pipeline.generateLightCleanup(noteId: note.id)

        XCTAssertEqual(repository.note(withId: note.id)?.lightCleanedNote, "already generated")
        XCTAssertTrue(mockLLM.receivedDictionaries.isEmpty, "should not re-generate an already-present light rewrite")
    }

    func testGenerateLightCleanupRespectsTheDisabledSetting() async {
        let previous = UserDefaults.standard.object(forKey: NoteProcessingPipeline.lightCleanupEnabledKey)
        UserDefaults.standard.set(false, forKey: NoteProcessingPipeline.lightCleanupEnabledKey)
        defer {
            if let previous { UserDefaults.standard.set(previous, forKey: NoteProcessingPipeline.lightCleanupEnabledKey) }
            else { UserDefaults.standard.removeObject(forKey: NoteProcessingPipeline.lightCleanupEnabledKey) }
        }

        let note = VoiceNote(id: UUID(), rawTranscript: "some transcript.", status: .ready)
        repository.save(note)

        await pipeline.generateLightCleanup(noteId: note.id)

        XCTAssertNil(repository.note(withId: note.id)?.lightCleanedNote)
        XCTAssertTrue(mockLLM.receivedDictionaries.isEmpty, "should not call the LLM at all when the setting is off")
    }

    // MARK: - Append / Merge (multi-segment notes)

    func testAppendRecordingTranscribesOnlyTheNewAudioAndReprocessesTheFullHistory() async {
        mockASR.stubTranscript = "First idea about the project."
        let note = VoiceNote(id: UUID(), duration: 10, audioFileName: "segment-1.m4a", status: .syncing)
        repository.save(note)
        await pipeline.process(note: note)

        XCTAssertEqual(mockASR.receivedAudioURLs.count, 1)

        mockASR.stubTranscript = "Second idea, a follow-up."
        let secondSegmentId = UUID()
        await pipeline.appendRecording(
            segmentId: secondSegmentId,
            audioFileName: "segment-2.m4a",
            duration: 8,
            source: .phoneApp,
            toNoteId: note.id
        )

        let updated = repository.note(withId: note.id)
        XCTAssertEqual(updated?.segments.count, 2)
        XCTAssertEqual(updated?.segments.last?.id, secondSegmentId)
        XCTAssertEqual(updated?.audioFileName, "segment-2.m4a", "Top-level audioFileName should track the latest segment")

        // Only the new audio was ever handed to ASR -- the first segment's transcript was reused.
        XCTAssertEqual(mockASR.receivedAudioURLs.count, 2)
        XCTAssertTrue(mockASR.receivedAudioURLs.last!.lastPathComponent.contains("segment-2"))

        // Stage 2 saw both segments' text together, not just the newest one.
        let mergedTranscript = mockLLM.receivedTranscripts.last!
        XCTAssertTrue(mergedTranscript.contains("First idea about the project."))
        XCTAssertTrue(mergedTranscript.contains("Second idea, a follow-up."))
        XCTAssertEqual(updated?.status, .ready)
    }

    func testMergeNoteFoldsSourceSegmentsIntoTargetAndDeletesSource() async {
        mockASR.stubTranscript = "Target note's original content."
        let target = VoiceNote(id: UUID(), duration: 12, audioFileName: "target.m4a", status: .syncing)
        repository.save(target)
        await pipeline.process(note: target)

        mockASR.stubTranscript = "A stray idea that belongs with the target."
        let source = VoiceNote(id: UUID(), duration: 6, audioFileName: "source.m4a", status: .syncing)
        repository.save(source)
        await pipeline.process(note: source)

        await pipeline.mergeNote(sourceId: source.id, intoTargetId: target.id)

        XCTAssertNil(repository.note(withId: source.id), "The source note's record should be gone after merging")

        let mergedTarget = repository.note(withId: target.id)
        XCTAssertEqual(mergedTarget?.segments.count, 2)
        XCTAssertEqual(mergedTarget?.status, .ready)

        let mergedTranscript = mockLLM.receivedTranscripts.last!
        XCTAssertTrue(mergedTranscript.contains("Target note's original content."))
        XCTAssertTrue(mergedTranscript.contains("A stray idea that belongs with the target."))
    }

    func testMergeNoteIgnoresRequestWhenSourceHasNoTranscriptYet() async {
        let target = VoiceNote(id: UUID(), rawTranscript: "Ready target.", status: .ready)
        repository.save(target)
        let unprocessedSource = VoiceNote(id: UUID(), status: .syncing)
        repository.save(unprocessedSource)

        await pipeline.mergeNote(sourceId: unprocessedSource.id, intoTargetId: target.id)

        XCTAssertNotNil(repository.note(withId: unprocessedSource.id), "An unprocessed source shouldn't be consumed by a merge")
        XCTAssertEqual(repository.note(withId: target.id)?.segments.count ?? 0, 0, "Target shouldn't change when the merge is rejected")
    }

    // MARK: - Cold-load warm-up

    func testWarmUpStartsBothServicesWarmUpConcurrently() async {
        await pipeline.warmUp().value

        XCTAssertEqual(mockASR.warmUpCallCount, 1)
        XCTAssertEqual(mockLLM.warmUpCallCount, 1)
        // warmUp() must never touch the actual transcription/generation path.
        XCTAssertTrue(mockASR.receivedAudioURLs.isEmpty)
        XCTAssertTrue(mockLLM.receivedTranscripts.isEmpty)
    }
}
