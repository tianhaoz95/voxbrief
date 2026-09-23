import SwiftUI

public struct NoteRowView: View {
    public let note: VoiceNote

    public init(note: VoiceNote) {
        self.note = note
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 6) {
                Text(note.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                statusIndicator

                if note.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                }
            }

            if !note.summary.isEmpty {
                Text(note.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var shortProcessingLabel: String {
        switch note.status {
        case .syncing: return "Syncing"
        case .transcribingASR: return "Transcribing"
        case .cleaningLLM: return "Cleaning up"
        default: return "Processing"
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if note.status.isProcessing {
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.6)
                Text(shortProcessingLabel)
                    .lineLimit(1)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        } else if note.status == .failed {
            Label("Failed", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .labelStyle(.titleAndIcon)
                .font(.caption2)
        } else if note.cleanupEngine == CleanupEngineLabel.ruleBased {
            Label("Basic Cleanup", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .labelStyle(.titleAndIcon)
                .font(.caption2)
        }
    }
}
