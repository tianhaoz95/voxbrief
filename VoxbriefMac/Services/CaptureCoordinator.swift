import Foundation
import Combine

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
    /// True for the lifetime of a capture started via `beginCapture(appendingTo:)` (the Notes
    /// browser's "Add Recording" sheet, which has its own full recording UI already) -- lets
    /// `OverlayWindowController` skip showing the global floating HUD for that flow, since showing
    /// both at once let either one drive `state` while the other's controls silently went stale.
    @Published public private(set) var isAppendCapture: Bool = false
    /// Real-time streaming transcript received progressively from Stage 1 ASR during processing.
    @Published public private(set) var streamingTranscript: String = ""
    /// True when Stage 1 ASR has finished and Stage 2 LLM copywriting is in progress.
    @Published public private(set) var isCleaningLLM: Bool = false

    public var audioLevel: Float { recorder.audioLevel }
    public var recordingDuration: TimeInterval { recorder.recordingDuration }

    private let recorder: MacAudioRecorderService
    private let repository: NoteRepository
    private let pipeline: NoteProcessingPipeline
    private let pasteInjector: PasteInjector

    private var cancellables = Set<AnyCancellable>()
    private var activeProcessingNoteId: UUID?

    /// Bumped on every `beginCapture()`/`cancelCapture()` so a still-running processing task from
    /// a cancelled/superseded capture can tell it's stale and skip pasting or updating state.
    private var generation = 0
    private var processingTask: Task<Void, Never>?

    /// Set by `beginCapture(appendingTo:)`; consumed by `completeCapture()`, which then appends the
    /// recording onto that existing note (via `NoteProcessingPipeline.appendRecording`) instead of
    /// creating a standalone note and pasting into the focused app. This is how the Notes browser's
    /// "Add Recording" action shares the same recorder/state machine as the global-hotkey flow.
    private var appendTargetNoteId: UUID?

    /// Guards against a second `beginCapture()` landing while the first is still awaiting the
    /// microphone-permission check below -- `state` is still `.idle` during that await, so the
    /// usual `guard state == .idle` at the top of `beginCapture` wouldn't catch a re-entrant call.
    private var isBeginningCapture = false

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

        pipeline.$streamingTranscripts
            .sink { [weak self] transcripts in
                guard let self, let id = self.activeProcessingNoteId else { return }
                self.streamingTranscript = transcripts[id] ?? ""
            }
            .store(in: &cancellables)

        repository.objectWillChange
            .sink { [weak self] in
                guard let self, let id = self.activeProcessingNoteId, let note = self.repository.note(withId: id) else { return }
                self.isCleaningLLM = (note.status == .cleaningLLM)
            }
            .store(in: &cancellables)
    }

    /// `appendingTo`, when set, means this recording will be folded into that existing note (via
    /// `NoteProcessingPipeline.appendRecording`) once it finishes, instead of becoming a new note
    /// that gets pasted into the previously-focused app.
    public func beginCapture(appendingTo targetNoteId: UUID? = nil) {
        guard state == .idle, !isBeginningCapture else { return }
        isBeginningCapture = true
        generation += 1
        let currentGeneration = generation
        appendTargetNoteId = targetNoteId
        isAppendCapture = targetNoteId != nil

        Task { [weak self] in
            guard let self else { return }
            defer { self.isBeginningCapture = false }

            let authorized = await self.recorder.ensureMicrophoneAccess()
            guard self.generation == currentGeneration else { return }
            guard authorized else {
                self.state = .failed("Microphone access is required. Enable it in System Settings > Privacy & Security > Microphone.")
                self.scheduleReturnToIdle()
                return
            }

            do {
                try self.recorder.startRecording()
                self.state = .listening
                self.pipeline.warmUp()
            } catch {
                self.state = .failed(error.localizedDescription)
                self.scheduleReturnToIdle()
            }
        }
    }

    public func completeCapture() {
        guard state == .listening, let result = recorder.stopRecording() else { return }
        state = .processing

        let currentGeneration = generation
        let appendTargetNoteId = self.appendTargetNoteId
        self.appendTargetNoteId = nil

        if let appendTargetNoteId {
            activeProcessingNoteId = appendTargetNoteId
            streamingTranscript = ""
            isCleaningLLM = false

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

        activeProcessingNoteId = result.noteId
        streamingTranscript = ""
        isCleaningLLM = false

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
        activeProcessingNoteId = nil
        streamingTranscript = ""
        isCleaningLLM = false
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
            self.activeProcessingNoteId = nil
            self.streamingTranscript = ""
            self.isCleaningLLM = false
            self.state = .idle
        }
    }
}
