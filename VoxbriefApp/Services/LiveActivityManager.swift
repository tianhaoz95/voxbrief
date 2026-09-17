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
    #endif

    public func start(noteId: UUID, source: String) {
        #if canImport(ActivityKit)
        end()

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("[LiveActivityManager] Live Activities are not enabled by the user.")
            return
        }

        let attributes = VoiceNoteActivityAttributes(noteId: noteId.uuidString, source: source)
        let initialState = VoiceNoteActivityAttributes.ContentState(
            isRecording: true,
            duration: 0,
            startedAt: Date(),
            audioLevel: 0.5
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil)
            )
            currentActivity = activity
        } catch {
            print("[LiveActivityManager] Failed to start Live Activity: \(error)")
        }
        #endif
    }

    public func end() {
        #if canImport(ActivityKit)
        guard let activity = currentActivity else { return }
        let finalState = VoiceNoteActivityAttributes.ContentState(
            isRecording: false,
            duration: 0,
            startedAt: Date(),
            audioLevel: 0
        )
        Task {
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .immediate)
        }
        currentActivity = nil
        #endif
    }
}
