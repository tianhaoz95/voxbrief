import SwiftUI

/// Search-and-pick sheet for "Append To…": folds `source`'s recording into another existing note
/// so Stage 2 reprocesses both notes' transcripts together (see `NoteProcessingPipeline.mergeNote`).
public struct NoteMergePickerSheet: View {
    public let source: VoiceNote
    public let candidates: [VoiceNote]
    public let onSelect: (VoiceNote) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    public init(source: VoiceNote, candidates: [VoiceNote], onSelect: @escaping (VoiceNote) -> Void) {
        self.source = source
        self.candidates = candidates
        self.onSelect = onSelect
    }

    private var filteredCandidates: [VoiceNote] {
        guard !searchText.isEmpty else { return candidates }
        let query = searchText.lowercased()
        return candidates.filter {
            $0.title.lowercased().contains(query) || $0.summary.lowercased().contains(query)
        }
    }

    public var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    ContentUnavailableView(
                        "No Notes to Append To",
                        systemImage: "tray",
                        description: Text("Other notes need to finish processing before you can append this recording to them.")
                    )
                } else {
                    List(filteredCandidates) { candidate in
                        Button {
                            onSelect(candidate)
                            dismiss()
                        } label: {
                            NoteRowView(note: candidate)
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                    .searchable(text: $searchText, prompt: "Search notes")
                }
            }
            .navigationTitle("Append To…")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .trackFeedbackScreen("NoteMergePicker")
        }
    }
}
