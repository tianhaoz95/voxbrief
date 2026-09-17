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
}
