import XCTest
@testable import Voxbrief

final class DictionaryCorrectorTests: XCTestCase {

    func testReplacesAliasWithCanonicalTerm() {
        let entries = [DictionaryEntry(term: "Voxbrief", aliases: ["fox brief"])]

        let result = DictionaryCorrector.apply(to: "Let's discuss fox brief today.", entries: entries)

        XCTAssertEqual(result, "Let's discuss Voxbrief today.")
    }

    func testReplacementIsCaseInsensitive() {
        let entries = [DictionaryEntry(term: "Voxbrief", aliases: ["fox brief"])]

        let result = DictionaryCorrector.apply(to: "FOX BRIEF is the app name.", entries: entries)

        XCTAssertEqual(result, "Voxbrief is the app name.")
    }

    func testReplacementRespectsWholeWordBoundaries() {
        let entries = [DictionaryEntry(term: "AI", aliases: ["ay"])]

        let result = DictionaryCorrector.apply(to: "The bay area team met today.", entries: entries)

        XCTAssertEqual(result, "The bay area team met today.", "Should not corrupt substrings of other words")
    }

    func testMultiWordAliasIsReplaced() {
        let entries = [DictionaryEntry(term: "Kubernetes", aliases: ["cooper netties"])]

        let result = DictionaryCorrector.apply(to: "We migrated to cooper netties last week.", entries: entries)

        XCTAssertEqual(result, "We migrated to Kubernetes last week.")
    }

    func testEntryWithNoAliasesIsNoOp() {
        let entries = [DictionaryEntry(term: "Voxbrief", aliases: [])]

        let result = DictionaryCorrector.apply(to: "Voxbrief is great.", entries: entries)

        XCTAssertEqual(result, "Voxbrief is great.")
    }

    func testEmptyEntriesIsNoOp() {
        let result = DictionaryCorrector.apply(to: "Some transcript text.", entries: [])

        XCTAssertEqual(result, "Some transcript text.")
    }

    func testTermContainingRegexSpecialCharactersRoundTripsLiterally() {
        let entries = [DictionaryEntry(term: "Price is $5\\month", aliases: ["dollar month"])]

        let result = DictionaryCorrector.apply(to: "The plan is dollar month.", entries: entries)

        XCTAssertEqual(result, "The plan is Price is $5\\month.")
    }

    func testCorrectionIsIdempotent() {
        let entries = [DictionaryEntry(term: "Voxbrief", aliases: ["fox brief"])]

        let once = DictionaryCorrector.apply(to: "fox brief is the app.", entries: entries)
        let twice = DictionaryCorrector.apply(to: once, entries: entries)

        XCTAssertEqual(once, twice)
    }
}
