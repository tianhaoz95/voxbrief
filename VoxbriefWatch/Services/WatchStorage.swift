import Foundation

public enum WatchSyncState: String, Codable, Sendable {
    case pending = "pending"
    case transferring = "transferring"
    case synced = "synced"
    case failed = "failed"
}

public struct WatchLocalNote: Identifiable, Codable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public var duration: TimeInterval
    public let localFileName: String
    public let source: NoteSource
    public var syncState: WatchSyncState
    public var lastSyncAttempt: Date?
    
    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        localFileName: String,
        source: NoteSource = .watchApp,
        syncState: WatchSyncState = .pending,
        lastSyncAttempt: Date? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.duration = duration
        self.localFileName = localFileName
        self.source = source
        self.syncState = syncState
        self.lastSyncAttempt = lastSyncAttempt
    }
}

@MainActor
public final class WatchStorage: ObservableObject {
    public static let shared = WatchStorage()
    
    @Published public private(set) var notes: [WatchLocalNote] = []
    
    private let storageURL: URL
    private let recordingsDirectoryURL: URL
    
    public init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.recordingsDirectoryURL = docs.appendingPathComponent("WatchRecordings", isDirectory: true)
        if !FileManager.default.fileExists(atPath: recordingsDirectoryURL.path) {
            try? FileManager.default.createDirectory(at: recordingsDirectoryURL, withIntermediateDirectories: true)
        }
        self.storageURL = docs.appendingPathComponent("watch_notes.json")
        load()
        if notes.isEmpty {
            seedSampleNotesIfEmpty()
        }
    }
    
    public func fileURL(for fileName: String) -> URL {
        return recordingsDirectoryURL.appendingPathComponent(fileName)
    }
    
    public func newRecordingURL(for id: UUID) -> URL {
        let fileName = "\(id.uuidString).\(AudioConstants.fileExtension)"
        return fileURL(for: fileName)
    }
    
    public func addNote(_ note: WatchLocalNote) {
        if let idx = notes.firstIndex(where: { $0.id == note.id }) {
            notes[idx] = note
        } else {
            notes.insert(note, at: 0)
        }
        persist()
    }
    
    public func updateSyncState(for noteId: UUID, state: WatchSyncState) {
        guard let idx = notes.firstIndex(where: { $0.id == noteId }) else { return }
        notes[idx].syncState = state
        notes[idx].lastSyncAttempt = Date()
        persist()
    }
    
    public func pendingNotes() -> [WatchLocalNote] {
        return notes.filter { $0.syncState == .pending || $0.syncState == .failed }
    }
    
    public func delete(id: UUID) {
        if let idx = notes.firstIndex(where: { $0.id == id }) {
            let file = fileURL(for: notes[idx].localFileName)
            try? FileManager.default.removeItem(at: file)
            notes.remove(at: idx)
            persist()
        }
    }
    
    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            let loaded = try JSONDecoder().decode([WatchLocalNote].self, from: data)
            self.notes = loaded.sorted(by: { $0.createdAt > $1.createdAt })
        } catch {
            print("[WatchStorage] Failed to load: \(error)")
        }
    }
    
    private func persist() {
        do {
            let data = try JSONEncoder().encode(notes)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[WatchStorage] Failed to persist: \(error)")
        }
    }

    private func seedSampleNotesIfEmpty() {
        guard notes.isEmpty else { return }
        let sample1 = WatchLocalNote(
            id: UUID(),
            createdAt: Date().addingTimeInterval(-600),
            duration: 18.5,
            localFileName: "sample_recording_1.m4a",
            source: .watchComplication,
            syncState: .pending
        )
        let sample2 = WatchLocalNote(
            id: UUID(),
            createdAt: Date().addingTimeInterval(-3600 * 2),
            duration: 32.0,
            localFileName: "sample_recording_2.m4a",
            source: .watchApp,
            syncState: .synced
        )
        self.notes = [sample1, sample2]
        persist()
    }
}
