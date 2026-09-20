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
    /// Optional short description of what `term` actually is (e.g. "our project's codename" or
    /// "a person on the team, not a typo"). Consumed only by `LLMCopywriterService`'s Stage 2
    /// prompt -- never by `DictionaryCorrector`'s plain string substitution, and never folded into
    /// `ASRService`'s Stage 1 vocabulary bias, which works better with bare terms than prose. Lets
    /// the LLM judge whether an ambiguous or unfamiliar-looking term actually fits the surrounding
    /// sentence instead of just matching spelling. `nil` for entries added before this existed, or
    /// left blank -- most terms don't need one.
    public var contextHint: String?
    public var createdAt: Date

    public init(id: UUID = UUID(), term: String, aliases: [String] = [], contextHint: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.term = term
        self.aliases = aliases
        self.contextHint = contextHint
        self.createdAt = createdAt
    }
}
