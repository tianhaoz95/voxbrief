import XCTest
@testable import Voxbrief

@MainActor
final class TemplateStoreTests: XCTestCase {

    var tempStorageURL: URL!
    var store: TemplateStore!

    override func setUp() {
        super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
        tempStorageURL = tempDir.appendingPathComponent("test_templates_\(UUID().uuidString).json")
        store = TemplateStore(customStorageURL: tempStorageURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempStorageURL)
        super.tearDown()
    }

    func testAllTemplatesIncludesBuiltInsAndCustom() {
        store.add(name: "Journal", summary: "A personal journal entry.", sections: [(title: "Entry", instructions: "", style: .paragraph)])

        XCTAssertEqual(store.allTemplates.count, NoteTemplate.builtIns.count + 1)
        XCTAssertTrue(store.allTemplates.contains(where: { $0.name == "Design Doc" }))
        XCTAssertTrue(store.allTemplates.contains(where: { $0.name == "Journal" }))
    }

    func testAddCreatesTemplateWithDerivedFieldKeys() {
        let template = store.add(
            name: "Meeting Notes",
            summary: "Notes from a meeting.",
            sections: [(title: "Attendees", instructions: "Who was there.", style: .bullet), (title: "Action Items", instructions: "Follow-ups.", style: .checklist)]
        )

        XCTAssertNotNil(template)
        XCTAssertEqual(template?.sections.count, 2)
        XCTAssertEqual(template?.sections[0].fieldKey, "attendees")
        XCTAssertEqual(template?.sections[1].fieldKey, "actionItems")
        XCTAssertEqual(store.customTemplates.count, 1)
    }

    func testAddRejectsEmptyName() {
        let template = store.add(name: "   ", summary: "", sections: [(title: "Notes", instructions: "", style: .paragraph)])

        XCTAssertNil(template)
        XCTAssertTrue(store.customTemplates.isEmpty)
    }

    func testAddRejectsNoNamedSections() {
        let template = store.add(name: "Empty Template", summary: "", sections: [(title: "  ", instructions: "", style: .paragraph)])

        XCTAssertNil(template)
        XCTAssertTrue(store.customTemplates.isEmpty)
    }

    func testAddDedupesCollidingFieldKeys() {
        let template = store.add(
            name: "Duplicate Sections",
            summary: "",
            sections: [(title: "Notes", instructions: "", style: .paragraph), (title: "Notes", instructions: "", style: .paragraph)]
        )

        XCTAssertEqual(template?.sections.map(\.fieldKey), ["notes", "notes2"])
    }

    func testAddRejectsCollisionAgainstReservedKeys() {
        let template = store.add(name: "Weird Template", summary: "", sections: [(title: "Title", instructions: "", style: .paragraph)])

        // "Title" slugifies to "title", which collides with the reserved universal key -- gets
        // de-duplicated to "title2" rather than silently colliding with the universal field.
        XCTAssertEqual(template?.sections.first?.fieldKey, "title2")
    }

    func testUpdateModifiesExistingCustomTemplate() {
        let template = store.add(name: "Journal", summary: "Old summary", sections: [(title: "Entry", instructions: "", style: .paragraph)])!

        var updated = template
        updated.name = "Daily Journal"
        updated.summary = "New summary"
        store.update(updated)

        XCTAssertEqual(store.customTemplates.first?.name, "Daily Journal")
        XCTAssertEqual(store.customTemplates.first?.summary, "New summary")
    }

    func testUpdateNoOpsForBuiltIn() {
        var designDoc = NoteTemplate.designDoc
        designDoc.name = "Hacked Name"
        store.update(designDoc)

        XCTAssertTrue(store.customTemplates.isEmpty, "Updating a built-in should never add it to customTemplates")
        XCTAssertEqual(NoteTemplate.designDoc.name, "Design Doc", "The built-in constant itself must be unaffected")
    }

    func testDeleteRemovesCustomTemplate() {
        let template = store.add(name: "Journal", summary: "", sections: [(title: "Entry", instructions: "", style: .paragraph)])!

        store.delete(id: template.id)

        XCTAssertTrue(store.customTemplates.isEmpty)
    }

    func testDeleteNoOpsForBuiltIn() {
        store.delete(id: NoteTemplate.designDoc.id)

        // Nothing to assert on customTemplates changing (it was already empty) -- this mainly
        // proves the call doesn't crash or affect NoteTemplate.builtIns.
        XCTAssertEqual(NoteTemplate.builtIns.count, 5)
    }

    func testDeleteAtOffsetsOnlyAffectsCustom() {
        store.add(name: "Alpha", summary: "", sections: [(title: "Notes", instructions: "", style: .paragraph)])
        store.add(name: "Beta", summary: "", sections: [(title: "Notes", instructions: "", style: .paragraph)])

        store.delete(at: IndexSet(integer: 0))

        XCTAssertEqual(store.customTemplates.count, 1)
    }

    func testCustomTemplatesAreSortedCaseInsensitively() {
        store.add(name: "zebra", summary: "", sections: [(title: "Notes", instructions: "", style: .paragraph)])
        store.add(name: "Apple", summary: "", sections: [(title: "Notes", instructions: "", style: .paragraph)])

        XCTAssertEqual(store.customTemplates.map(\.name), ["Apple", "zebra"])
    }

    func testPersistenceAcrossFreshStoreInstance() {
        store.add(name: "Journal", summary: "A personal journal entry.", sections: [(title: "Entry", instructions: "", style: .paragraph)])

        let reloaded = TemplateStore(customStorageURL: tempStorageURL)

        XCTAssertEqual(reloaded.customTemplates.count, 1)
        XCTAssertEqual(reloaded.customTemplates.first?.name, "Journal")
    }

    /// Mirrors `PersonalDictionaryStoreTests.testLoadsLegacyEntryJSONMissingContextHintField` --
    /// documents the pattern this whole redesign leans on for `VoiceNote`: any field added to
    /// `NoteTemplate` later must be `Optional` (or otherwise handled via a hand-written
    /// `init(from:)`) so old `custom_templates.json` files missing the new key still decode.
    /// Nothing on `NoteTemplate` is optional yet, so this currently just proves a fully-populated
    /// legacy-shaped JSON round-trips correctly -- update it if an optional field is ever added.
    func testLoadsCustomTemplateJSON() {
        let templateId = UUID()
        let sectionId = UUID()
        let legacyJSON = """
        [
          {
            "id": "\(templateId.uuidString)",
            "name": "Journal",
            "summary": "A personal journal entry.",
            "isBuiltIn": false,
            "createdAt": "2026-01-01T00:00:00Z",
            "sections": [
              {
                "id": "\(sectionId.uuidString)",
                "fieldKey": "entry",
                "title": "Entry",
                "instructions": "",
                "style": "paragraph"
              }
            ]
          }
        ]
        """
        try! legacyJSON.write(to: tempStorageURL, atomically: true, encoding: .utf8)

        let loadedStore = TemplateStore(customStorageURL: tempStorageURL)

        XCTAssertEqual(loadedStore.customTemplates.count, 1)
        XCTAssertEqual(loadedStore.customTemplates.first?.name, "Journal")
        XCTAssertEqual(loadedStore.customTemplates.first?.sections.first?.fieldKey, "entry")
    }
}
