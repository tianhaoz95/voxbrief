import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

public enum AppleFoundationModelState: Sendable, Equatable {
    case available
    case unavailable(String)
}

public enum AppleFoundationModelError: LocalizedError {
    case unsupportedPlatform
    case unavailable(reason: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedPlatform:
            return "Apple Foundation Model requires iOS 26+ or macOS 26+ with Apple Intelligence support."
        case .unavailable(let reason):
            return "Apple Foundation Model is unavailable: \(reason)"
        }
    }
}

/// Provides text generation via Apple's built-in FoundationModels framework (`SystemLanguageModel`).
///
/// On devices and OS versions where Apple Intelligence is supported and enabled (iOS 26+, macOS 26+),
/// this model runs locally on the Apple Neural Engine with zero extra download and no network access.
@MainActor
public final class AppleFoundationModelService: ObservableObject {
    public static let shared = AppleFoundationModelService()

    public static let modelDisplayName = "Apple Foundation Model"

    @Published public private(set) var state: AppleFoundationModelState = .available

    public init() {
        refreshState()
    }

    /// Whether the Apple Foundation Model is supported and currently available on this device/platform.
    public static var isSupportedOnThisDevice: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    /// Human-readable detail about whether the model is available or why it is unavailable.
    public func refreshState() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let model = SystemLanguageModel.default
            switch model.availability {
            case .available:
                state = .available
            case .unavailable(let reason):
                switch reason {
                case .deviceNotEligible:
                    state = .unavailable("This device does not support Apple Intelligence.")
                case .appleIntelligenceNotEnabled:
                    state = .unavailable("Apple Intelligence is not enabled in System Settings.")
                case .modelNotReady:
                    state = .unavailable("Apple Foundation Model is preparing or downloading system assets.")
                @unknown default:
                    state = .unavailable("Apple Foundation Model is currently unavailable.")
                }
            }
            return
        }
        #endif
        state = .unavailable("Requires iOS 26+ or macOS 26+ with Apple Intelligence.")
    }

    /// Generates text using the system foundation model (`LanguageModelSession`).
    public func generate(systemPrompt: String, userPrompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                let reason: String
                switch model.availability {
                case .unavailable(let uReason):
                    reason = "\(uReason)"
                case .available:
                    reason = "model reported unavailable"
                }
                throw AppleFoundationModelError.unavailable(reason: reason)
            }

            let session = LanguageModelSession(model: model, instructions: systemPrompt)
            let response = try await session.respond(to: userPrompt)
            return response.content
        }
        #endif
        throw AppleFoundationModelError.unsupportedPlatform
    }
}
