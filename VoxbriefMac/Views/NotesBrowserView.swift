import SwiftUI

/// Full-featured Mac counterpart to the iPhone app's `NoteListView` + `NoteDetailView` — same
/// notes (search, tag/source/favorite filters, export, edit, favorite, reprocess, retry, add
/// recording, append-to-note) and the same `NoteDetailView`, just in a desktop `NavigationSplitView`
/// instead of iOS's push navigation, since a list+detail split view is the native Mac idiom for
/// this rather than aping iOS's own chrome.
///
/// Backed by this app's own `NoteRepository`/`NoteProcessingPipeline`/`AudioPlaybackService`
/// instances (see `VoxbriefMacApp`) -- separate from the iPhone app's, since the two apps'
/// histories are intentionally separate (see `CaptureCoordinator`).
struct NotesBrowserView: View {
    @StateObject private var viewModel: NoteListViewModel
    private let repository: NoteRepository
    private let pipeline: NoteProcessingPipeline
    private let playbackService: AudioPlaybackService

    @State private var selectedNoteId: VoiceNote.ID?

    init(repository: NoteRepository, pipeline: NoteProcessingPipeline, playbackService: AudioPlaybackService) {
        self.repository = repository
        self.pipeline = pipeline
        self.playbackService = playbackService
        _viewModel = StateObject(wrappedValue: NoteListViewModel(repository: repository, pipeline: pipeline))
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let note = viewModel.notes.first(where: { $0.id == selectedNoteId }) {
                NoteDetailView(note: note, repository: repository, pipeline: pipeline, playbackService: playbackService)
                    .id(note.id)
            } else {
                ContentUnavailableView("Select a Note", systemImage: "waveform")
            }
        }
        .sheet(item: $viewModel.mergeSourceNote) { source in
            NoteMergePickerSheet(source: source, candidates: viewModel.mergeCandidates(excluding: source)) { target in
                viewModel.confirmMerge(source: source, into: target)
            }
        }
        .frame(minWidth: 760, minHeight: 480)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            if !viewModel.allTags.isEmpty {
                tagFilterBar
            }

            if viewModel.notes.isEmpty {
                ContentUnavailableView(
                    "No Notes Yet",
                    systemImage: "waveform",
                    description: Text("Press both ⌘ keys anywhere to capture your first note.")
                )
            } else {
                List(selection: $selectedNoteId) {
                    ForEach(viewModel.notes) { note in
                        NoteRowView(note: note)
                            .tag(note.id)
                            .contextMenu { contextMenu(for: note) }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle("Voice Notes")
        .navigationSplitViewColumnWidth(min: 240, ideal: 300)
        .searchable(text: $viewModel.searchText, prompt: "Search notes, requirements, tags...")
        .toolbar {
            ToolbarItem {
                Menu {
                    Picker("Source Filter", selection: $viewModel.filterSource) {
                        Text("All Sources").tag(NoteSource?.none)
                        Text("Mac").tag(NoteSource?.some(.macApp))
                        Text("Apple Watch").tag(NoteSource?.some(.watchApp))
                        Text("Watch Complication").tag(NoteSource?.some(.watchComplication))
                        Text("Watch Live Activity").tag(NoteSource?.some(.watchLiveActivity))
                        Text("iPhone Direct").tag(NoteSource?.some(.phoneApp))
                    }

                    Toggle(isOn: $viewModel.onlyFavorites) {
                        Label("Favorites Only", systemImage: "star")
                    }

                    Divider()

                    ShareLink(item: viewModel.exportAllNotesMarkdown()) {
                        Label("Export All Notes", systemImage: "square.and.arrow.up.on.square")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }

            ToolbarItem {
                SettingsLink {
                    Image(systemName: "gearshape")
                }
            }
        }
    }

    @ViewBuilder
    private func contextMenu(for note: VoiceNote) -> some View {
        Button {
            viewModel.toggleFavorite(note: note)
        } label: {
            Label(note.isFavorite ? "Unfavorite" : "Favorite", systemImage: note.isFavorite ? "star.slash" : "star.fill")
        }

        if note.status == .ready {
            Button {
                viewModel.beginMerge(source: note)
            } label: {
                Label("Append To…", systemImage: "arrow.triangle.merge")
            }
        }

        if note.status == .failed {
            Button {
                viewModel.retryProcessing(note: note)
            } label: {
                Label("Retry", systemImage: "arrow.triangle.2.circlepath")
            }
        }

        Divider()

        Button(role: .destructive) {
            if selectedNoteId == note.id {
                selectedNoteId = nil
            }
            viewModel.delete(note: note)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(title: "All", isSelected: viewModel.selectedTag == nil) {
                    viewModel.selectedTag = nil
                }

                ForEach(viewModel.allTags, id: \.self) { tag in
                    filterChip(title: tag, isSelected: viewModel.selectedTag == tag) {
                        viewModel.selectedTag = (viewModel.selectedTag == tag) ? nil : tag
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
    }

    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background {
                    Capsule().fill(isSelected ? Color.accentColor : Color.appTertiaryFill)
                }
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
