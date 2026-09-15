import Foundation

/// Defines keys and helpers for WatchConnectivity file and metadata transfers
public struct SyncConstants {
    public static let keyNoteId = "note_id"
    public static let keyCreatedAt = "created_at"
    public static let keyDuration = "duration"
    public static let keySource = "source"
    public static let keyAudioFileName = "audio_filename"
    public static let keyAction = "action"
    
    // Actions
    public static let actionAudioTransfer = "audio_transfer"
    public static let actionPing = "ping"
    public static let actionAck = "ack"
    public static let actionRequestSync = "request_sync"
}

public struct WatchSyncPayload: Codable, Sendable {
    public let noteId: UUID
    public let createdAt: Date
    public let duration: TimeInterval
    public let source: NoteSource
    public let audioFileName: String
    
    public init(noteId: UUID, createdAt: Date, duration: TimeInterval, source: NoteSource, audioFileName: String) {
        self.noteId = noteId
        self.createdAt = createdAt
        self.duration = duration
        self.source = source
        self.audioFileName = audioFileName
    }
    
    public var dictionaryRepresentation: [String: Any] {
        return [
            SyncConstants.keyAction: SyncConstants.actionAudioTransfer,
            SyncConstants.keyNoteId: noteId.uuidString,
            SyncConstants.keyCreatedAt: createdAt.timeIntervalSince1970,
            SyncConstants.keyDuration: duration,
            SyncConstants.keySource: source.rawValue,
            SyncConstants.keyAudioFileName: audioFileName
        ]
    }
    
    public static func from(dictionary: [String: Any]) -> WatchSyncPayload? {
        guard let idString = dictionary[SyncConstants.keyNoteId] as? String,
              let id = UUID(uuidString: idString),
              let timestamp = dictionary[SyncConstants.keyCreatedAt] as? TimeInterval,
              let duration = dictionary[SyncConstants.keyDuration] as? TimeInterval,
              let sourceRaw = dictionary[SyncConstants.keySource] as? String,
              let source = NoteSource(rawValue: sourceRaw),
              let audioFileName = dictionary[SyncConstants.keyAudioFileName] as? String else {
            return nil
        }
        return WatchSyncPayload(
            noteId: id,
            createdAt: Date(timeIntervalSince1970: timestamp),
            duration: duration,
            source: source,
            audioFileName: audioFileName
        )
    }
}
