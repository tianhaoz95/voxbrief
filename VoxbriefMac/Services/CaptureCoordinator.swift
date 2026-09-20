import Foundation

/// Drives one end-to-end capture: hotkey -> record -> ASR/LLM pipeline -> paste. The Mac analogue
/// of the iOS `RecordingCoordinator`, except the "finish" action pastes into the previously
/// focused app instead of just saving a note.
///
/// Owns its own `NoteRepository`/`AudioFileManager`/`NoteProcessingPipeline` instances (pointed at
/// this app's own storage locations -- see `VoxbriefMacApp`) rather than the iOS `.shared`
/// singletons, since the two apps' note histories are intentionally separate.
@MainActor
public final class CaptureCoordinator: ObservableObject {
    public enum State: Equatable {
        case idle
        case listening
        case processing
        case success
        case failed(String)
    }

    @Published public private(set) var state: State = .idle
    public var audioLevel: Float { recorder.audioLevel }
    public var recordingDuration: TimeInterval { recorder.recordingDuration }

    private let recorder: MacAudioRecorderService
    private let repository: NoteRepository
    private let pipeline: NoteProcessingPipeline
    private let pasteInjector: PasteInjector

    /// Bumped on every `beginCapture()`/`cancelCapture()` so a still-running processing task from
    /// a cancelled/superseded capture can tell it's stale and skip pasting or updating state.
    private var generation = 0
    private var processingTask: Task<Void, Never>?

    /// Set by `beginCapture(appendingTo:)`; consumed by `completeCapture()`, which then appends the
    /// recording onto that existing note (via `NoteProcessingPipeline.appendRecording`) instead of
    /// creating a standalone note and pasting into the focused app. This is how the Notes browser's
    /// "Add Recording" action shares the same recorder/state machine as the global-hotkey flow.
    private var appendTargetNoteId: UUID?

    public init(
        recorder: MacAudioRecorderService,
        repository: NoteRepository,
        pipeline: NoteProcessingPipeline,
        pasteInjector: PasteInjector
    ) {
        self.recorder = recorder
        self.repository = repository
        self.pipeline = pipeline
        self.pasteInjector = pasteInjector
    }

    /// `appendingTo`, when set, means this recording will be folded into that existing note (via
    /// `NoteProcessingPipeline.appendRecording`) once it finishes, instead of becoming a new note
    /// that gets pasted into the previously-focused app.
    public func beginCapture(appendingTo targetNoteId: UUID? = nil) {
        guard state == .idle else { return }
        generation += 1
        appendTargetNoteId = targetNoteId
        do {
            try recorder.startRecording()
            state = .listening
        } catch {
            state = .failed(error.localizedDescription)
            scheduleReturnToIdle()
        }
    }

    public func completeCapture() {
        guard state == .listening, let result = recorder.stopRecording() else { return }
        state = .processing

        let currentGeneration = generation
        let appendTargetNoteId = self.appendTargetNoteId
        self.appendTargetNoteId = nil

        if let appendTargetNoteId {
            processingTask = Task { [pipeline, repository] in
                await pipeline.appendRecording(
                    segmentId: result.noteId,
                    audioFileName: "\(result.noteId.uuidString).\(AudioConstants.fileExtension)",
                    duration: result.duration,
                    source: .macApp,
                    toNoteId: appendTargetNoteId
                )
                guard self.generation == currentGeneration else { return }
                guard let updated = repository.note(withId: appendTargetNoteId), updated.status == .ready else {
                    self.state = .failed(repository.note(withId: appendTargetNoteId)?.errorMessage ?? "Processing failed.")
                    self.scheduleReturnToIdle()
                    return
                }
                self.state = .success
                self.scheduleReturnToIdle()
            }
            return
        }

        processingTask = Task { [pipeline, repository, pasteInjector] in
            let draft = VoiceNote(
                id: result.noteId,
                createdAt: Date(),
                duration: result.duration,
                audioFileName: "\(result.noteId.uuidString).\(AudioConstants.fileExtension)",
                title: "Processing Voice Capture...",
                summary: "Transcribing and cleaning up...",
                status: .transcribingASR,
                source: .macApp
            )
            repository.save(draft)

            await pipeline.process(note: draft)
            guard let processed = repository.note(withId: draft.id) else { return }

            guard self.generation == currentGeneration else { return }

            guard processed.status == .ready else {
                self.state = .failed(processed.errorMessage ?? "Processing failed.")
                self.scheduleReturnToIdle()
                return
            }

            let textToPaste = processed.lightCleanedNote ?? processed.cleanedNote
            do {
                try await pasteInjector.paste(textToPaste)
                guard self.generation == currentGeneration else { return }
                self.state = .success
            } catch {
                guard self.generation == currentGeneration else { return }
                self.state = .failed(error.localizedDescription)
            }
            self.scheduleReturnToIdle()
        }
    }

    public func cancelCapture() {
        generation += 1
        appendTargetNoteId = nil
        processingTask?.cancel()
        processingTask = nil
        switch state {
        case .listening:
            recorder.cancelRecording()
        default:
            break
        }
        state = .idle
    }

    private func scheduleReturnToIdle() {
        let currentGeneration = generation
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard self.generation == currentGeneration else { return }
            self.state = .idle
        }
    }
}
