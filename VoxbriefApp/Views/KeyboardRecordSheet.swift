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
///
/// `processingView` deliberately does NOT invite the user to switch away early, even though
/// `RecordingCoordinator`'s background task would let the pipeline survive it. That was tried
/// (an earlier version said "you can switch back now") and caused two problems, not one: leaving
/// while the on-device LLM (Stage 2) was actively generating crashed the whole app (a real
/// TestFlight crash -- see `OnDeviceLLMService`'s doc comment), and leaving before Stage 2 even
/// started silently downgraded the note to the plainer rule-based cleanup instead of the LLM one.
/// The fallback path stays as a safety net for an involuntary interruption (a phone call, the
/// screen locking, etc.), not something to route the common case through just to save a few
/// seconds of waiting -- on-device LLM quality is the point of this app.
public struct KeyboardRecordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recordingService = AudioRecordingService.shared
    private let coordinator = RecordingCoordinator.shared
    private let repository = NoteRepository.shared
    private let pipeline = NoteProcessingPipeline.shared

    @State private var phase: Phase = .recording
    @State private var errorMessage: String?
    /// Set once, in `onAppear`, i.e. the moment this app was opened from the keyboard. iOS's own
    /// "‹ Back to [App]" status-bar affordance is, by design, temporary -- it silently expires
    /// after roughly a couple of minutes with no public API to detect or extend it (confirmed via
    /// community reports going back to its iOS 9 introduction; Apple has never documented an exact
    /// duration). This is used purely as a best-effort heuristic for when it's likely already gone,
    /// to swap in fallback guidance rather than send the user hunting for a button that vanished.
    @State private var openedAt = Date()

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
                    // "Cancel" only actually cancels anything during .recording -- once stopped,
                    // processing is already committed and protected in the background (see
                    // RecordingCoordinator), so this just dismisses the sheet from here on.
                    Button(phase == .recording ? "Cancel" : "Close") {
                        if phase == .recording, recordingService.isRecording {
                            coordinator.cancelRecording()
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                openedAt = Date()
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

            Text("Heads up: iOS hides the **‹ Back** button in the top-left after a bit. If it's gone when you're done, just switch apps manually (hold the home indicator, or double-click Home) -- your note will be waiting on the clipboard either way.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

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
            // Deliberately does NOT invite switching away here. The on-device LLM (Stage 2) can
            // only safely run while this app is in the foreground -- see OnDeviceLLMService's
            // doc comment on the real crash this caused. Leaving mid-generation risks a crash;
            // leaving before it starts silently downgrades this note to the plainer rule-based
            // cleanup instead of the LLM one. Neither is something to invite as the common case
            // just to save a few seconds -- the background-task/Live Activity protection stays
            // as a safety net for an *involuntary* interruption (a call, etc.), not an invitation.
            Text("This usually only takes a few seconds -- keeping Voxbrief open gets you the better on-device LLM cleanup instead of a plainer fallback.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    // MARK: - Ready to paste

    private var readyToPasteView: some View {
        // iOS's "‹ Back" affordance isn't guaranteed to still be there by now -- see `openedAt`'s
        // doc comment. There's no way to actually check, so this is a best-effort guess: past a
        // conservative threshold, swap in guidance that doesn't send the user hunting for a
        // button that may have already vanished.
        let likelyBackButtonGone = Date().timeIntervalSince(openedAt) > 60

        return VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.green)
            Text("Ready to paste")
                .font(.title2.bold())
            if likelyBackButtonGone {
                Text("It's on your clipboard, ready to paste with any keyboard. It's been a little while, so iOS may have already hidden the **‹ Back** button -- if you don't see it, just switch back manually (hold the home indicator, or double-click Home) instead of looking for it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            } else {
                Text("Switch back to where you were typing -- tap the **‹ Back** button in the top-left corner -- and Voxbrief Keyboard will paste this in automatically. It's also on your clipboard, so a normal paste works with any keyboard.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
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
    /// `pipeline.process(note:)`, protected by a background task so this survives the user
    /// switching away -- see `RecordingCoordinator`), then generates the light rewrite
    /// specifically for this flow -- a near-verbatim proofread reads far better pasted into a
    /// chat/note than the fully restructured Markdown the full rewrite produces -- before handing
    /// the result to the keyboard.
    private func waitForResultAndHandOff(noteId: UUID) async {
        while true {
            if let note = repository.note(withId: noteId) {
                if note.status == .ready {
                    await pipeline.generateLightCleanup(noteId: noteId)
                    let finalNote = repository.note(withId: noteId) ?? note
                    let text = Self.bestPasteText(for: finalNote)
                    KeyboardHandoff.setPendingPaste(text)
                    // Also copies to the system clipboard -- if the user pastes with whatever
                    // keyboard happens to be active, they don't have to switch specifically back
                    // to Voxbrief Keyboard just for the auto-insert to fire.
                    UIPasteboard.general.string = text
                    NoteCompletionNotifier.notifyReady()
                    phase = .readyToPaste
                    return
                } else if note.status == .failed {
                    errorMessage = note.errorMessage ?? "Processing failed."
                    NoteCompletionNotifier.notifyFailed()
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
