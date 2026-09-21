import Foundation
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Owns the lifecycle of the iPhone-side Live Activity shown in the Dynamic Island / Lock Screen
/// while a direct on-device recording is in progress. The Activity's elapsed timer is driven purely
/// by `startedAt` (ActivityKit renders `Text(timerInterval:)` client-side), so no periodic update
/// calls are needed between start and end.
@MainActor
public final class LiveActivityManager {
    public static let shared = LiveActivityManager()

    public init() {}

    #if canImport(ActivityKit)
    private var currentActivity: Activity<VoiceNoteActivityAttributes>?
    private var recordingStartedAt: Date?
    #endif

    public func start(noteId: UUID, source: String) {
        #if canImport(ActivityKit)
        cancel()

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[LiveActivityManager] Live Activities are not enabled by the user.")
            return
        }

        let startedAt = Date()
        let attributes = VoiceNoteActivityAttributes(noteId: noteId.uuidString, source: source)
        let initialState = VoiceNoteActivityAttributes.ContentState(
            phase: .recording,
            duration: 0,
            startedAt: startedAt,
            audioLevel: 0.5
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil)
            )
            currentActivity = activity
            recordingStartedAt = startedAt
        } catch {
            print("[LiveActivityManager] Failed to start Live Activity: \(error)")
        }
        #endif
    }

    /// Transitions the Activity to a "processing" appearance instead of ending it -- called once
    /// recording stops and Stage 1/2 begins, so the Activity (and the Dynamic Island/Lock Screen
    /// glance it provides) stays up through processing rather than vanishing the instant the user
    /// taps stop. That's what lets the caller leave the app immediately instead of watching a
    /// spinner in-app: `finish(success:)` below is what actually ends it once the pipeline lands.
    public func updateToProcessing(duration: TimeInterval) {
        #if canImport(ActivityKit)
        guard let activity = currentActivity else { return }
        let state = VoiceNoteActivityAttributes.ContentState(
            phase: .processing,
            duration: duration,
            startedAt: recordingStartedAt ?? Date(),
            audioLevel: 0
        )
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
        #endif
    }

    /// Ends the Activity once Stage 1/2 actually finishes (or fails), briefly showing a
    /// ready/failed state rather than disappearing silently -- `dismissalPolicy: .default` lets
    /// the system keep it visible for a short while afterward instead of yanking it immediately.
    public func finish(success: Bool) {
        #if canImport(ActivityKit)
        guard let activity = currentActivity else { return }
        let finalState = VoiceNoteActivityAttributes.ContentState(
            phase: success ? .ready : .failed,
            duration: 0,
            startedAt: recordingStartedAt ?? Date(),
            audioLevel: 0
        )
        Task {
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .default)
        }
        currentActivity = nil
        recordingStartedAt = nil
        #endif
    }

    /// Ends the Activity immediately with no ready/failed glimpse -- for when recording itself
    /// gets cancelled before there's anything to process.
    public func cancel() {
        #if canImport(ActivityKit)
        guard let activity = currentActivity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        currentActivity = nil
        recordingStartedAt = nil
        #endif
    }
}
