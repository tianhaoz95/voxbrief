import SwiftUI

@main
struct VoxbriefApp: App {
    @StateObject private var watchSyncService = WatchSyncService.shared
    @StateObject private var noteRepository = NoteRepository.shared
    @StateObject private var pipeline = NoteProcessingPipeline.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(watchSyncService)
                .environmentObject(noteRepository)
                .environmentObject(pipeline)
        }
    }
}

/// Hosts the main note list plus the app-wide chrome (first-run onboarding, appearance,
/// and the Live Activity "Stop & Save" deep link) that only makes sense at the root.
private struct RootView: View {
    @AppStorage("has_completed_onboarding") private var hasCompletedOnboarding = false
    @AppStorage("app_appearance") private var appearance: String = "system"
    @State private var showOnboarding = false

    var body: some View {
        NoteListView()
            .preferredColorScheme(colorScheme)
            .onAppear {
                showOnboarding = !hasCompletedOnboarding
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView {
                    hasCompletedOnboarding = true
                    showOnboarding = false
                }
                .preferredColorScheme(colorScheme)
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
    }

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private func handleDeepLink(_ url: URL) {
        guard let host = url.host else { return }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var params: [String: String] = [:]
        for item in queryItems {
            if let val = item.value {
                params[item.name] = val
            }
        }

        if host == "record" {
            let action = params["action"]
            if action == "stop" {
                RecordingCoordinator.shared.handleStopDeepLink()
            } else {
                NotificationCenter.default.post(
                    name: .voxbriefNavigate,
                    object: nil,
                    userInfo: ["screen": "record"]
                )
            }
        } else if host == "navigate" {
            NotificationCenter.default.post(
                name: .voxbriefNavigate,
                object: nil,
                userInfo: params
            )
        }
    }
}

extension Notification.Name {
    public static let voxbriefNavigate = Notification.Name("com.jacksonzhou666.voxbrief.navigate")
}
