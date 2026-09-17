import Foundation
import MLX
import MLXLLM
import MLXLMCommon

public enum OnDeviceModelState: Sendable, Equatable {
    case notDownloaded
    case downloading(progress: Double)
    case ready
    case failed(String)
}

public enum OnDeviceLLMError: LocalizedError {
    case bundledModelMissing
    case unavailableInSimulator

    public var errorDescription: String? {
        switch self {
        case .bundledModelMissing:
            return "The bundled on-device model is missing from the app."
        case .unavailableInSimulator:
            return "On-device models require a real iPhone or iPad. The Simulator's graphics stack doesn't support the storage modes MLX needs for its GPU allocator -- this is a permanent MLX/Simulator limitation, not something this app can work around."
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
@MainActor
public final class OnDeviceLLMService: ObservableObject {
    public static let shared = OnDeviceLLMService()

    public static let smallModelResourceName = "Qwen3-0.6B-4bit"
    public static let smallModelDisplayName = "Qwen3-0.6B (bundled)"
    public static let smallModelParameterCount = "0.6B"
    public static let smallModelApproxSizeBytes: Int64 = 351_386_061

    public static let largeModelRepoId = "mlx-community/Qwen3-4B-4bit"
    public static let largeModelDisplayName = "Qwen3-4B"
    public static let largeModelParameterCount = "4B"
    public static let largeModelApproxDownloadBytes: Int64 = 2_278_972_183

    @Published public private(set) var largeModelState: OnDeviceModelState = .notDownloaded

    private let largeModelConfiguration = ModelConfiguration(id: OnDeviceLLMService.largeModelRepoId)

    private var smallContainer: ModelContainer?
    private var smallLoadTask: Task<ModelContainer, Error>?
    private var largeContainer: ModelContainer?
    private var downloadTask: Task<Void, Never>?

    public init() {
        refreshLargeModelState()
    }

    public static var isSupportedOnThisDevice: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
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
                let container = try await LLMModelFactory.shared.loadContainer(
                    configuration: configuration
                ) { progress in
                    Task { @MainActor [weak self] in
                        self?.largeModelState = .downloading(progress: progress.fractionCompleted)
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
        if case .ready = largeModelState {
            return largeContainer != nil
        }
        return false
    }

    /// Short display name of whichever model would actually serve the next `generate` call --
    /// used to label notes with which engine cleaned them up.
    public var activeModelDisplayName: String {
        isUsingLargeModel ? Self.largeModelDisplayName : "Qwen3-0.6B"
    }

    // MARK: - Generation

    /// Generates text using the best available model: the downloaded large model if ready,
    /// otherwise the bundled small model (always available, no setup required).
    public func generate(systemPrompt: String, userPrompt: String, maxTokens: Int = 1024) async throws -> String {
        guard Self.isSupportedOnThisDevice else {
            throw OnDeviceLLMError.unavailableInSimulator
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
        if case .ready = largeModelState, let largeContainer {
            return largeContainer
        }
        return try await loadSmallContainer()
    }

    private func loadSmallContainer() async throws -> ModelContainer {
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
        let userInput = UserInput(chat: chat)
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
