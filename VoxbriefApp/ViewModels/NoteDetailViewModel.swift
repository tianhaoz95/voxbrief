import Foundation
import Combine

@MainActor
public final class NoteDetailViewModel: ObservableObject {
    @Published public var note: VoiceNote
    @Published public var selectedTab: DetailTab = .cleanedNote
    @Published public var isReprocessing: Bool = false
    @Published public var isEditing: Bool = false
    @Published public var editedTitle: String = ""
    @Published public var editedCleanedNote: String = ""
    
    public enum DetailTab: String, CaseIterable, Identifiable {
        case cleanedNote = "Full Rewrite"
        case lightCleanup = "Light Cleanup"
        case rawTranscript = "Raw Transcript"
        case pipeline = "2-Stage Pipeline"

        public var id: String { rawValue }

        /// SF Symbol shown instead of `rawValue` when the segmented tab bar doesn't have room
        /// for four text labels (see `NoteDetailView.useCompactTabBar`).
        public var iconName: String {
            switch self {
            case .cleanedNote: return "doc.plaintext"
            case .lightCleanup: return "wand.and.stars"
            case .rawTranscript: return "waveform"
            case .pipeline: return "gearshape.2"
            }
        }
    }
    
    private let repository: NoteRepository
    private let pipeline: NoteProcessingPipeline
    public let playbackService: AudioPlaybackService
    
    private var cancellables = Set<AnyCancellable>()
    
    public init(
        note: VoiceNote,
        repository: NoteRepository = .shared,
        pipeline: NoteProcessingPipeline = .shared,
        playbackService: AudioPlaybackService = .shared
    ) {
        self.note = note
        self.repository = repository
        self.pipeline = pipeline
        self.playbackService = playbackService
        
        repository.objectWillChange
            .sink { [weak self] in
                guard let self = self else { return }
                if let updated = self.repository.note(withId: self.note.id) {
                    self.note = updated
                }
            }
            .store(in: &cancellables)
    }
    
    public var hasAudio: Bool {
        guard let fileName = note.audioFileName else { return false }
        return AudioFileManager.shared.fileExists(fileName: fileName)
    }

    /// True when this note's Stage 2 cleanup ran on the deterministic rule-based transformer
    /// because neither Ollama nor the on-device LLM was available -- surfaced in the UI so a
    /// degraded result is visible rather than looking identical to a full LLM cleanup.
    public var usedFallbackCleanup: Bool {
        note.cleanupEngine == CleanupEngineLabel.ruleBased
    }

    /// Same as `usedFallbackCleanup`, for the light rewrite shown on its own tab.
    public var usedFallbackCleanupLight: Bool {
        note.lightCleanupEngine == CleanupEngineLabel.ruleBased
    }

    public func togglePlayback() {
        guard let fileName = note.audioFileName else { return }
        playbackService.play(fileName: fileName)
    }

    public func seek(to progress: Double) {
        guard let fileName = note.audioFileName else { return }
        if playbackService.currentlyPlayingFileName != fileName {
            playbackService.play(fileName: fileName)
            playbackService.pause()
        }
        playbackService.seek(to: progress)
    }
    
    public func reprocessNote() {
        isReprocessing = true
        Task {
            await pipeline.reprocessWithLLM(noteId: note.id)
            isReprocessing = false
        }
    }

    /// Re-runs the full ASR + LLM pipeline from the original audio, for notes that failed
    /// before a transcript was ever produced (`reprocessNote()` only re-runs Stage 2, which
    /// needs an existing transcript and is a no-op otherwise).
    public func retryFullProcessing() {
        isReprocessing = true
        Task {
            await pipeline.process(note: note)
            isReprocessing = false
        }
    }
    
    public func toggleFavorite() {
        repository.toggleFavorite(id: note.id)
    }

    public func beginEditing() {
        editedTitle = note.title
        editedCleanedNote = note.cleanedNote
        isEditing = true
    }

    public func saveEdits() {
        var updated = note
        let trimmedTitle = editedTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.title = trimmedTitle.isEmpty ? note.title : trimmedTitle
        updated.cleanedNote = editedCleanedNote
        repository.save(updated)
        isEditing = false
    }

    public func cancelEditing() {
        isEditing = false
    }
}
