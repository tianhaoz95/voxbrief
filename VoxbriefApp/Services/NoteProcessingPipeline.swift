import Foundation

@MainActor
public final class NoteProcessingPipeline: ObservableObject {
    public static let shared = NoteProcessingPipeline()
    
    private let asrService: ASRServiceProtocol
    private let llmService: LLMCopywriterServiceProtocol
    private let repository: NoteRepository
    private let audioFileManager: AudioFileManager
    
    @Published public private(set) var activeProcessingCount: Int = 0

    /// Notes currently mid-pipeline. Guards against double-processing the same note when a
    /// retry, a pull-to-refresh, and the original sync-triggered run could otherwise overlap.
    private var inFlightNoteIds: Set<UUID> = []

    public init(
        asrService: ASRServiceProtocol = ASRService.shared,
        llmService: LLMCopywriterServiceProtocol = LLMCopywriterService.shared,
        repository: NoteRepository = .shared,
        audioFileManager: AudioFileManager = .shared
    ) {
        self.asrService = asrService
        self.llmService = llmService
        self.repository = repository
        self.audioFileManager = audioFileManager
    }
    
    /// Executes the two-stage processing pipeline for a given voice note
    public func process(note: VoiceNote) async {
        guard !inFlightNoteIds.contains(note.id) else { return }

        guard let audioFileName = note.audioFileName else {
            repository.updateStatus(for: note.id, status: .failed, errorMessage: "Missing audio file.")
            return
        }

        let audioURL = audioFileManager.url(for: audioFileName)
        inFlightNoteIds.insert(note.id)
        activeProcessingCount += 1
        defer {
            inFlightNoteIds.remove(note.id)
            activeProcessingCount -= 1
        }
        
        do {
            // Stage 1: ASR Speech-to-Text
            repository.updateStatus(for: note.id, status: .transcribingASR)
            let rawTranscript = try await asrService.transcribeAudio(at: audioURL)
            
            // Stage 2: On-device LLM cleanup / copywriting -- runs both rewrite styles
            // concurrently; the light pass is best-effort and never fails the note.
            repository.updateStatus(for: note.id, status: .cleaningLLM)
            async let fullResultAsync = llmService.processTranscript(rawTranscript, mode: .full)
            async let lightResultAsync = llmService.processTranscript(rawTranscript, mode: .light)
            let llmResult = try await fullResultAsync
            let lightResult = try? await lightResultAsync

            // Build completed note
            var updatedNote = note
            updatedNote.rawTranscript = rawTranscript
            updatedNote.title = llmResult.title
            updatedNote.summary = llmResult.summary
            updatedNote.cleanedNote = llmResult.cleanedMarkdown
            updatedNote.requirements = llmResult.requirements
            updatedNote.conditions = llmResult.conditions
            updatedNote.actionItems = llmResult.actionItems
            updatedNote.tags = llmResult.tags
            updatedNote.status = .ready
            updatedNote.errorMessage = nil
            updatedNote.cleanupEngine = llmResult.engine
            updatedNote.lightCleanedNote = lightResult?.cleanedMarkdown
            updatedNote.lightCleanupEngine = lightResult?.engine

            repository.save(updatedNote)
            
            print("[NoteProcessingPipeline] Successfully processed note: \(note.id) -> '\(llmResult.title)'")
        } catch {
            print("[NoteProcessingPipeline] Processing failed for note \(note.id): \(error)")
            var failedNote = note
            failedNote.status = .failed
            failedNote.errorMessage = error.localizedDescription
            if failedNote.title == "Processing Voice Note..." {
                failedNote.title = "Processing Failed"
                failedNote.summary = error.localizedDescription
            }
            repository.save(failedNote)
        }
    }
    
    /// Re-runs Stage 2 (LLM copywriting) on an existing note's raw transcript
    public func reprocessWithLLM(noteId: UUID) async {
        guard var note = repository.note(withId: noteId), !note.rawTranscript.isEmpty else { return }
        
        activeProcessingCount += 1
        defer { activeProcessingCount -= 1 }
        
        repository.updateStatus(for: noteId, status: .cleaningLLM)
        do {
            async let fullResultAsync = llmService.processTranscript(note.rawTranscript, mode: .full)
            async let lightResultAsync = llmService.processTranscript(note.rawTranscript, mode: .light)
            let llmResult = try await fullResultAsync
            let lightResult = try? await lightResultAsync
            note.title = llmResult.title
            note.summary = llmResult.summary
            note.cleanedNote = llmResult.cleanedMarkdown
            note.requirements = llmResult.requirements
            note.conditions = llmResult.conditions
            note.actionItems = llmResult.actionItems
            note.tags = llmResult.tags
            note.status = .ready
            note.errorMessage = nil
            note.cleanupEngine = llmResult.engine
            note.lightCleanedNote = lightResult?.cleanedMarkdown
            note.lightCleanupEngine = lightResult?.engine
            repository.save(note)
        } catch {
            repository.updateStatus(for: noteId, status: .failed, errorMessage: error.localizedDescription)
        }
    }
}
