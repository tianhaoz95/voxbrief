import Foundation
import WhisperKit

public protocol ASRServiceProtocol: Sendable {
    func transcribeAudio(at fileURL: URL) async throws -> String
}

public enum ASRError: LocalizedError, Sendable {
    case fileNotFound
    case emptyAudio
    case modelLoadFailed(String)
    case transcriptionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Audio file was not found."
        case .emptyAudio:
            return "Audio recording was empty or silent."
        case .modelLoadFailed(let reason):
            return "Could not load the on-device Whisper model: \(reason)"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}

/// Stage 1 speech-to-text, powered by OpenAI's Whisper model running fully on-device via
/// WhisperKit (CoreML). Unlike Apple's `Speech` framework, this needs no system speech-recognition
/// permission and doesn't depend on Apple's own on-device model assets being present -- WhisperKit
/// manages its own model download (once, cached thereafter) and inference.
///
/// Model loading is expensive (multiple seconds), so the `WhisperKit` pipeline is created lazily on
/// first use and reused for every subsequent transcription.
public actor ASRService: ASRServiceProtocol {
    public static let shared = ASRService()

    /// English-only, small enough for a quick first download while still being meaningfully more
    /// accurate than "tiny" -- a reasonable default for short voice notes. Change here to trade
    /// off accuracy, speed, and download size (see the model table in argmaxinc/argmax-oss-swift).
    public static let defaultModel = "base.en"

    private let modelName: String
    private var pipe: WhisperKit?
    private var loadTask: Task<WhisperKit, Error>?

    public init(modelName: String = ASRService.defaultModel) {
        self.modelName = modelName
    }

    /// Transcribes an audio file at the given local file URL.
    public func transcribeAudio(at fileURL: URL) async throws -> String {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ASRError.fileNotFound
        }

        let whisperKit: WhisperKit
        do {
            whisperKit = try await loadedPipe()
        } catch {
            throw ASRError.modelLoadFailed(error.localizedDescription)
        }

        do {
            let results = try await whisperKit.transcribe(audioPath: fileURL.path)
            let transcript = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if transcript.isEmpty {
                throw ASRError.emptyAudio
            }
            return transcript
        } catch let error as ASRError {
            throw error
        } catch {
            throw ASRError.transcriptionFailed(error.localizedDescription)
        }
    }

    /// Loads (or returns the already-loaded) WhisperKit pipeline. Concurrent callers await the
    /// same in-flight load rather than triggering redundant model loads.
    private func loadedPipe() async throws -> WhisperKit {
        if let pipe {
            return pipe
        }
        if let loadTask {
            return try await loadTask.value
        }

        let modelName = self.modelName
        let task = Task<WhisperKit, Error> {
            try await WhisperKit(WhisperKitConfig(model: modelName, verbose: false))
        }
        loadTask = task

        do {
            let loaded = try await task.value
            pipe = loaded
            loadTask = nil
            return loaded
        } catch {
            loadTask = nil
            throw error
        }
    }
}
