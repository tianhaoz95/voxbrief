import Foundation
import Combine

@MainActor
public final class NoteListViewModel: ObservableObject {
    @Published public var searchText: String = ""
    @Published public var selectedTag: String? = nil
    @Published public var filterSource: NoteSource? = nil
    @Published public var onlyFavorites: Bool = false
    @Published public var showingRecordSheet: Bool = false
    @Published public var showingSyncStatus: Bool = false
    @Published public var showingSettings: Bool = false
    
    private let repository: NoteRepository
    public let syncService: WatchSyncService
    public let pipeline: NoteProcessingPipeline
    
    private var cancellables = Set<AnyCancellable>()
    
    public init(
        repository: NoteRepository = .shared,
        syncService: WatchSyncService = .shared,
        pipeline: NoteProcessingPipeline = .shared
    ) {
        self.repository = repository
        self.syncService = syncService
        self.pipeline = pipeline
        
        // Forward changes from repository
        repository.objectWillChange
            .sink { [weak self] in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    public var notes: [VoiceNote] {
        return repository.notes.filter { note in
            // Search filter
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                let matchesTitle = note.title.lowercased().contains(query)
                let matchesSummary = note.summary.lowercased().contains(query)
                let matchesTranscript = note.rawTranscript.lowercased().contains(query)
                let matchesCleaned = note.cleanedNote.lowercased().contains(query)
                if !matchesTitle && !matchesSummary && !matchesTranscript && !matchesCleaned {
                    return false
                }
            }
            
            // Tag filter
            if let selectedTag = selectedTag, !selectedTag.isEmpty {
                if !note.tags.contains(selectedTag) {
                    return false
                }
            }
            
            // Source filter
            if let filterSource = filterSource {
                if note.source != filterSource {
                    return false
                }
            }
            
            // Favorites filter
            if onlyFavorites && !note.isFavorite {
                return false
            }
            
            return true
        }
    }
    
    public var allTags: [String] {
        var tagsSet = Set<String>()
        for note in repository.notes {
            for tag in note.tags {
                tagsSet.insert(tag)
            }
        }
        return Array(tagsSet).sorted()
    }
    
    public func delete(note: VoiceNote) {
        repository.delete(id: note.id)
    }
    
    public func toggleFavorite(note: VoiceNote) {
        repository.toggleFavorite(id: note.id)
    }
    
    public func retryProcessing(note: VoiceNote) {
        Task {
            await pipeline.process(note: note)
        }
    }
}
