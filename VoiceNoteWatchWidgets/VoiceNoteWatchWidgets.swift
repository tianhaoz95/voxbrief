import WidgetKit
import SwiftUI

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: Date(), isRecording: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        let entry = ComplicationEntry(date: Date(), isRecording: false)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let entry = ComplicationEntry(date: Date(), isRecording: false)
        // Refresh every 1 hour or when app updates
        let timeline = Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(3600)))
        completion(timeline)
    }
}

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let isRecording: Bool
}

struct VoiceNoteComplicationView: View {
    @Environment(\.widgetFamily) var family
    var entry: ComplicationEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: entry.isRecording ? "waveform.badge.mic" : "mic.fill")
                    .font(.title3)
                    .foregroundColor(entry.isRecording ? .red : .blue)
            }
            .widgetURL(URL(string: "voicenote://record?source=watch_complication"))

        case .accessoryCorner:
            Image(systemName: "mic.fill")
                .foregroundColor(.blue)
                .widgetLabel {
                    Text("Voice Note")
                }
                .widgetURL(URL(string: "voicenote://record?source=watch_complication"))

        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: "mic.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Capture Idea")
                        .font(.headline)
                        .lineLimit(1)
                    Text("Tap to record memo")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .widgetURL(URL(string: "voicenote://record?source=watch_complication"))

        case .accessoryInline:
            Label("Record Idea", systemImage: "mic.fill")
                .widgetURL(URL(string: "voicenote://record?source=watch_complication"))

        default:
            Image(systemName: "mic.fill")
                .widgetURL(URL(string: "voicenote://record?source=watch_complication"))
        }
    }
}

struct VoiceNoteComplication: Widget {
    let kind: String = "VoiceNoteComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ComplicationProvider()) { entry in
            VoiceNoteComplicationView(entry: entry)
        }
        .configurationDisplayName("Voice Note Quick Capture")
        .description("One-tap voice capture right from your watch face.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

@main
struct VoiceNoteWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        VoiceNoteComplication()
    }
}
