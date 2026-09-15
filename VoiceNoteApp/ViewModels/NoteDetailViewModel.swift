import Foundation
import Combine

@MainActor
public final class NoteDetailViewModel: ObservableObject {
    @Published public var note: VoiceNote
    @Published public var selectedTab: DetailTab = .cleanedNote
    @Published public var isReprocessing: Bool = false
    
    public enum DetailTab: String, CaseIterable, Identifiable {
        case cleanedNote = "Cleaned Note"
        case rawTranscript = "Raw Transcript"
        case pipeline = "2-Stage Pipeline"
        
        public var id: String { rawValue }
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
    
    public func togglePlayback() {
        guard let fileName = note.audioFileName else { return }
        playbackService.play(fileName: fileName)
    }
    
    public func reprocessNote() {
        isReprocessing = true
        Task {
            await pipeline.reprocessWithLLM(noteId: note.id)
            isReprocessing = false
        }
    }
    
    public func toggleFavorite() {
        repository.toggleFavorite(id: note.id)
    }
}
