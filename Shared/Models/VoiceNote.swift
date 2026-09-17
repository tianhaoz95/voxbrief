import Foundation

/// Represents the origin of a voice note capture
public enum NoteSource: String, Codable, CaseIterable, Sendable {
    case watchComplication = "watch_complication"
    case watchLiveActivity = "watch_live_activity"
    case watchApp = "watch_app"
    case phoneApp = "phone_app"
    
    public var displayName: String {
        switch self {
        case .watchComplication: return "Watch Complication"
        case .watchLiveActivity: return "Watch Live Activity"
        case .watchApp: return "Apple Watch"
        case .phoneApp: return "iPhone"
        }
    }
    
    public var iconName: String {
        switch self {
        case .watchComplication: return "applewatch.radiowaves.left.and.right"
        case .watchLiveActivity: return "waveform.badge.magnifyingglass"
        case .watchApp: return "applewatch"
        case .phoneApp: return "iphone"
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
}

/// Complete Voice Note model containing raw audio metadata, ASR transcript, and LLM-processed note
public struct VoiceNote: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var createdAt: Date
    public var duration: TimeInterval
    public var audioFileName: String?
    
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
}
