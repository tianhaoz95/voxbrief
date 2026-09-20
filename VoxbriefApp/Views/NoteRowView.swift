import SwiftUI

public struct NoteRowView: View {
    public let note: VoiceNote

    public init(note: VoiceNote) {
        self.note = note
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(note.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

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

            HStack(spacing: 4) {
                Text(metadataLine)

                Spacer(minLength: 8)

                statusIndicator
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 10)
    }

    private var shortProcessingLabel: String {
        switch note.status {
        case .syncing: return "Syncing"
        case .transcribingASR: return "Transcribing"
        case .cleaningLLM: return "Cleaning up"
        default: return "Processing"
        }
    }

    private var metadataLine: String {
        var parts = [note.createdAt.relativeOrFormattedString]
        if note.duration > 0 {
            parts.append(note.duration.formattedDuration)
        }
        parts.append(note.source.displayName)
        return parts.joined(separator: "  ·  ")
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
        } else if note.status == .failed {
            Label("Failed", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .labelStyle(.titleAndIcon)
        } else if note.cleanupEngine == CleanupEngineLabel.ruleBased {
            Label("Basic Cleanup", systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
                .labelStyle(.titleAndIcon)
        }
    }
}
