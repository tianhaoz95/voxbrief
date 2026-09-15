import SwiftUI

public struct WatchNotesListView: View {
    @ObservedObject var storage = WatchStorage.shared
    @ObservedObject var syncService = WatchSyncService.shared
    
    public init() {}
    
    public var body: some View {
        List {
            if storage.notes.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "waveform.slash")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Text("No local recordings")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
            } else {
                Section {
                    ForEach(storage.notes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(note.createdAt.relativeOrFormattedString)
                                    .font(.caption2.bold())
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                syncBadge(for: note.syncState)
                            }
                            
                            HStack {
                                Label(note.duration.formattedDuration, systemImage: "waveform")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text(note.source.displayName)
                                    .font(.system(size: 9))
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let note = storage.notes[index]
                            storage.delete(id: note.id)
                        }
                    }
                } header: {
                    HStack {
                        Text("Memos (\(storage.notes.count))")
                        Spacer()
                        if storage.pendingNotes().count > 0 {
                            Button("Sync") {
                                syncService.syncPendingNotes()
                            }
                            .font(.caption2)
                        }
                    }
                }
            }
        }
        .navigationTitle("Saved Memos")
    }
    
    @ViewBuilder
    private func syncBadge(for state: WatchSyncState) -> some View {
        switch state {
        case .pending:
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundColor(.orange)
        case .transferring:
            Image(systemName: "arrow.up.circle.fill")
                .font(.caption2)
                .foregroundColor(.blue)
        case .synced:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.caption2)
                .foregroundColor(.red)
        }
    }
}
