import Foundation
#if canImport(ActivityKit)
import ActivityKit

public struct VoiceNoteActivityAttributes: ActivityAttributes {
    /// `.recording` -> `.processing` -> `.ready`/`.failed`. Kept alive through `.processing`
    /// (rather than ending the Activity the moment recording stops) so the user has a
    /// system-wide, glanceable way to see Stage 1/2 progress and can leave the app immediately
    /// after tapping stop instead of waiting on-screen for the pipeline to finish.
    public enum Phase: String, Codable, Hashable {
        case recording
        case processing
        case ready
        case failed
    }

    public struct ContentState: Codable, Hashable {
        public var phase: Phase
        public var duration: TimeInterval
        public var startedAt: Date
        public var audioLevel: Float

        public init(phase: Phase, duration: TimeInterval, startedAt: Date, audioLevel: Float = 0.5) {
            self.phase = phase
            self.duration = duration
            self.startedAt = startedAt
            self.audioLevel = audioLevel
        }
    }
    
    public var noteId: String
    public var source: String
    
    public init(noteId: String = UUID().uuidString, source: String = "Watch") {
        self.noteId = noteId
        self.source = source
    }
}
#endif
