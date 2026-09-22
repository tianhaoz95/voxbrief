import Foundation
import MLX
import MLXLLM
import MLXLMCommon
#if os(iOS)
import UIKit
#endif

public enum OnDeviceModelState: Sendable, Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case ready
    case failed(String)
}

public enum OnDeviceLLMError: LocalizedError {
    case bundledModelMissing
    case unavailableInSimulator
    case unavailableWhileBackgrounded

    public var errorDescription: String? {
        switch self {
        case .bundledModelMissing:
            return "The bundled on-device model is missing from the app."
        case .unavailableInSimulator:
            return "On-device models require a real iPhone or iPad. The Simulator's graphics stack doesn't support the storage modes MLX needs for its GPU allocator -- this is a permanent MLX/Simulator limitation, not something this app can work around."
        case .unavailableWhileBackgrounded:
            return "On-device generation was skipped because the app is in the background -- attempting it anyway risks crashing the whole process (see OnDeviceLLMService's doc comment). Falling back to the deterministic rule-based cleanup instead."
        }
    }
}

public enum OnDeviceModelSelection: String, CaseIterable, Identifiable, Sendable {
    case auto = "auto"
    case small = "small"
    case large = "large"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto:
            return "Auto (Best Available)"
        case .small:
            return "Qwen3-0.6B (Bundled)"
        case .large:
            return "Qwen3-4B (Downloaded)"
        }
    }

    public var shortDisplayName: String {
        switch self {
        case .auto:
            return "Auto"
        case .small:
            return "Qwen3-0.6B"
        case .large:
            return "Qwen3-4B"
        }
    }
}

/// Runs Stage 2 text generation fully on-device via MLX Swift (mlx-swift-examples), with two
/// model tiers:
///
/// - A small model (Qwen3-0.6B-4bit) bundled directly in the app -- always available, zero
///   setup, works offline from first launch.
/// - A larger, optional model (Qwen3-4B-4bit, ~2.3 GB) downloaded on demand from Hugging Face
///   when the user chooses to in Settings, for meaningfully better cleanup quality. Once
///   downloaded it's used automatically in place of the bundled model.
///
/// Both run entirely on-device with no network at inference time; only the large model's
/// one-time download needs network.
///
/// IMPORTANT: MLX does not run in the iOS Simulator at all -- its Metal GPU allocator requires
/// a heap storage mode the Simulator's Metal implementation doesn't support, and hitting this
/// crashes the whole process with an uncatchable C++ abort (not a Swift error `try/catch` can
/// intercept). Every entry point below checks `targetEnvironment(simulator)` and fails cleanly
/// *before* touching any MLX API, rather than letting that abort happen.
///
/// The same category of crash also happens on a real device if generation is attempted while
/// the app is backgrounded: confirmed via a TestFlight crash report where a keyboard-triggered
/// recording's Stage 2 generation was still running when the user switched back to their
/// previous app (exactly what the keyboard flow's "you can switch back now" messaging invites).
/// iOS revokes/suspends foreground GPU access for a backgrounded app, and MLX's Metal command
/// buffer for the in-flight generation later completes with an error; its completion handler
/// (`mlx::core::gpu::check_error`) throws a C++ exception from deep inside an async Metal/
/// libdispatch callback with no Swift `try/catch` anywhere on that call stack, so it terminates
/// the process (`__cxa_throw` -> `std::terminate` -> abort) exactly like the Simulator case, just
/// triggered by backgrounding instead of an unsupported heap mode. `isSafeToUseMLXRightNow`
/// below gates every entry point the same way as the Simulator check -- this can't fully
/// eliminate the risk if backgrounding happens *after* the check passes, mid-generation (MLX
/// exposes no way to cancel or pause one), but it stops a new generation from ever starting
/// while already backgrounded, which is the common case this crash was actually hit from.
@MainActor
public final class OnDeviceLLMService: ObservableObject {
    public static let shared = OnDeviceLLMService()

    public static let modelPreferenceStorageKey = "on_device_model_preference"

    public static let smallModelResourceName = "Qwen3-0.6B-4bit"
    public static let smallModelDisplayName = "Qwen3-0.6B (bundled)"
    public static let smallModelParameterCount = "0.6B"
    public static let smallModelApproxSizeBytes: Int64 = 351_386_061

    public static let largeModelRepoId = "mlx-community/Qwen3-4B-4bit"
    public static let largeModelDisplayName = "Qwen3-4B"
    public static let largeModelParameterCount = "4B"
    public static let largeModelApproxDownloadBytes: Int64 = 2_278_972_183

    @Published public private(set) var largeModelState: OnDeviceModelState = .notDownloaded

    @Published public var modelPreference: OnDeviceModelSelection {
        didSet {
            UserDefaults.standard.set(modelPreference.rawValue, forKey: Self.modelPreferenceStorageKey)
            if modelPreference == .small {
                largeContainer = nil
            }
        }
    }

    private let largeModelConfiguration = ModelConfiguration(id: OnDeviceLLMService.largeModelRepoId)

    private var smallContainer: ModelContainer?
    private var smallLoadTask: Task<ModelContainer, Error>?
    private var largeContainer: ModelContainer?
    private var largeLoadTask: Task<ModelContainer, Error>?
    private var downloadTask: Task<Void, Never>?

    public init() {
        let savedRaw = UserDefaults.standard.string(forKey: Self.modelPreferenceStorageKey) ?? OnDeviceModelSelection.auto.rawValue
        self.modelPreference = OnDeviceModelSelection(rawValue: savedRaw) ?? .auto
        refreshLargeModelState()
    }

    public static var isSupportedOnThisDevice: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }

    /// `isSupportedOnThisDevice`, plus (on iOS only) not currently backgrounded -- see this
    /// type's doc comment. macOS has no equivalent GPU-access-revocation-on-background behavior,
    /// so this is just `isSupportedOnThisDevice` there. (Already `@MainActor` via the enclosing
    /// class -- `UIApplication.shared` access requires that.)
    private static var isSafeToUseMLXRightNow: Bool {
        guard isSupportedOnThisDevice else { return false }
        #if os(iOS)
        return UIApplication.shared.applicationState != .background
        #else
        return true
        #endif
    }

    // MARK: - Large (downloadable) model lifecycle

    /// Re-checks disk for an already-downloaded large model (e.g. on app launch).
    public func refreshLargeModelState() {
        guard Self.isSupportedOnThisDevice else {
            largeModelState = .failed(OnDeviceLLMError.unavailableInSimulator.localizedDescription)
            return
        }
        if case .downloading = largeModelState { return }
        if largeContainer != nil {
            largeModelState = .ready
            return
        }
        largeModelState = Self.largeModelFilesExistOnDisk(configuration: largeModelConfiguration) ? .ready : .notDownloaded
    }

    private static func largeModelFilesExistOnDisk(configuration: ModelConfiguration) -> Bool {
        let directory = configuration.modelDirectory(hub: defaultHubApi)
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent("config.json").path)
    }

    public func downloadLargeModel() {
        guard Self.isSupportedOnThisDevice else {
            largeModelState = .failed(OnDeviceLLMError.unavailableInSimulator.localizedDescription)
            return
        }
        guard downloadTask == nil else { return }
        largeModelState = .downloading(progress: 0)

        downloadTask = Task {
            do {
                let configuration = largeModelConfiguration
                let modelDirectory = configuration.modelDirectory(hub: defaultHubApi)
                let container = try await LLMModelFactory.shared.loadContainer(
                    configuration: configuration
                ) { _ in
                    // Ignore the library's own `Progress.fractionCompleted` -- swift-transformers'
                    // Hub downloader weights it by FILE COUNT (`Progress(totalUnitCount:
                    // filenames.count)`), not by bytes, so a repo like this one (one ~2.2GB
                    // safetensors file plus several tiny config/tokenizer files) reports as
                    // almost done the instant the small files finish, long before the dominant
                    // file has downloaded any meaningful fraction of its bytes. Compute our own
                    // byte-weighted fraction instead by summing actual on-disk bytes under the
                    // model's directory -- this also picks up the currently-downloading file's
                    // growing `.incomplete` temp file, since that lives in a `.cache/huggingface/
                    // download` subdirectory of this same root.
                    let bytesOnDisk = Self.directorySizeInBytes(at: modelDirectory)
                    let fraction = min(1.0, Double(bytesOnDisk) / Double(Self.largeModelApproxDownloadBytes))
                    Task { @MainActor [weak self] in
                        self?.largeModelState = .downloading(progress: fraction)
                    }
                }
                self.largeContainer = container
                self.largeModelState = .ready
            } catch {
                self.largeModelState = .failed(error.localizedDescription)
            }
            self.downloadTask = nil
        }
    }

    /// Recursively sums the size of every regular file under `url`, including hidden ones --
    /// deliberately not `.skipsHiddenFiles`, since the Hub downloader's in-progress `.incomplete`
    /// file lives under a hidden `.cache` subdirectory that must be counted for progress to track
    /// the currently-downloading file's growing byte count, not just already-finished files.
    private nonisolated static func directorySizeInBytes(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else { continue }
            total += Int64(size)
        }
        return total
    }

    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        refreshLargeModelState()
    }

    public func deleteLargeModel() {
        let directory = largeModelConfiguration.modelDirectory(hub: defaultHubApi)
        try? FileManager.default.removeItem(at: directory)
        largeContainer = nil
        refreshLargeModelState()
    }

    /// Whether the higher-quality downloaded model is the one actually in use right now
    /// (as opposed to the always-available bundled model).
    public var isUsingLargeModel: Bool {
        guard case .ready = largeModelState else {
            return false
        }
        switch modelPreference {
        case .auto, .large:
            return true
        case .small:
            return false
        }
    }

    /// Short display name of whichever model would actually serve the next `generate` call --
    /// used to label notes with which engine cleaned them up.
    public var activeModelDisplayName: String {
        isUsingLargeModel ? Self.largeModelDisplayName : "Qwen3-0.6B"
    }

    #if DEBUG
    internal func setLargeModelStateForTesting(_ state: OnDeviceModelState) {
        self.largeModelState = state
    }
    #endif

    // MARK: - Generation

    /// Best-effort: loads whichever model would actually serve the next `generate()` call now,
    /// rather than paying that cost inline on first real use. A no-op on the Simulator (same as
    /// `generate()`) and if the large model is already `.ready` (already resident once
    /// downloaded, nothing more to load). Errors are swallowed -- a real `generate()` call will
    /// surface them properly if loading still fails.
    public func warmUp() async {
        guard Self.isSafeToUseMLXRightNow else { return }
        _ = try? await bestAvailableContainer()
    }

    /// Generates text using the best available model: the downloaded large model if ready,
    /// otherwise the bundled small model (always available, no setup required).
    public func generate(systemPrompt: String, userPrompt: String, maxTokens: Int = 1024) async throws -> String {
        guard Self.isSupportedOnThisDevice else {
            throw OnDeviceLLMError.unavailableInSimulator
        }
        guard Self.isSafeToUseMLXRightNow else {
            throw OnDeviceLLMError.unavailableWhileBackgrounded
        }
        let container = try await bestAvailableContainer()
        return try await Self.runGeneration(
            container: container,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: maxTokens
        )
    }

    private func bestAvailableContainer() async throws -> ModelContainer {
        if isUsingLargeModel {
            do {
                return try await loadLargeContainer()
            } catch {
                print("[OnDeviceLLMService] Failed to load large model container, falling back to small: \(error)")
                return try await loadSmallContainer()
            }
        }
        return try await loadSmallContainer()
    }

    private func loadLargeContainer() async throws -> ModelContainer {
        guard Self.isSupportedOnThisDevice else {
            throw OnDeviceLLMError.unavailableInSimulator
        }
        if let largeContainer {
            return largeContainer
        }
        if let largeLoadTask {
            return try await largeLoadTask.value
        }

        let task = Task<ModelContainer, Error> {
            let configuration = largeModelConfiguration
            return try await LLMModelFactory.shared.loadContainer(configuration: configuration)
        }
        largeLoadTask = task

        do {
            let container = try await task.value
            largeContainer = container
            largeLoadTask = nil
            return container
        } catch {
            largeLoadTask = nil
            throw error
        }
    }

    private func loadSmallContainer() async throws -> ModelContainer {
        guard Self.isSupportedOnThisDevice else {
            throw OnDeviceLLMError.unavailableInSimulator
        }
        if let smallContainer {
            return smallContainer
        }
        if let smallLoadTask {
            return try await smallLoadTask.value
        }

        let task = Task<ModelContainer, Error> {
            guard let directory = Bundle.main.url(forResource: OnDeviceLLMService.smallModelResourceName, withExtension: nil) else {
                throw OnDeviceLLMError.bundledModelMissing
            }
            let configuration = ModelConfiguration(directory: directory)
            return try await LLMModelFactory.shared.loadContainer(configuration: configuration)
        }
        smallLoadTask = task

        do {
            let container = try await task.value
            smallContainer = container
            smallLoadTask = nil
            return container
        } catch {
            smallLoadTask = nil
            throw error
        }
    }

    private static func runGeneration(
        container: ModelContainer,
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int
    ) async throws -> String {
        let chat: [Chat.Message] = [.system(systemPrompt), .user(userPrompt)]
        // Qwen3's chat template defaults to "thinking mode" -- it opens its own <think>...</think>
        // block and reasons before answering unless told not to -- which silently ate the entire
        // 24-token budget of the template-classification call before it ever reached the actual
        // `{"template": ...}` answer, making classification fall back to the default template on
        // almost every call. `enable_thinking: false` is a template-rendering variable read
        // directly by Qwen3's chat template (see LLMUserInputProcessor forwarding
        // `additionalContext` to `tokenizer.applyChatTemplate`), not a generation parameter --
        // there's no equivalent on `GenerateParameters`.
        let userInput = UserInput(chat: chat, additionalContext: ["enable_thinking": false])
        let parameters = GenerateParameters(maxTokens: maxTokens, temperature: 0.3)

        return try await container.perform { (context: ModelContext) -> String in
            let lmInput = try await context.processor.prepare(input: userInput)
            let stream = try MLXLMCommon.generate(input: lmInput, parameters: parameters, context: context)

            var result = ""
            for await item in stream {
                if let chunk = item.chunk {
                    result += chunk
                }
            }
            return result
        }
    }
}
