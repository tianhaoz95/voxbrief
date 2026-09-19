import Foundation

/// A single user-maintained "personal dictionary" entry: a jargon word, product name, or
/// person's name that Whisper `base.en` and the on-device LLM have no built-in knowledge of.
/// iOS-only (not in `Shared/Models`) -- dictionary terms are never watch-synced, only consumed
/// by the iOS-side processing pipeline (`ASRService`, `DictionaryCorrector`, `LLMCopywriterService`).
public struct DictionaryEntry: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    /// Canonical, correctly-spelled/capitalized form, e.g. "Voxbrief", "Kubernetes", "Priya Patel".
    public var term: String
    /// Known ASR mishearings of `term` (e.g. ["fox brief", "vox brief"]), used only by
    /// `DictionaryCorrector`'s deterministic substitution pass. May be empty.
    public var aliases: [String]
    public var createdAt: Date

    public init(id: UUID = UUID(), term: String, aliases: [String] = [], createdAt: Date = Date()) {
        self.id = id
        self.term = term
        self.aliases = aliases
        self.createdAt = createdAt
    }
}
