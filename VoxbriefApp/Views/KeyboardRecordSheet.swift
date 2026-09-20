import SwiftUI

/// The flow VoxbriefKeyboard's record button opens into (`voxbrief://record?source=keyboard`,
/// routed by `VoxbriefApp.handleDeepLink`). Unlike `QuickRecordSheet`, this doesn't just dismiss
/// once recording stops -- it waits for the full pipeline (and the light rewrite, generated here
/// specifically because it's a better fit to paste into a chat/text field than the fully
/// restructured Markdown the full rewrite produces) to finish, hands the result to the keyboard
/// via `KeyboardHandoff`, and tells the user to switch back manually.
///
/// iOS has no public API for this app to force that switch itself -- see CLAUDE.md's notes on why
/// the "jump back" step stays a manual tap for the foreseeable future.
public struct KeyboardRecordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recordingService = AudioRecordingService.shared
    private let coordinator = RecordingCoordinator.shared
    private let repository = NoteRepository.shared
    private let pipeline = NoteProcessingPipeline.shared

    @State private var phase: Phase = .recording
    @State private var errorMessage: String?

    private enum Phase: Equatable {
        case recording
        case processing
        case readyToPaste
        case failed
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                switch phase {
                case .recording:
                    recordingView
                case .processing:
                    processingView
                case .readyToPaste:
                    readyToPasteView
                case .failed:
                    failedView
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Voxbrief Keyboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(phase == .readyToPaste ? "Done" : "Cancel") {
                        if phase == .recording, recordingService.isRecording {
                            coordinator.cancelRecording()
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                startAutoRecord()
            }
        }
    }

    // MARK: - Recording

    private var recordingView: some View {
        VStack(spacing: 28) {
            Text(recordingService.isRecording ? "Listening…" : "Getting ready…")
                .font(.headline)
                .foregroundStyle(recordingService.isRecording ? Color.accentColor : .secondary)

            Text(recordingService.recordingDuration.formattedDuration)
                .font(.system(size: 52, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .contentTransition(.numericText())

            ZStack {
                if recordingService.isRecording {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 132 + CGFloat(recordingService.audioLevel * 60),
                               height: 132 + CGFloat(recordingService.audioLevel * 60))
                        .animation(.easeInOut(duration: 0.1), value: recordingService.audioLevel)
                }

                Circle()
                    .fill(recordingService.isRecording ? Color.red : Color.accentColor)
                    .frame(width: 96, height: 96)

                Image(systemName: "stop.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white)
            }
            .onTapGesture {
                stopAndProcess()
            }

            Text("Tap to stop -- Voxbrief will clean it up and get it ready to paste")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }

    // MARK: - Processing

    private var processingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Cleaning up your recording…")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Ready to paste

    private var readyToPasteView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
            Text("Ready to paste")
                .font(.title2.bold())
            Text("Switch back to where you were typing -- tap the **‹ Back** button in the top-left corner -- and Voxbrief Keyboard will paste this in automatically.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    // MARK: - Failed

    private var failedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.orange)
            Text("Something went wrong")
                .font(.headline)
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }

    // MARK: - Flow

    private func startAutoRecord() {
        Task {
            let granted = await recordingService.requestPermission()
            if granted {
                do {
                    try await coordinator.beginRecording()
                } catch {
                    errorMessage = error.localizedDescription
                    phase = .failed
                }
            } else {
                errorMessage = "Microphone permission is required to record audio."
                phase = .failed
            }
        }
    }

    private func stopAndProcess() {
        guard let note = coordinator.finishRecording() else { return }
        phase = .processing
        Task {
            await waitForResultAndHandOff(noteId: note.id)
        }
    }

    /// Polls the repository until Stage 1+2 finish (`finishRecording()` already kicked off
    /// `pipeline.process(note:)`), then generates the light rewrite specifically for this flow --
    /// a near-verbatim proofread reads far better pasted into a chat/note than the fully
    /// restructured Markdown the full rewrite produces -- before handing the result to the
    /// keyboard.
    private func waitForResultAndHandOff(noteId: UUID) async {
        while true {
            if let note = repository.note(withId: noteId) {
                if note.status == .ready {
                    await pipeline.generateLightCleanup(noteId: noteId)
                    let finalNote = repository.note(withId: noteId) ?? note
                    KeyboardHandoff.setPendingPaste(Self.bestPasteText(for: finalNote))
                    phase = .readyToPaste
                    return
                } else if note.status == .failed {
                    errorMessage = note.errorMessage ?? "Processing failed."
                    phase = .failed
                    return
                }
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    /// Prefers the light rewrite (near-verbatim, reads like normal prose) over the full
    /// structured rewrite (headers/bullets/checklists -- looks wrong pasted into a chat) over the
    /// raw transcript as a last resort if both LLM passes somehow produced nothing.
    private static func bestPasteText(for note: VoiceNote) -> String {
        if let light = note.lightCleanedNote, !light.isEmpty { return light }
        if !note.cleanedNote.isEmpty { return note.cleanedNote }
        return note.rawTranscript
    }
}
