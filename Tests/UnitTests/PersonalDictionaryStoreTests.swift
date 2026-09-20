import XCTest
@testable import Voxbrief

@MainActor
final class PersonalDictionaryStoreTests: XCTestCase {

    var tempStorageURL: URL!
    var store: PersonalDictionaryStore!

    override func setUp() {
        super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
        tempStorageURL = tempDir.appendingPathComponent("test_dictionary_\(UUID().uuidString).json")
        store = PersonalDictionaryStore(customStorageURL: tempStorageURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempStorageURL)
        super.tearDown()
    }

    func testAddCreatesEntry() {
        let entry = store.add(term: "Voxbrief", aliases: ["fox brief", "vox brief"])

        XCTAssertNotNil(entry)
        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.term, "Voxbrief")
        XCTAssertEqual(store.entries.first?.aliases, ["fox brief", "vox brief"])
    }

    func testAddRejectsEmptyOrWhitespaceTerm() {
        XCTAssertNil(store.add(term: ""))
        XCTAssertNil(store.add(term: "   "))
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testAddFiltersEmptyAliases() {
        store.add(term: "Kubernetes", aliases: ["", "  ", "koob-ernetties"])

        XCTAssertEqual(store.entries.first?.aliases, ["koob-ernetties"])
    }

    func testAddTrimsContextHintAndTreatsBlankAsNil() {
        let withHint = store.add(term: "Voxbrief", contextHint: "  our project's codename  ")
        let withBlankHint = store.add(term: "Kubernetes", contextHint: "   ")

        XCTAssertEqual(withHint?.contextHint, "our project's codename")
        XCTAssertNil(withBlankHint?.contextHint)
    }

    func testUpdateModifiesExistingEntry() {
        let entry = store.add(term: "Voxbrief")!

        var updated = entry
        updated.term = "VoxBrief"
        updated.aliases = ["vox brief"]
        store.update(updated)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.term, "VoxBrief")
        XCTAssertEqual(store.entries.first?.aliases, ["vox brief"])
    }

    func testUpdateWithEmptyTermIsIgnored() {
        let entry = store.add(term: "Voxbrief")!

        var updated = entry
        updated.term = "   "
        store.update(updated)

        XCTAssertEqual(store.entries.first?.term, "Voxbrief", "Update with an empty term should be a no-op")
    }

    func testDeleteById() {
        let entry = store.add(term: "Voxbrief")!
        store.add(term: "Kubernetes")

        store.delete(id: entry.id)

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entries.first?.term, "Kubernetes")
    }

    func testDeleteAtOffsets() {
        store.add(term: "Alpha")
        store.add(term: "Beta")

        store.delete(at: IndexSet(integer: 0))

        XCTAssertEqual(store.entries.count, 1)
    }

    func testEntriesAreSortedCaseInsensitively() {
        store.add(term: "zebra")
        store.add(term: "Apple")
        store.add(term: "banana")

        XCTAssertEqual(store.entries.map(\.term), ["Apple", "banana", "zebra"])
    }

    /// `DictionaryEntry.contextHint` was added after entries had already been persisted to disk.
    /// Being `Optional` (unlike `VoiceNote.segments`, which needed a hand-written `init(from:)`),
    /// the synthesized `Decodable` should already fall back to `nil` for JSON missing the key.
    func testLoadsLegacyEntryJSONMissingContextHintField() {
        let entryId = UUID()
        let legacyJSON = """
        [
          {
            "id": "\(entryId.uuidString)",
            "term": "Voxbrief",
            "aliases": ["fox brief"],
            "createdAt": "2026-01-01T00:00:00Z"
          }
        ]
        """
        try! legacyJSON.write(to: tempStorageURL, atomically: true, encoding: .utf8)

        let legacyStore = PersonalDictionaryStore(customStorageURL: tempStorageURL)

        XCTAssertEqual(legacyStore.entries.count, 1)
        XCTAssertEqual(legacyStore.entries.first?.term, "Voxbrief")
        XCTAssertNil(legacyStore.entries.first?.contextHint)
    }

    func testPersistenceAcrossFreshStoreInstance() {
        store.add(term: "Voxbrief", aliases: ["fox brief"])

        let reloaded = PersonalDictionaryStore(customStorageURL: tempStorageURL)

        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertEqual(reloaded.entries.first?.term, "Voxbrief")
        XCTAssertEqual(reloaded.entries.first?.aliases, ["fox brief"])
    }
}
