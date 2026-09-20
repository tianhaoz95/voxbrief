import SwiftUI

/// Mac analogue of the iOS `QuickRecordSheet`, for "Add Recording" on an existing note's detail
/// screen (see `NoteDetailView`). Shares the same `CaptureCoordinator`/`MacAudioRecorderService`
/// instances as the global-hotkey capture flow (injected via `@EnvironmentObject` from
/// `VoxbriefMacApp`), just started in "append to this note" mode instead of "paste" mode.
struct MacAddRecordingSheet: View {
    let noteId: UUID

    @EnvironmentObject private var coordinator: CaptureCoordinator
    @EnvironmentObject private var recorder: MacAudioRecorderService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Text(headline)
                .font(.headline)
                .foregroundStyle(recorder.isRecording ? Color.accentColor : .secondary)

            Text(recorder.recordingDuration.formattedDuration)
                .font(.system(size: 52, weight: .medium, design: .monospaced))
                .monospacedDigit()

            ZStack {
                if recorder.isRecording {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 132 + CGFloat(recorder.audioLevel * 60),
                               height: 132 + CGFloat(recorder.audioLevel * 60))
                        .animation(.easeInOut(duration: 0.1), value: recorder.audioLevel)
                }

                Circle()
                    .fill(recorder.isRecording ? Color.red : Color.accentColor)
                    .frame(width: 96, height: 96)

                Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white)
            }
            .onTapGesture { toggleRecording() }

            Text(recorder.isRecording ? "Click to stop and add to this note" : "Click the microphone to add a recording")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if case .failed(let message) = coordinator.state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            Button("Cancel") {
                if recorder.isRecording {
                    coordinator.cancelCapture()
                }
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(24)
        .frame(width: 360, height: 360)
        .onAppear { coordinator.beginCapture(appendingTo: noteId) }
        .onChange(of: coordinator.state) { _, newState in
            if newState == .success {
                dismiss()
            }
        }
    }

    private var headline: String {
        switch coordinator.state {
        case .processing: return "Transcribing…"
        case .success: return "Added"
        case .failed: return "Failed"
        default: return recorder.isRecording ? "Listening…" : "Ready to Record"
        }
    }

    private func toggleRecording() {
        if recorder.isRecording {
            coordinator.completeCapture()
        } else {
            coordinator.beginCapture(appendingTo: noteId)
        }
    }
}
