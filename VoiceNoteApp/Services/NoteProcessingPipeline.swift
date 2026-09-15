import Foundation

@MainActor
public final class NoteProcessingPipeline: ObservableObject {
    public static let shared = NoteProcessingPipeline()
    
    private let asrService: ASRServiceProtocol
    private let llmService: LLMCopywriterServiceProtocol
    private let repository: NoteRepository
    private let audioFileManager: AudioFileManager
    
    @Published public private(set) var activeProcessingCount: Int = 0
    
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
        guard let audioFileName = note.audioFileName else {
            repository.updateStatus(for: note.id, status: .failed, errorMessage: "Missing audio file.")
            return
        }
        
        let audioURL = audioFileManager.url(for: audioFileName)
        activeProcessingCount += 1
        defer { activeProcessingCount -= 1 }
        
        do {
            // Stage 1: ASR Speech-to-Text
            repository.updateStatus(for: note.id, status: .transcribingASR)
            let rawTranscript = try await asrService.transcribeAudio(at: audioURL)
            
            // Stage 2: On-device LLM cleanup / copywriting
            repository.updateStatus(for: note.id, status: .cleaningLLM)
            let llmResult = try await llmService.processTranscript(rawTranscript)
            
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
            
            repository.save(updatedNote)
            
            print("[NoteProcessingPipeline] Successfully processed note: \(note.id) -> '\(llmResult.title)'")
        } catch {
            print("[NoteProcessingPipeline] Processing failed for note \(note.id): \(error)")
            repository.updateStatus(for: note.id, status: .failed, errorMessage: error.localizedDescription)
        }
    }
    
    /// Re-runs Stage 2 (LLM copywriting) on an existing note's raw transcript
    public func reprocessWithLLM(noteId: UUID) async {
        guard var note = repository.note(withId: noteId), !note.rawTranscript.isEmpty else { return }
        
        activeProcessingCount += 1
        defer { activeProcessingCount -= 1 }
        
        repository.updateStatus(for: noteId, status: .cleaningLLM)
        do {
            let llmResult = try await llmService.processTranscript(note.rawTranscript)
            note.title = llmResult.title
            note.summary = llmResult.summary
            note.cleanedNote = llmResult.cleanedMarkdown
            note.requirements = llmResult.requirements
            note.conditions = llmResult.conditions
            note.actionItems = llmResult.actionItems
            note.tags = llmResult.tags
            note.status = .ready
            note.errorMessage = nil
            repository.save(note)
        } catch {
            repository.updateStatus(for: noteId, status: .failed, errorMessage: error.localizedDescription)
        }
    }
}
