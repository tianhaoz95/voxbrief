import Foundation

/// Represents the origin of a voice note capture
public enum NoteSource: String, Codable, CaseIterable, Sendable {
    case watchComplication = "watch_complication"
    case watchLiveActivity = "watch_live_activity"
    case watchApp = "watch_app"
    case phoneApp = "phone_app"
    case macApp = "mac_app"

    public var displayName: String {
        switch self {
        case .watchComplication: return "Watch Complication"
        case .watchLiveActivity: return "Watch Live Activity"
        case .watchApp: return "Apple Watch"
        case .phoneApp: return "iPhone"
        case .macApp: return "Mac"
        }
    }

    public var iconName: String {
        switch self {
        case .watchComplication: return "applewatch.radiowaves.left.and.right"
        case .watchLiveActivity: return "waveform.badge.magnifyingglass"
        case .watchApp: return "applewatch"
        case .phoneApp: return "iphone"
        case .macApp: return "macbook"
        }
    }
}

/// Pipeline processing status of a voice note
public enum NoteProcessingStatus: String, Codable, Sendable, CaseIterable {
    case recordedOnWatch = "recorded_on_watch"
    case syncing = "syncing"
    case transcribingASR = "transcribing_asr"
    case cleaningLLM = "cleaning_llm"
    case ready = "ready"
    case failed = "failed"
    
    public var stepDescription: String {
        switch self {
        case .recordedOnWatch: return "Saved on Watch"
        case .syncing: return "Syncing to iPhone..."
        case .transcribingASR: return "Stage 1: Speech-to-Text (ASR)..."
        case .cleaningLLM: return "Stage 2: LLM Copywriting & Structure..."
        case .ready: return "Processed & Ready"
        case .failed: return "Processing Failed"
        }
    }
    
    public var isProcessing: Bool {
        switch self {
        case .syncing, .transcribingASR, .cleaningLLM:
            return true
        case .recordedOnWatch, .ready, .failed:
            return false
        }
    }

    /// SF Symbol representing this stage, for live-progress UI (e.g. the reprocessing indicator
    /// in `NoteDetailView`).
    public var iconName: String {
        switch self {
        case .recordedOnWatch: return "applewatch"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .transcribingASR: return "waveform"
        case .cleaningLLM: return "sparkles"
        case .ready: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}

/// One recording session folded into a `VoiceNote`. A note always has at least one segment once
/// Stage 1 (ASR) has produced a transcript for it; a plain single-recording note simply has one.
/// Appending a further recording (see `NoteProcessingPipeline.appendRecording`/`mergeNote`) adds
/// another segment and re-runs Stage 2 over all of them together, so the LLM always sees the
/// note's full history rather than just the newest snippet.
public struct NoteSegment: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let audioFileName: String
    public let createdAt: Date
    public let duration: TimeInterval
    public let source: NoteSource
    public var rawTranscript: String

    public init(id: UUID, audioFileName: String, createdAt: Date, duration: TimeInterval, source: NoteSource, rawTranscript: String) {
        self.id = id
        self.audioFileName = audioFileName
        self.createdAt = createdAt
        self.duration = duration
        self.source = source
        self.rawTranscript = rawTranscript
    }
}

/// Complete Voice Note model containing raw audio metadata, ASR transcript, and LLM-processed note
public struct VoiceNote: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var createdAt: Date
    public var duration: TimeInterval
    public var audioFileName: String?

    /// Ordered oldest -> newest. Populated once Stage 1 produces this note's first transcript;
    /// empty for a note still mid-sync/ASR, and for notes persisted before this field existed --
    /// `init(from:)` below decodes it with `decodeIfPresent(...) ?? []` specifically so old
    /// `notes_store.json` files missing this key still decode instead of failing outright (a
    /// synthesized `Decodable` would require the key to be present for a non-Optional property,
    /// inline default or not). See `NoteProcessingPipeline`'s `legacySegment(from:)` for how call
    /// sites reconstruct a single segment from the top-level fields when this is empty.
    public var segments: [NoteSegment] = []

    // Extracted and generated content
    public var title: String
    public var summary: String
    public var rawTranscript: String
    public var cleanedNote: String
    
    // Structured extractions from LLM stage
    public var requirements: [String]
    public var conditions: [String]
    public var actionItems: [String]
    public var tags: [String]
    
    // Metadata & Pipeline Status
    public var status: NoteProcessingStatus
    public var source: NoteSource
    public var isFavorite: Bool
    public var errorMessage: String?

    /// Human-readable label for whichever Stage 2 engine actually produced this note's cleanup
    /// (e.g. "On-Device LLM (Qwen3-0.6B)", "Ollama", or the rule-based fallback's label) --
    /// `nil` for notes processed before this field existed. Lets the UI show the user when the
    /// preferred engine wasn't available instead of silently degrading to the rule-based
    /// transformer with no indication anything less than the real LLM ran.
    public var cleanupEngine: String?

    /// Stage 2's "light" rewrite: typos/grammar/filler words fixed, but original wording and
    /// sentence order preserved -- no requirements/conditions/action-item restructuring. Kept
    /// alongside `cleanedNote` (the structured "full" rewrite) so the UI can offer both. `nil`
    /// for notes processed before this field existed, or if the light pass failed.
    public var lightCleanedNote: String?
    public var lightCleanupEngine: String?

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        audioFileName: String? = nil,
        segments: [NoteSegment] = [],
        title: String = "Untitled Note",
        summary: String = "",
        rawTranscript: String = "",
        cleanedNote: String = "",
        requirements: [String] = [],
        conditions: [String] = [],
        actionItems: [String] = [],
        tags: [String] = [],
        status: NoteProcessingStatus = .ready,
        source: NoteSource = .phoneApp,
        isFavorite: Bool = false,
        errorMessage: String? = nil,
        cleanupEngine: String? = nil,
        lightCleanedNote: String? = nil,
        lightCleanupEngine: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.audioFileName = audioFileName
        self.segments = segments
        self.title = title
        self.summary = summary
        self.rawTranscript = rawTranscript
        self.cleanedNote = cleanedNote
        self.requirements = requirements
        self.conditions = conditions
        self.actionItems = actionItems
        self.tags = tags
        self.status = status
        self.source = source
        self.isFavorite = isFavorite
        self.errorMessage = errorMessage
        self.cleanupEngine = cleanupEngine
        self.lightCleanedNote = lightCleanedNote
        self.lightCleanupEngine = lightCleanupEngine
    }

    /// Hand-written (rather than relying on synthesized `Decodable`) solely so `segments` can use
    /// `decodeIfPresent(...) ?? []` -- every other field decodes exactly as synthesis would.
    /// `Encodable`'s `encode(to:)` is still compiler-synthesized as usual.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        audioFileName = try container.decodeIfPresent(String.self, forKey: .audioFileName)
        segments = try container.decodeIfPresent([NoteSegment].self, forKey: .segments) ?? []
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decode(String.self, forKey: .summary)
        rawTranscript = try container.decode(String.self, forKey: .rawTranscript)
        cleanedNote = try container.decode(String.self, forKey: .cleanedNote)
        requirements = try container.decode([String].self, forKey: .requirements)
        conditions = try container.decode([String].self, forKey: .conditions)
        actionItems = try container.decode([String].self, forKey: .actionItems)
        tags = try container.decode([String].self, forKey: .tags)
        status = try container.decode(NoteProcessingStatus.self, forKey: .status)
        source = try container.decode(NoteSource.self, forKey: .source)
        isFavorite = try container.decode(Bool.self, forKey: .isFavorite)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
        cleanupEngine = try container.decodeIfPresent(String.self, forKey: .cleanupEngine)
        lightCleanedNote = try container.decodeIfPresent(String.self, forKey: .lightCleanedNote)
        lightCleanupEngine = try container.decodeIfPresent(String.self, forKey: .lightCleanupEngine)
    }
}
