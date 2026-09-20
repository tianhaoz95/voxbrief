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

    /// Non-nil while the "Append To…" picker is up for this note; drives `.sheet(item:)`.
    @Published public var mergeSourceNote: VoiceNote? = nil
    
    private let repository: NoteRepository
    public let pipeline: NoteProcessingPipeline

    private var cancellables = Set<AnyCancellable>()

    // Note: watch sync status used to be a `WatchSyncService` dependency here. It's been moved to
    // iOS's `NoteListView` owning its own `WatchSyncService.shared` directly instead, since this
    // view model is now shared with `VoxbriefMac`'s Notes browser (see project.yml) where it's not
    // meaningful (no Watch pairing on plain macOS), and it was only ever a UI-only concern anyway,
    // not note-filtering logic.
    public init(
        repository: NoteRepository = .shared,
        pipeline: NoteProcessingPipeline = .shared
    ) {
        self.repository = repository
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
                let matchesTags = note.tags.contains { $0.lowercased().contains(query) }
                let matchesRequirements = note.requirements.contains { $0.lowercased().contains(query) }
                let matchesConditions = note.conditions.contains { $0.lowercased().contains(query) }
                let matchesActionItems = note.actionItems.contains { $0.lowercased().contains(query) }
                let matchesAny = matchesTitle || matchesSummary || matchesTranscript || matchesCleaned
                    || matchesTags || matchesRequirements || matchesConditions || matchesActionItems
                if !matchesAny {
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

    public func beginMerge(source: VoiceNote) {
        mergeSourceNote = source
    }

    /// Other `.ready` notes `source` could be appended into -- excludes itself and anything still
    /// mid-pipeline (nothing to merge from, or an in-flight run `mergeNote` would collide with).
    public func mergeCandidates(excluding source: VoiceNote) -> [VoiceNote] {
        repository.notes.filter { $0.id != source.id && $0.status == .ready }
    }

    public func confirmMerge(source: VoiceNote, into target: VoiceNote) {
        Task {
            await pipeline.mergeNote(sourceId: source.id, intoTargetId: target.id)
        }
        mergeSourceNote = nil
    }

    /// Re-kicks the pipeline for any note still sitting in a non-terminal status. Safe to call
    /// at any time -- `NoteProcessingPipeline` no-ops for a note that's already actively running --
    /// so this doubles as manual (pull-to-refresh) and automatic (returning to foreground) recovery
    /// for a note whose background processing got cut off before reaching `.ready`/`.failed`.
    public func refresh() async {
        for note in repository.notes where note.status.isProcessing {
            await pipeline.process(note: note)
        }
    }

    public func exportAllNotesMarkdown() -> String {
        guard !repository.notes.isEmpty else {
            return "_No voice notes captured yet._"
        }
        return repository.notes
            .sorted(by: { $0.createdAt > $1.createdAt })
            .map { note in
                note.cleanedNote.isEmpty ? "# \(note.title)\n\n\(note.rawTranscript)" : note.cleanedNote
            }
            .joined(separator: "\n\n---\n\n")
    }
}
