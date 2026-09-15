import XCTest
@testable import VoiceNote

final class WatchSyncServiceTests: XCTestCase {
    
    func testSyncPayloadDictionarySerialization() {
        let noteId = UUID()
        let now = Date()
        let payload = WatchSyncPayload(
            noteId: noteId,
            createdAt: now,
            duration: 25.4,
            source: .watchComplication,
            audioFileName: "\(noteId.uuidString).m4a"
        )
        
        let dict = payload.dictionaryRepresentation
        XCTAssertEqual(dict[SyncConstants.keyAction] as? String, SyncConstants.actionAudioTransfer)
        XCTAssertEqual(dict[SyncConstants.keyNoteId] as? String, noteId.uuidString)
        XCTAssertEqual(dict[SyncConstants.keySource] as? String, NoteSource.watchComplication.rawValue)
        
        // Deserialize back
        let restored = WatchSyncPayload.from(dictionary: dict)
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.noteId, noteId)
        XCTAssertEqual(restored?.duration, 25.4)
        XCTAssertEqual(restored?.source, .watchComplication)
        XCTAssertEqual(restored?.audioFileName, "\(noteId.uuidString).m4a")
    }
}
