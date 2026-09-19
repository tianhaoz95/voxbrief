import AppKit
import SwiftUI

/// Minimal browser for past Mac captures -- not a port of the iPhone app's full note list, just
/// enough to review or re-copy a recent capture. Backed by this app's own `NoteRepository`
/// instance (see `VoxbriefMacApp`), which is separate from the iPhone app's note history.
struct HistoryView: View {
    @ObservedObject var repository: NoteRepository
    @State private var selectedNoteId: VoiceNote.ID?

    var body: some View {
        NavigationSplitView {
            List(repository.notes, selection: $selectedNoteId) { note in
                VStack(alignment: .leading, spacing: 2) {
                    Text(note.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(note.id)
            }
            .navigationTitle("Capture History")
            .frame(minWidth: 220)
        } detail: {
            if let note = repository.notes.first(where: { $0.id == selectedNoteId }) {
                detail(for: note)
            } else {
                ContentUnavailableView("Select a capture", systemImage: "waveform")
            }
        }
        .frame(width: 640, height: 420)
    }

    private func detail(for note: VoiceNote) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(note.title)
                    .font(.title3.bold())
                Text(note.lightCleanedNote ?? note.cleanedNote)
                    .textSelection(.enabled)
                Divider()
                Text("Raw transcript")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(note.rawTranscript)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(note.lightCleanedNote ?? note.cleanedNote, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                Button(role: .destructive) {
                    repository.delete(id: note.id)
                    selectedNoteId = nil
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}
