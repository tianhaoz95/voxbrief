import Foundation
#if canImport(ActivityKit)
import ActivityKit

public struct VoiceNoteActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public var isRecording: Bool
        public var duration: TimeInterval
        public var startedAt: Date
        public var audioLevel: Float
        
        public init(isRecording: Bool, duration: TimeInterval, startedAt: Date, audioLevel: Float = 0.5) {
            self.isRecording = isRecording
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
