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

    func testPersistenceAcrossFreshStoreInstance() {
        store.add(term: "Voxbrief", aliases: ["fox brief"])

        let reloaded = PersonalDictionaryStore(customStorageURL: tempStorageURL)

        XCTAssertEqual(reloaded.entries.count, 1)
        XCTAssertEqual(reloaded.entries.first?.term, "Voxbrief")
        XCTAssertEqual(reloaded.entries.first?.aliases, ["fox brief"])
    }
}
