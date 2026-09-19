import Foundation

public final class AudioFileManager: Sendable {
    public static let shared = AudioFileManager()

    /// Overrides where audio files are stored. Only needed on platforms where
    /// `.documentDirectory` resolves to a real, user-visible folder (e.g. non-sandboxed macOS,
    /// where it's the user's actual `~/Documents`) and writing app-private audio there would be
    /// clutter -- iOS leaves this `nil` and keeps its existing sandboxed-Documents behavior.
    private let baseDirectoryOverride: URL?

    private var notesDirectoryURL: URL {
        let base = baseDirectoryOverride ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioDir = base.appendingPathComponent(AudioConstants.audioDirectoryName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: audioDir.path) {
            try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        }
        return audioDir
    }

    public init(baseDirectoryOverride: URL? = nil) {
        self.baseDirectoryOverride = baseDirectoryOverride
    }
    
    /// Returns the absolute file URL for a given audio file name
    public func url(for fileName: String) -> URL {
        return notesDirectoryURL.appendingPathComponent(fileName)
    }
    
    /// Generates a unique file URL for a new recording
    public func newAudioFileURL(for noteId: UUID = UUID()) -> URL {
        let fileName = "\(noteId.uuidString).\(AudioConstants.fileExtension)"
        return notesDirectoryURL.appendingPathComponent(fileName)
    }
    
    /// Copies an incoming file (e.g. from WatchConnectivity temporary directory) to persistent storage
    public func copyIncomingAudioFile(from sourceURL: URL, noteId: UUID) throws -> String {
        let targetFileName = "\(noteId.uuidString).\(AudioConstants.fileExtension)"
        let targetURL = notesDirectoryURL.appendingPathComponent(targetFileName)
        
        if FileManager.default.fileExists(atPath: targetURL.path) {
            try? FileManager.default.removeItem(at: targetURL)
        }
        
        try FileManager.default.copyItem(at: sourceURL, to: targetURL)
        return targetFileName
    }
    
    /// Deletes an audio file if it exists
    public func deleteAudioFile(fileName: String) {
        let fileURL = notesDirectoryURL.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }
    
    /// Checks if the audio file exists
    public func fileExists(fileName: String) -> Bool {
        let fileURL = notesDirectoryURL.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
}
