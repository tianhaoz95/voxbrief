import XCTest
@testable import Voxbrief

@MainActor
final class NoteListViewModelTests: XCTestCase {

    var tempStorageURL: URL!
    var repository: NoteRepository!
    var viewModel: NoteListViewModel!

    override func setUp() {
        super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
        tempStorageURL = tempDir.appendingPathComponent("test_notes_\(UUID().uuidString).json")
        repository = NoteRepository(customStorageURL: tempStorageURL)
        viewModel = NoteListViewModel(repository: repository)
        // NoteRepository seeds sample notes when its store is empty; clear them so
        // these tests only ever see the notes they explicitly create.
        for note in repository.notes {
            repository.delete(id: note.id)
        }
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempStorageURL)
        super.tearDown()
    }

    func testSearchMatchesTags() {
        let note = VoiceNote(id: UUID(), title: "Untitled", summary: "", rawTranscript: "", cleanedNote: "", tags: ["#watchOS"])
        repository.save(note)

        viewModel.searchText = "watchos"
        XCTAssertEqual(viewModel.notes.count, 1, "Search should match against tags case-insensitively")
    }

    func testSearchMatchesRequirementsAndActionItems() {
        let note = VoiceNote(
            id: UUID(),
            title: "Untitled",
            summary: "",
            rawTranscript: "",
            cleanedNote: "",
            requirements: ["Support biometric login"],
            actionItems: ["Check with the security team"]
        )
        repository.save(note)

        viewModel.searchText = "biometric"
        XCTAssertEqual(viewModel.notes.count, 1, "Search should match against requirement text")

        viewModel.searchText = "security team"
        XCTAssertEqual(viewModel.notes.count, 1, "Search should match against action item text")

        viewModel.searchText = "nonexistent phrase"
        XCTAssertTrue(viewModel.notes.isEmpty, "Search should exclude notes with no matching field")
    }
}
