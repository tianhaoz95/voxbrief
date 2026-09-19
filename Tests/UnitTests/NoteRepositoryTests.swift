import XCTest
@testable import Voxbrief

@MainActor
final class NoteRepositoryTests: XCTestCase {
    
    var tempStorageURL: URL!
    var repository: NoteRepository!
    
    override func setUp() {
        super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
        tempStorageURL = tempDir.appendingPathComponent("test_notes_\(UUID().uuidString).json")
        repository = NoteRepository(customStorageURL: tempStorageURL)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempStorageURL)
        super.tearDown()
    }
    
    func testSaveAndRetrieveNote() {
        let note = VoiceNote(
            id: UUID(),
            createdAt: Date(),
            duration: 15.0,
            title: "Quick Idea",
            summary: "Testing repository persistence",
            rawTranscript: "this is raw transcript",
            cleanedNote: "# Quick Idea\n\nTesting persistence",
            status: .ready,
            source: .watchComplication
        )
        
        repository.save(note)
        
        let retrieved = repository.note(withId: note.id)
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.title, "Quick Idea")
        XCTAssertEqual(retrieved?.source, .watchComplication)
    }
    
    func testUpdateProcessingStatus() {
        let noteId = UUID()
        let note = VoiceNote(id: noteId, status: .syncing)
        repository.save(note)
        
        repository.updateStatus(for: noteId, status: .transcribingASR)
        XCTAssertEqual(repository.note(withId: noteId)?.status, .transcribingASR)
        
        repository.updateStatus(for: noteId, status: .cleaningLLM)
        XCTAssertEqual(repository.note(withId: noteId)?.status, .cleaningLLM)
        
        repository.updateStatus(for: noteId, status: .ready)
        XCTAssertEqual(repository.note(withId: noteId)?.status, .ready)
    }
    
    func testDeleteNote() {
        let note = VoiceNote(id: UUID())
        repository.save(note)
        XCTAssertNotNil(repository.note(withId: note.id))

        repository.delete(id: note.id)
        XCTAssertNil(repository.note(withId: note.id))
    }

    /// `VoiceNote.segments` was added after notes had already been persisted to disk; its inline
    /// `= []` default must let the synthesized `Decodable` fall back to empty for JSON missing the
    /// key entirely, rather than failing to decode a user's existing `notes_store.json`.
    func testLoadsLegacyNoteJSONMissingSegmentsField() {
        let noteId = UUID()
        let legacyJSON = """
        [
          {
            "id": "\(noteId.uuidString)",
            "createdAt": "2026-01-01T00:00:00Z",
            "duration": 12.5,
            "audioFileName": "legacy.m4a",
            "title": "Legacy Note",
            "summary": "",
            "rawTranscript": "legacy transcript",
            "cleanedNote": "",
            "requirements": [],
            "conditions": [],
            "actionItems": [],
            "tags": [],
            "status": "ready",
            "source": "phone_app",
            "isFavorite": false
          }
        ]
        """
        try! legacyJSON.write(to: tempStorageURL, atomically: true, encoding: .utf8)

        let legacyRepository = NoteRepository(customStorageURL: tempStorageURL)
        let loaded = legacyRepository.note(withId: noteId)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.segments, [])
        XCTAssertEqual(loaded?.rawTranscript, "legacy transcript")
    }

    func testDeleteRemovesAudioFilesForEverySegmentNotJustTheLatest() {
        let audioFileManager = AudioFileManager()
        let firstFile = audioFileManager.newAudioFileURL()
        let secondFile = audioFileManager.newAudioFileURL()
        FileManager.default.createFile(atPath: firstFile.path, contents: Data())
        FileManager.default.createFile(atPath: secondFile.path, contents: Data())
        defer {
            try? FileManager.default.removeItem(at: firstFile)
            try? FileManager.default.removeItem(at: secondFile)
        }

        let scopedRepository = NoteRepository(audioFileManager: audioFileManager, customStorageURL: tempStorageURL)
        let note = VoiceNote(
            id: UUID(),
            audioFileName: secondFile.lastPathComponent,
            segments: [
                NoteSegment(id: UUID(), audioFileName: firstFile.lastPathComponent, createdAt: Date(), duration: 5, source: .phoneApp, rawTranscript: "one"),
                NoteSegment(id: UUID(), audioFileName: secondFile.lastPathComponent, createdAt: Date(), duration: 5, source: .phoneApp, rawTranscript: "two")
            ],
            status: .ready
        )
        scopedRepository.save(note)

        scopedRepository.delete(id: note.id)

        XCTAssertFalse(FileManager.default.fileExists(atPath: firstFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondFile.path))
    }
}
