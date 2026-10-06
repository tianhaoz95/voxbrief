import SwiftUI

public struct WatchNotesListView: View {
    @ObservedObject var storage = WatchStorage.shared
    @ObservedObject var syncService = WatchSyncService.shared
    
    public init() {}
    
    public var body: some View {
        List {
            if storage.notes.isEmpty {
                VStack(spacing: 8) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 44, height: 44)
                        Image(systemName: "waveform.slash")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    }
                    Text("No local recordings")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                    Text("Memos you record on your watch appear here until synced.")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 16)
                .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(storage.notes) { note in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .center) {
                                Text(note.createdAt.relativeOrFormattedString)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                syncBadge(for: note.syncState)
                            }
                            
                            HStack(spacing: 6) {
                                HStack(spacing: 3) {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 8))
                                    Text(note.duration.formattedDuration)
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                }
                                .foregroundColor(.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.12), in: Capsule())
                                
                                Spacer()
                                
                                Text(note.source.displayName)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(Color.accentColor)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            let note = storage.notes[index]
                            storage.delete(id: note.id)
                        }
                    }
                } header: {
                    HStack {
                        Text("Recordings (\(storage.notes.count))")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if storage.pendingNotes().count > 0 {
                            Button {
                                syncService.syncPendingNotes()
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 9, weight: .bold))
                                    Text("Sync")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundColor(.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.2), in: Capsule())
                            }
                            .buttonStyle(.plain)
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
            HStack(spacing: 3) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 8))
                Text("Queued")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(.orange)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.18), in: Capsule())
        case .transferring:
            HStack(spacing: 3) {
                ProgressView()
                    .scaleEffect(0.5)
                Text("Syncing")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(.blue)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.18), in: Capsule())
        case .synced:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(Color.accentColor)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.red)
        }
    }
}
