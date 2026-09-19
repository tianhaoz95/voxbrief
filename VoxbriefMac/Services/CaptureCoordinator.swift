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

    private let recorder: MacAudioRecorderService
    private let repository: NoteRepository
    private let pipeline: NoteProcessingPipeline
    private let pasteInjector: PasteInjector

    /// Bumped on every `beginCapture()`/`cancelCapture()` so a still-running processing task from
    /// a cancelled/superseded capture can tell it's stale and skip pasting or updating state.
    private var generation = 0
    private var processingTask: Task<Void, Never>?

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

    public func beginCapture() {
        guard state == .idle else { return }
        generation += 1
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
