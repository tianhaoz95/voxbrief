import Foundation
import Combine

@MainActor
public final class NoteRepository: ObservableObject {
    public static let shared = NoteRepository()
    
    @Published public private(set) var notes: [VoiceNote] = []
    
    private let storageURL: URL
    private let audioFileManager: AudioFileManager
    
    public init(audioFileManager: AudioFileManager = .shared, customStorageURL: URL? = nil) {
        self.audioFileManager = audioFileManager
        if let customURL = customStorageURL {
            self.storageURL = customURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            if !FileManager.default.fileExists(atPath: appSupport.path) {
                try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
            }
            self.storageURL = appSupport.appendingPathComponent("notes_store.json")
        }
        
        loadNotes()
        
        if notes.isEmpty {
            seedSampleNotesIfEmpty()
        }
    }
    
    // MARK: - CRUD Operations
    
    public func save(_ note: VoiceNote) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        } else {
            notes.insert(note, at: 0)
        }
        persistNotes()
    }
    
    public func updateStatus(for noteId: UUID, status: NoteProcessingStatus, errorMessage: String? = nil) {
        guard let index = notes.firstIndex(where: { $0.id == noteId }) else { return }
        notes[index].status = status
        if let errorMessage = errorMessage {
            notes[index].errorMessage = errorMessage
        }
        persistNotes()
    }
    
    public func delete(id: UUID) {
        if let index = notes.firstIndex(where: { $0.id == id }) {
            let note = notes[index]
            var fileNames = Set(note.segments.map(\.audioFileName))
            if let audioFileName = note.audioFileName {
                fileNames.insert(audioFileName)
            }
            for fileName in fileNames where !fileName.isEmpty {
                audioFileManager.deleteAudioFile(fileName: fileName)
            }
            notes.remove(at: index)
            persistNotes()
        }
    }

    /// Removes a note's record without touching its audio files on disk -- used when merging one
    /// note's recording(s) into another (`NoteProcessingPipeline.mergeNote`), where the target
    /// note's `segments` now reference those same files.
    public func removeRecordOnly(id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes.remove(at: index)
        persistNotes()
    }
    
    public func toggleFavorite(id: UUID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].isFavorite.toggle()
        persistNotes()
    }
    
    public func note(withId id: UUID) -> VoiceNote? {
        return notes.first(where: { $0.id == id })
    }
    
    // MARK: - Persistence
    
    private func loadNotes() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let loaded = try decoder.decode([VoiceNote].self, from: data)
            self.notes = loaded.sorted(by: { $0.createdAt > $1.createdAt })
        } catch {
            print("[NoteRepository] Failed to load notes: \(error)")
        }
    }
    
    private func persistNotes() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(notes)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[NoteRepository] Failed to persist notes: \(error)")
        }
    }
    
    // MARK: - Sample Data
    
    private func seedSampleNotesIfEmpty() {
        let sample1 = VoiceNote(
            id: UUID(),
            createdAt: Date().addingTimeInterval(-3600 * 3),
            duration: 42.0,
            audioFileName: nil,
            title: "Voice Note Architecture & Live Activity",
            summary: "Capture voice ideas instantly from Apple Watch complications and Live Activity, then sync to iOS for ASR and on-device LLM cleanup.",
            rawTranscript: "um so basically we need to build an apple watch app with live activity and complication. first the user taps to record audio. second audio is saved locally. then background fetch syncs it to iphone. requirement is to run speech recognition stage one and then stage two on-device llm to format requirements as bullets and conditions as numbered list. make sure to handle offline mode.",
            cleanedNote: """
            # Voice Note Architecture & Live Activity
            
            > Capture voice ideas instantly from Apple Watch complications and Live Activity, then sync to iOS for ASR and on-device LLM cleanup.
            
            ### 🎯 Requirements
            - Build an Apple Watch app with Live Activity and Watch complication support
            - Stage 1: Run on-device ASR speech recognition to transcribe voice memos
            - Stage 2: Run on-device LLM cleanup to format requirements into bullet points and enumerated conditions into numbered formatting
            - Handle offline mode gracefully with persistent local caching
            
            ### 🔢 Sequential Conditions & Workflow
            1. User initiates one-tap recording via Watch complication or Smart Stack Live Activity
            2. Audio file is captured and stored locally on watchOS without blocking transcription
            3. When background activity runs or periodic sync occurs, audio is transferred to iOS companion app
            4. iOS companion app processes Stage 1 (ASR) followed by Stage 2 (LLM Copywriting)
            
            ### ✅ Action Items
            - [ ] Test WatchConnectivity file transfer during background wakeups
            - [ ] Verify on-device Whisper transcription accuracy
            - [ ] Implement smart prompt templates for notes
            """,
            requirements: [
                "Build an Apple Watch app with Live Activity and Watch complication support",
                "Stage 1: Run on-device ASR speech recognition to transcribe voice memos",
                "Stage 2: Run on-device LLM cleanup to format requirements into bullet points and enumerated conditions into numbered formatting",
                "Handle offline mode gracefully with persistent local caching"
            ],
            conditions: [
                "User initiates one-tap recording via Watch complication or Smart Stack Live Activity",
                "Audio file is captured and stored locally on watchOS without blocking transcription",
                "When background activity runs or periodic sync occurs, audio is transferred to iOS companion app",
                "iOS companion app processes Stage 1 (ASR) followed by Stage 2 (LLM Copywriting)"
            ],
            actionItems: [
                "Test WatchConnectivity file transfer during background wakeups",
                "Verify on-device Whisper transcription accuracy",
                "Implement smart prompt templates for notes"
            ],
            tags: ["#watchOS", "#iOS", "#architecture", "#LLM"],
            status: .ready,
            source: .watchComplication,
            isFavorite: true
        )
        
        let sample2 = VoiceNote(
            id: UUID(),
            createdAt: Date().addingTimeInterval(-86400),
            duration: 28.5,
            audioFileName: nil,
            title: "Sprint Planning & Release Checklist",
            summary: "Sprint roadmap items including push notifications and audio waveform visualizations.",
            rawTranscript: "okay for sprint planning we need to test audio waveform rendering. also requirement is push notifications for when sync finishes. condition 1 if watch battery is under twenty percent delay sync. condition 2 if wifi is connected sync immediately. remember to review unit tests with team.",
            cleanedNote: """
            # Sprint Planning & Release Checklist
            
            > Sprint roadmap items including push notifications and audio waveform visualizations.
            
            ### 🎯 Requirements
            - Test audio waveform rendering across varied memo lengths
            - Send completion notification when background sync finishes processing
            
            ### 🔢 Conditions & Execution Logic
            1. If Watch battery is under 20%, delay heavy background sync
            2. If Wi-Fi is connected, trigger immediate high-speed sync
            
            ### ✅ Action Items
            - [ ] Review unit test coverage with the engineering team
            - [ ] Validate battery consumption metrics during audio recording
            """,
            requirements: [
                "Test audio waveform rendering across varied memo lengths",
                "Send completion notification when background sync finishes processing"
            ],
            conditions: [
                "If Watch battery is under 20%, delay heavy background sync",
                "If Wi-Fi is connected, trigger immediate high-speed sync"
            ],
            actionItems: [
                "Review unit test coverage with the engineering team",
                "Validate battery consumption metrics during audio recording"
            ],
            tags: ["#planning", "#sprint", "#release"],
            status: .ready,
            source: .watchLiveActivity,
            isFavorite: false
        )

        let sample3 = VoiceNote(
            id: UUID(),
            createdAt: Date().addingTimeInterval(-86400 * 2),
            duration: 54.2,
            audioFileName: nil,
            title: "On-Device AI Engine & Privacy Architecture",
            summary: "Zero cloud transmission architecture running local Whisper CoreML ASR and MLX Swift Qwen3 on-device LLM.",
            rawTranscript: "hey team so for the AI engine we need complete privacy. requirement one is speech recognition must run locally with whisperkit and coreml so no audio ever leaves the device. requirement two is stage two structured copywriting runs on-device using qwen3 with mlx swift. condition 1 if the device supports metal gpu acceleration execute directly on neural engine. condition 2 if user configures a local ollama endpoint route there instead. make sure to encrypt local storage with aes 256.",
            cleanedNote: """
            # On-Device AI Engine & Privacy Architecture

            > Zero cloud transmission architecture running local Whisper CoreML ASR and MLX Swift Qwen3 on-device LLM.

            ### 🎯 Requirements
            - Run speech recognition locally via WhisperKit CoreML (no audio leaves device)
            - Execute Stage 2 copywriting using on-device Qwen3 via MLX Swift Metal acceleration
            - Encrypt local audio recordings and notes database on disk with AES-256
            - Zero cloud accounts, telemetry, or external API requirements

            ### 🔢 Execution Logic & Fallback Chain
            1. If device supports Metal GPU, execute on-device Qwen3 model
            2. If user explicitly opts into local LLM endpoint in Settings, route to private Ollama host
            3. If on-device inference is unavailable, fall back to deterministic transformer

            ### ✅ Action Items
            - [ ] Benchmark CoreML neural engine inference latency on A17/A18 Pro
            - [ ] Validate MLX Swift memory allocation and cache purge on backgrounding
            - [ ] Confirm zero network requests during full note processing
            """,
            requirements: [
                "Run speech recognition locally via WhisperKit CoreML (no audio leaves device)",
                "Execute Stage 2 copywriting using on-device Qwen3 via MLX Swift Metal acceleration",
                "Encrypt local audio recordings and notes database on disk with AES-256",
                "Zero cloud accounts, telemetry, or external API requirements"
            ],
            conditions: [
                "If device supports Metal GPU, execute on-device Qwen3 model",
                "If user explicitly opts into local LLM endpoint in Settings, route to private Ollama host",
                "If on-device inference is unavailable, fall back to deterministic transformer"
            ],
            actionItems: [
                "Benchmark CoreML neural engine inference latency on A17/A18 Pro",
                "Validate MLX Swift memory allocation and cache purge on backgrounding",
                "Confirm zero network requests during full note processing"
            ],
            tags: ["#AI", "#privacy", "#CoreML", "#architecture"],
            status: .ready,
            source: .phoneApp,
            isFavorite: true,
            cleanupEngine: "On-Device LLM (Qwen3-0.6B)"
        )

        let sample4 = VoiceNote(
            id: UUID(),
            createdAt: Date().addingTimeInterval(-86400 * 3),
            duration: 19.8,
            audioFileName: nil,
            title: "Apple Watch Complications & Offline Sync",
            summary: "Instant 1-tap recording from watch face complications with background queue sync.",
            rawTranscript: "make sure the watch app supports all watch face complication families circular corner rectangular and inline. condition 1 tapping complication starts capture immediately without launching full app UI. condition 2 background fetch sweeps un-synced memos every fifteen minutes.",
            cleanedNote: """
            # Apple Watch Complications & Offline Sync

            > Instant 1-tap recording from watch face complications with background queue sync.

            ### 🎯 Requirements
            - Support all WidgetKit complication families: circular, corner, rectangular, inline
            - Maintain offline queue on Apple Watch with zero phone dependency
            - Background sync transfers AAC memos automatically when iPhone is nearby

            ### 🔢 Workflow Conditions
            1. Tapping complication immediately starts audio capture without UI delay
            2. Background fetch sweeps un-synced memos every 15-30 minutes

            ### ✅ Action Items
            - [ ] Test complications across 42mm, 46mm, and 49mm Ultra displays
            - [ ] Verify Smart Stack Live Activity timer accuracy
            """,
            requirements: [
                "Support all WidgetKit complication families: circular, corner, rectangular, inline",
                "Maintain offline queue on Apple Watch with zero phone dependency",
                "Background sync transfers AAC memos automatically when iPhone is nearby"
            ],
            conditions: [
                "Tapping complication immediately starts audio capture without UI delay",
                "Background fetch sweeps un-synced memos every 15-30 minutes"
            ],
            actionItems: [
                "Test complications across 42mm, 46mm, and 49mm Ultra displays",
                "Verify Smart Stack Live Activity timer accuracy"
            ],
            tags: ["#watchOS", "#widgets", "#design"],
            status: .ready,
            source: .watchComplication,
            isFavorite: false,
            cleanupEngine: "On-Device LLM (Qwen3-0.6B)"
        )
        
        self.notes = [sample1, sample2, sample3, sample4]
        persistNotes()
    }
}
