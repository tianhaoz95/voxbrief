import SwiftUI

public struct NoteRowView: View {
    public let note: VoiceNote
    
    public init(note: VoiceNote) {
        self.note = note
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row: Title & Favorite
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    Text(note.createdAt.relativeOrFormattedString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if note.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.caption)
                }
            }
            
            // Summary snippet
            if !note.summary.isEmpty {
                Text(note.summary)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            // Status or tags row
            HStack(spacing: 8) {
                // Source badge
                Label(note.source.displayName, systemImage: note.source.iconName)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.12))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
                
                // Duration badge if available
                if note.duration > 0 {
                    Label(note.duration.formattedDuration, systemImage: "waveform")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundColor(.secondary)
                        .clipShape(Capsule())
                }
                
                Spacer()
                
                // Status indicator
                if note.status.isProcessing {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.6)
                        Text(note.status == .transcribingASR ? "ASR" : (note.status == .cleaningLLM ? "LLM" : "Syncing"))
                            .font(.caption2.bold())
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())
                } else if note.status == .failed {
                    Text("Error")
                        .font(.caption2.bold())
                        .foregroundColor(.red)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.15))
                        .clipShape(Capsule())
                } else if !note.requirements.isEmpty || !note.conditions.isEmpty {
                    Text("\(note.requirements.count) reqs • \(note.conditions.count) conds")
                        .font(.caption2)
                        .foregroundColor(.purple)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.purple.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.vertical, 4)
    }
}
