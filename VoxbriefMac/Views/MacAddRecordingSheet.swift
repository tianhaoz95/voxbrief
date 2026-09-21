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

            CaptureWaveformView(isRecording: recorder.isRecording, audioLevel: recorder.audioLevel)
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
        // Fixed width only -- NOT a fixed height. The content (headline + duration + the 187pt-tall
        // `CaptureWaveformView` + footnote + the optional permission-failure banner + Cancel button,
        // with 28pt spacing between each) needs ~520-590pt depending on whether the failure banner is
        // showing, well past a naive 360pt. SwiftUI does not clip a VStack that overflows a fixed
        // `.frame(height:)` -- it silently renders past the window's bottom edge, which was pushing
        // the Cancel button off-window entirely: present in the view tree, but below the visible sheet
        // and unclickable. Letting height size to content is what actually keeps Cancel reachable.
        .frame(width: 360)
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
