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

    public func beginRecording() async throws {
        let noteId = UUID()
        try recordingService.startRecording(for: noteId)
        activeNoteId = noteId
        liveActivity.start(noteId: noteId, source: "iPhone")
    }

    /// Stops the active recording, persists it, and kicks off the two-stage pipeline.
    @discardableResult
    public func finishRecording() -> VoiceNote? {
        guard let result = recordingService.stopRecording() else { return nil }

        let note = VoiceNote(
            id: result.noteId,
            createdAt: Date(),
            duration: result.duration,
            audioFileName: "\(result.noteId.uuidString).\(AudioConstants.fileExtension)",
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

        liveActivity.end()
        activeNoteId = nil
        return note
    }

    public func cancelRecording() {
        recordingService.cancelRecording()
        liveActivity.end()
        activeNoteId = nil
    }

    /// Handles `voxbrief://record?action=stop` from the Live Activity / Dynamic Island link.
    public func handleStopDeepLink() {
        guard recordingService.isRecording else { return }
        finishRecording()
    }
}
