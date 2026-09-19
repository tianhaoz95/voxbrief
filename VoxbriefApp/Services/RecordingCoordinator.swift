import Foundation

/// Single entry point for starting, finishing, and cancelling an iPhone-direct recording.
/// Both the record sheet's UI actions and the Live Activity's "Stop & Save" deep link route
/// through here so a recording is always finalized (saved + pipelined) exactly one way.
@MainActor
public final class RecordingCoordinator: ObservableObject {
    public static let shared = RecordingCoordinator()

    private let recordingService: AudioRecordingService
    private let repository: NoteRepository
    private let pipeline: NoteProcessingPipeline
    private let liveActivity: LiveActivityManager

    @Published public private(set) var activeNoteId: UUID?

    /// Set by `beginRecording(appendingTo:)`; consumed and cleared by `finishRecording()`, which
    /// branches into `NoteProcessingPipeline.appendRecording` instead of creating a standalone note.
    private var appendTargetNoteId: UUID?

    public init(
        recordingService: AudioRecordingService = .shared,
        repository: NoteRepository = .shared,
        pipeline: NoteProcessingPipeline = .shared,
        liveActivity: LiveActivityManager = .shared
    ) {
        self.recordingService = recordingService
        self.repository = repository
        self.pipeline = pipeline
        self.liveActivity = liveActivity
    }

    /// `appendingTo`, when set, means the recording being started will be folded into that
    /// existing note (via `appendRecording`) instead of becoming a standalone note once finished.
    public func beginRecording(appendingTo targetNoteId: UUID? = nil) async throws {
        let noteId = UUID()
        try recordingService.startRecording(for: noteId)
        activeNoteId = noteId
        appendTargetNoteId = targetNoteId
        liveActivity.start(noteId: noteId, source: "iPhone")
    }

    /// Stops the active recording and either kicks off the two-stage pipeline as a new note, or --
    /// if `beginRecording(appendingTo:)` set a target -- appends it onto that existing note instead.
    @discardableResult
    public func finishRecording() -> VoiceNote? {
        guard let result = recordingService.stopRecording() else { return nil }
        let audioFileName = "\(result.noteId.uuidString).\(AudioConstants.fileExtension)"

        liveActivity.end()
        activeNoteId = nil

        if let targetNoteId = appendTargetNoteId {
            appendTargetNoteId = nil
            Task {
                await pipeline.appendRecording(
                    segmentId: result.noteId,
                    audioFileName: audioFileName,
                    duration: result.duration,
                    source: .phoneApp,
                    toNoteId: targetNoteId
                )
            }
            return repository.note(withId: targetNoteId)
        }

        let note = VoiceNote(
            id: result.noteId,
            createdAt: Date(),
            duration: result.duration,
            audioFileName: audioFileName,
            title: "Processing Voice Note...",
            summary: "Extracting transcript and structuring requirements...",
            rawTranscript: "",
            cleanedNote: "",
            requirements: [],
            conditions: [],
            actionItems: [],
            tags: [],
            status: .transcribingASR,
            source: .phoneApp
        )
        repository.save(note)
        Task { await pipeline.process(note: note) }
        return note
    }

    public func cancelRecording() {
        recordingService.cancelRecording()
        liveActivity.end()
        activeNoteId = nil
        appendTargetNoteId = nil
    }

    /// Handles `voxbrief://record?action=stop` from the Live Activity / Dynamic Island link.
    public func handleStopDeepLink() {
        guard recordingService.isRecording else { return }
        finishRecording()
    }
}
