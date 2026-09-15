import ActivityKit
import WidgetKit
import SwiftUI

public struct VoiceNoteLiveActivity: Widget {
    public init() {}
    
    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: VoiceNoteActivityAttributes.self) { context in
            // Lock Screen / Smart Stack Live Activity presentation
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("Recording Idea on \(context.attributes.source)")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                        .font(.subheadline.monospacedDigit().bold())
                        .foregroundColor(.primary)
                }
                
                HStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Capturing Voice Note")
                            .font(.subheadline.bold())
                        Text("Stage 1 ASR & Stage 2 LLM cleanup upon stop")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Link(destination: URL(string: "voicenote://record?action=stop&id=\(context.attributes.noteId)")!) {
                        Text("Stop & Save")
                            .font(.caption.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.85))
            .activitySystemActionForegroundColor(Color.white)
            
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text(context.attributes.source)
                            .font(.caption.bold())
                    }
                    .padding(.leading, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                        .font(.caption.monospacedDigit().bold())
                        .padding(.trailing, 8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label("Voice Note Capturing", systemImage: "waveform")
                            .font(.subheadline)
                        Spacer()
                        Link(destination: URL(string: "voicenote://record?action=stop&id=\(context.attributes.noteId)")!) {
                            Text("Stop & Save")
                                .font(.caption.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.red)
                                .foregroundColor(.white)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 8)
                }
            } compactLeading: {
                Image(systemName: "mic.fill")
                    .foregroundColor(.red)
            } compactTrailing: {
                Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                    .font(.caption2.monospacedDigit())
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "mic.fill")
                    .foregroundColor(.red)
            }
        }
    }
}

@main
struct VoiceNoteWidgetBundle: WidgetBundle {
    var body: some Widget {
        VoiceNoteLiveActivity()
    }
}
