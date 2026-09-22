import Foundation
import WhisperKit

public protocol ASRServiceProtocol: Sendable {
    /// `vocabulary` is a list of jargon/proper-noun terms (see `DictionaryEntry`) to bias the
    /// decoder toward recognizing, via Whisper's standard "initial prompt" mechanism. Pass `[]`
    /// for no bias.
    /// `onProgress` receives the progressive full transcript so far as decoding takes place. Pass `nil`
    /// if streaming progress is not needed.
    func transcribeAudio(
        at fileURL: URL,
        vocabulary: [String],
        onProgress: (@Sendable (String) -> Void)?
    ) async throws -> String

    /// Best-effort: starts loading the underlying model now (if not already loaded/loading)
    /// rather than waiting for the first real `transcribeAudio` call to pay that cost. Errors are
    /// swallowed -- a real call will surface them properly if loading still fails by the time it
    /// actually needs the model. A no-op is a valid, always-safe implementation (e.g. for a test
    /// double). See `NoteProcessingPipeline.warmUp`, which starts (but never awaits) this the
    /// moment a recording begins, so it races however long the user is talking instead of
    /// blocking the stop-recording path with a cold load.
    func warmUp() async
}

public extension ASRServiceProtocol {
    func transcribeAudio(at fileURL: URL, vocabulary: [String] = []) async throws -> String {
        try await transcribeAudio(at: fileURL, vocabulary: vocabulary, onProgress: nil)
    }
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

    /// Cap on how many personal-dictionary terms get folded into the decoder's conditioning
    /// prompt, applied *before* encoding to tokens. WhisperKit's own `TextDecoder` truncates
    /// `promptTokens` to fit half the model's token context by keeping the *last* tokens, so
    /// capping the term count here (rather than relying on that alone) avoids silently dropping
    /// earlier-added terms from the front of an unbounded list.
    public static let maxVocabularyTerms = 100

    private let modelName: String
    private var pipe: WhisperKit?
    private var loadTask: Task<WhisperKit, Error>?

    public init(modelName: String = ASRService.defaultModel) {
        self.modelName = modelName
    }

    /// Transcribes an audio file at the given local file URL. `vocabulary` (personal-dictionary
    /// terms) biases decoding toward recognizing them correctly; pass `[]` for no bias.
    public func warmUp() async {
        _ = try? await loadedPipe()
    }

    public func transcribeAudio(
        at fileURL: URL,
        vocabulary: [String] = [],
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw ASRError.fileNotFound
        }

        let whisperKit: WhisperKit
        do {
            whisperKit = try await loadedPipe()
        } catch {
            throw ASRError.modelLoadFailed(error.localizedDescription)
        }

        let decodeOptions = Self.buildDecodingOptions(vocabulary: vocabulary, tokenizer: whisperKit.tokenizer)
        let tracker = ASRProgressTracker(onProgress: onProgress)

        do {
            let results = try await whisperKit.transcribe(
                audioPath: fileURL.path,
                decodeOptions: decodeOptions,
                callback: tracker.makeCallback()
            )
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

    /// `nil` (not a `DecodingOptions` with empty `promptTokens`) when there's no vocabulary or no
    /// tokenizer loaded yet, so an empty dictionary produces byte-identical behavior to calling
    /// `transcribe` with no options at all.
    static func buildDecodingOptions(vocabulary: [String], tokenizer: WhisperTokenizer?) -> DecodingOptions? {
        guard let promptText = vocabularyPromptText(from: vocabulary), let tokenizer else { return nil }
        let tokens = tokenizer.encode(text: " " + promptText)
        guard !tokens.isEmpty else { return nil }
        return DecodingOptions(promptTokens: tokens)
    }

    /// Pure and independently unit-testable (no WhisperKit/tokenizer needed): joins up to
    /// `maxTerms` vocabulary terms into the text that gets encoded into `promptTokens`.
    static func vocabularyPromptText(from vocabulary: [String], maxTerms: Int = ASRService.maxVocabularyTerms) -> String? {
        let cleaned = vocabulary
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }
        return cleaned.prefix(maxTerms).joined(separator: ", ")
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

/// Thread-safe tracker that receives incremental window decoding updates from WhisperKit's
/// `TranscriptionCallback` and forwards the accumulated full transcript so far to `onProgress`.
public final class ASRProgressTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var completedWindows: [Int: String] = [:]
    private var currentWindowId: Int = 0
    private var currentWindowText: String = ""
    private let onProgress: (@Sendable (String) -> Void)?

    public init(onProgress: (@Sendable (String) -> Void)? = nil) {
        self.onProgress = onProgress
    }

    /// Feeds incremental progress for a given window, returning the full assembled text so far.
    @discardableResult
    public func update(windowId: Int, text: String) -> String {
        lock.lock()
        defer { lock.unlock() }

        if windowId > currentWindowId {
            if !currentWindowText.isEmpty {
                completedWindows[currentWindowId] = currentWindowText
            }
            currentWindowId = windowId
            currentWindowText = ""
        }

        currentWindowText = text

        var parts: [String] = []
        for id in completedWindows.keys.sorted() {
            if let windowText = completedWindows[id] {
                let trimmed = windowText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    parts.append(trimmed)
                }
            }
        }
        let currentTrimmed = currentWindowText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currentTrimmed.isEmpty {
            parts.append(currentTrimmed)
        }

        let fullText = parts.joined(separator: " ")
        if !fullText.isEmpty {
            onProgress?(fullText)
        }
        return fullText
    }

    public func makeCallback() -> TranscriptionCallback? {
        guard onProgress != nil else { return nil }
        return { [weak self] progress in
            self?.update(windowId: progress.windowId, text: progress.text)
            return true
        }
    }
}
