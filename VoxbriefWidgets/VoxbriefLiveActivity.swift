import ActivityKit
import WidgetKit
import SwiftUI

public struct VoxbriefLiveActivity: Widget {
    public init() {}
    
    public var body: some WidgetConfiguration {
        ActivityConfiguration(for: VoiceNoteActivityAttributes.self) { context in
            // Lock Screen / Smart Stack Live Activity presentation
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(context.state.phase.dotColor)
                            .frame(width: 8, height: 8)
                        Text("\(context.state.phase.headline) on \(context.attributes.source)")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if context.state.phase == .recording {
                        Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                            .font(.subheadline.monospacedDigit().bold())
                            .foregroundColor(.primary)
                    }
                }

                HStack(spacing: 12) {
                    Image(systemName: context.state.phase.symbolName)
                        .font(.title2)
                        .foregroundColor(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.phase.title)
                            .font(.subheadline.bold())
                        Text(context.state.phase.detail)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if context.state.phase == .recording {
                        Link(destination: URL(string: "voxbrief://record?action=stop&id=\(context.attributes.noteId)")!) {
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
            }
            .padding()
            .activityBackgroundTint(Color.black.opacity(0.85))
            .activitySystemActionForegroundColor(Color.white)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(context.state.phase.dotColor)
                            .frame(width: 8, height: 8)
                        Text(context.attributes.source)
                            .font(.caption.bold())
                    }
                    .padding(.leading, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.phase == .recording {
                        Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                            .font(.caption.monospacedDigit().bold())
                            .padding(.trailing, 8)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Label(context.state.phase.title, systemImage: context.state.phase.symbolName)
                            .font(.subheadline)
                        Spacer()
                        if context.state.phase == .recording {
                            Link(destination: URL(string: "voxbrief://record?action=stop&id=\(context.attributes.noteId)")!) {
                                Text("Stop & Save")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.red)
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                }
            } compactLeading: {
                Image(systemName: context.state.phase.symbolName)
                    .foregroundColor(context.state.phase.dotColor)
            } compactTrailing: {
                if context.state.phase == .recording {
                    Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
                        .font(.caption2.monospacedDigit())
                        .frame(width: 44)
                }
            } minimal: {
                Image(systemName: context.state.phase.symbolName)
                    .foregroundColor(context.state.phase.dotColor)
            }
        }
    }
}

private extension VoiceNoteActivityAttributes.Phase {
    var headline: String {
        switch self {
        case .recording: return "Recording Idea"
        case .processing: return "Cleaning Up Idea"
        case .ready: return "Idea Ready"
        case .failed: return "Idea Failed"
        }
    }

    var title: String {
        switch self {
        case .recording: return "Capturing Voice Note"
        case .processing: return "Cleaning Up Your Note"
        case .ready: return "Ready to Paste"
        case .failed: return "Processing Failed"
        }
    }

    var detail: String {
        switch self {
        case .recording: return "Stage 1 ASR & Stage 2 LLM cleanup upon stop"
        case .processing: return "Stage 1 ASR & Stage 2 LLM cleanup in progress"
        case .ready: return "Open Voxbrief to view or paste it"
        case .failed: return "Open Voxbrief to see what went wrong"
        }
    }

    var symbolName: String {
        switch self {
        case .recording: return "mic.fill"
        case .processing: return "waveform"
        case .ready: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    var dotColor: Color {
        switch self {
        case .recording: return .red
        case .processing: return .blue
        case .ready: return .green
        case .failed: return .orange
        }
    }
}

@main
struct VoxbriefWidgetBundle: WidgetBundle {
    var body: some Widget {
        VoxbriefLiveActivity()
    }
}
