import Foundation

/// Persists the user's personal dictionary of jargon/proper-noun terms (see `DictionaryEntry`),
/// mirroring `NoteRepository`'s shape: `@MainActor` singleton, `@Published` in-memory array kept
/// in sync with a JSON file on every mutation, no migration layer.
@MainActor
public final class PersonalDictionaryStore: ObservableObject {
    public static let shared = PersonalDictionaryStore()

    @Published public private(set) var entries: [DictionaryEntry] = []

    private let storageURL: URL

    public init(customStorageURL: URL? = nil) {
        if let customStorageURL {
            self.storageURL = customStorageURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            if !FileManager.default.fileExists(atPath: appSupport.path) {
                try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            }
            self.storageURL = appSupport.appendingPathComponent("personal_dictionary.json")
        }

        loadEntries()
    }

    // MARK: - CRUD Operations

    @discardableResult
    public func add(term: String, aliases: [String] = [], contextHint: String? = nil) -> DictionaryEntry? {
        let trimmedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTerm.isEmpty else { return nil }
        let cleanedAliases = aliases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let entry = DictionaryEntry(term: trimmedTerm, aliases: cleanedAliases, contextHint: Self.cleanedHint(contextHint))
        entries.append(entry)
        sortAndPersist()
        return entry
    }

    public func update(_ entry: DictionaryEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        var updated = entry
        updated.term = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.aliases = entry.aliases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        updated.contextHint = Self.cleanedHint(entry.contextHint)
        guard !updated.term.isEmpty else { return }
        entries[index] = updated
        sortAndPersist()
    }

    /// Trims whitespace and collapses an all-blank hint to `nil`, so an empty text field never
    /// gets persisted as a hint that's just whitespace.
    private static func cleanedHint(_ hint: String?) -> String? {
        guard let trimmed = hint?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    public func delete(id: UUID) {
        entries.removeAll { $0.id == id }
        persist()
    }

    public func delete(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        persist()
    }

    // MARK: - Persistence

    private func sortAndPersist() {
        entries.sort { $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending }
        persist()
    }

    private func loadEntries() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loaded = try decoder.decode([DictionaryEntry].self, from: data)
            self.entries = loaded.sorted { $0.term.localizedCaseInsensitiveCompare($1.term) == .orderedAscending }
        } catch {
            print("[PersonalDictionaryStore] Failed to load entries: \(error)")
        }
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(entries)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[PersonalDictionaryStore] Failed to persist entries: \(error)")
        }
    }
}
