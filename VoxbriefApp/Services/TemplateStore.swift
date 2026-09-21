import Foundation

/// Persists the user's custom Stage 2 output templates (see `NoteTemplate`), mirroring
/// `PersonalDictionaryStore`'s shape: `@MainActor` singleton, `@Published` in-memory array kept
/// in sync with a JSON file on every mutation, no migration layer. Built-in templates
/// (`NoteTemplate.builtIns`) are compiled-in and never touch this file -- only user-created ones
/// are persisted here.
@MainActor
public final class TemplateStore: ObservableObject {
    public static let shared = TemplateStore()

    /// Reserved -- every generation prompt always includes these as universal keys (see
    /// `LLMCopywriterService.buildGenerationSystemPrompt`), so a custom section can't also claim
    /// one of them.
    private static let reservedFieldKeys: Set<String> = ["title", "summary", "tags"]

    @Published public private(set) var customTemplates: [NoteTemplate] = []
    /// IDs (built-in or custom) the user has opted out of -- `enabledTemplates` is what
    /// `NoteProcessingPipeline` actually offers the LLM for classification, so disabling a
    /// template here means it never appears in a classification prompt at all, not just that the
    /// LLM is told to avoid it.
    @Published public private(set) var disabledTemplateIDs: Set<UUID> = []

    private let storageURL: URL

    public init(customStorageURL: URL? = nil) {
        if let customStorageURL {
            self.storageURL = customStorageURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            if !FileManager.default.fileExists(atPath: appSupport.path) {
                try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            }
            self.storageURL = appSupport.appendingPathComponent("custom_templates.json")
        }

        loadTemplates()
    }

    /// Built-in templates first, then custom ones -- the order the LLM sees them in classification
    /// prompts and the order they're listed in `TemplatesView`.
    public var allTemplates: [NoteTemplate] {
        NoteTemplate.builtIns + customTemplates
    }

    /// `allTemplates` minus anything the user disabled -- this, not `allTemplates`, is what
    /// `NoteProcessingPipeline` passes to `LLMCopywriterService` for classification, so a
    /// disabled template's name/summary never even enters the prompt. Falls back to
    /// `allTemplates` if disabling somehow left nothing enabled (shouldn't happen given
    /// `setEnabled`'s own guard, but the LLM always needs at least one candidate).
    public var enabledTemplates: [NoteTemplate] {
        let enabled = allTemplates.filter { !disabledTemplateIDs.contains($0.id) }
        return enabled.isEmpty ? allTemplates : enabled
    }

    public func isEnabled(_ template: NoteTemplate) -> Bool {
        !disabledTemplateIDs.contains(template.id)
    }

    /// Toggles whether a template (built-in or custom) is offered to the LLM. Refuses to disable
    /// the last remaining enabled template or an unknown ID, so there's always at least one
    /// candidate for classification to choose from.
    public func setEnabled(_ enabled: Bool, for templateId: UUID) {
        guard allTemplates.contains(where: { $0.id == templateId }) else { return }
        if enabled {
            guard disabledTemplateIDs.remove(templateId) != nil else { return }
        } else {
            let remainingEnabled = allTemplates.filter { $0.id != templateId && !disabledTemplateIDs.contains($0.id) }
            guard !remainingEnabled.isEmpty else { return }
            disabledTemplateIDs.insert(templateId)
        }
        persist()
    }

    // MARK: - CRUD Operations

    /// `sections` are supplied as (title, instructions, style) tuples -- `fieldKey` is never
    /// user-entered, it's derived here from each section's title (see `Self.fieldKey(for:existingKeys:)`).
    @discardableResult
    public func add(name: String, summary: String, sections: [(title: String, instructions: String, style: TemplateSectionStyle)]) -> NoteTemplate? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        let builtSections = Self.buildSections(from: sections)
        guard !builtSections.isEmpty else { return nil }

        let template = NoteTemplate(
            name: trimmedName,
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            sections: builtSections,
            isBuiltIn: false
        )
        customTemplates.append(template)
        sortAndPersist()
        return template
    }

    /// No-ops for a built-in template (`template.isBuiltIn == true`) -- those are compiled-in and
    /// never editable. `sections` are re-derived from scratch the same way `add` does, so editing
    /// a section's title re-slugs its `fieldKey` too.
    public func update(_ template: NoteTemplate) {
        guard !template.isBuiltIn, let index = customTemplates.firstIndex(where: { $0.id == template.id }) else { return }
        let trimmedName = template.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let rebuiltSections = Self.buildSections(from: template.sections.map { ($0.title, $0.instructions, $0.style) })
        guard !rebuiltSections.isEmpty else { return }

        var updated = template
        updated.name = trimmedName
        updated.summary = template.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.sections = rebuiltSections
        customTemplates[index] = updated
        sortAndPersist()
    }

    /// No-ops for a built-in template's ID -- there's nothing in `customTemplates` to remove.
    public func delete(id: UUID) {
        customTemplates.removeAll { $0.id == id }
        disabledTemplateIDs.remove(id)
        persist()
    }

    /// Offsets are scoped to `customTemplates` (the only array `TemplatesView`'s `.onDelete`
    /// applies to) -- built-in rows never appear in a `ForEach` this is attached to.
    public func delete(at offsets: IndexSet) {
        for id in offsets.compactMap({ customTemplates.indices.contains($0) ? customTemplates[$0].id : nil }) {
            disabledTemplateIDs.remove(id)
        }
        customTemplates.remove(atOffsets: offsets)
        persist()
    }

    // MARK: - Field key derivation

    /// Turns each (title, instructions, style) into a `TemplateSection` with an auto-derived,
    /// de-duplicated `fieldKey` -- skips any entry whose title is blank (an empty "Add Section"
    /// row the user never filled in).
    private static func buildSections(from sections: [(title: String, instructions: String, style: TemplateSectionStyle)]) -> [TemplateSection] {
        var usedKeys = reservedFieldKeys
        var result: [TemplateSection] = []
        for entry in sections {
            let trimmedTitle = entry.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else { continue }
            let key = fieldKey(for: trimmedTitle, existingKeys: usedKeys)
            usedKeys.insert(key)
            result.append(TemplateSection(
                fieldKey: key,
                title: trimmedTitle,
                instructions: entry.instructions.trimmingCharacters(in: .whitespacesAndNewlines),
                style: entry.style
            ))
        }
        return result
    }

    /// Slugifies a section title into a lowerCamelCase JSON key (e.g. "Action Items" ->
    /// "actionItems"), then de-duplicates against `existingKeys` (including the reserved
    /// universal ones) by appending "2", "3", ... on collision.
    private static func fieldKey(for title: String, existingKeys: Set<String>) -> String {
        let words = title
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let base: String
        if words.isEmpty {
            base = "section"
        } else {
            let first = words[0].lowercased()
            let rest = words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            base = ([first] + rest).joined()
        }

        guard existingKeys.contains(base) else { return base }
        var suffix = 2
        while existingKeys.contains("\(base)\(suffix)") {
            suffix += 1
        }
        return "\(base)\(suffix)"
    }

    // MARK: - Persistence

    /// On-disk shape as of per-template enable/disable. Older installs' `custom_templates.json`
    /// is just a bare `[NoteTemplate]` array (no disabled-IDs concept existed yet) -- `loadTemplates`
    /// tries this shape first and falls back to the bare-array shape, so an existing file loads
    /// exactly as before with everything defaulting to enabled, rather than getting wiped.
    private struct PersistedData: Codable {
        var customTemplates: [NoteTemplate]
        var disabledTemplateIDs: [UUID]
    }

    private func sortAndPersist() {
        customTemplates.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        persist()
    }

    private func loadTemplates() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            if let persisted = try? decoder.decode(PersistedData.self, from: data) {
                self.customTemplates = persisted.customTemplates.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                self.disabledTemplateIDs = Set(persisted.disabledTemplateIDs)
                return
            }

            // Legacy format, from before per-template enable/disable existed.
            let legacy = try decoder.decode([NoteTemplate].self, from: data)
            self.customTemplates = legacy.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            print("[TemplateStore] Failed to load custom templates: \(error)")
        }
    }

    private func persist() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let payload = PersistedData(customTemplates: customTemplates, disabledTemplateIDs: Array(disabledTemplateIDs))
            let data = try encoder.encode(payload)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[TemplateStore] Failed to persist custom templates: \(error)")
        }
    }
}
