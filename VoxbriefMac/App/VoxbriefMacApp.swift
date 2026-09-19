import AppKit
import SwiftUI

@main
struct VoxbriefMacApp: App {
    @StateObject private var accessibility = AccessibilityPermissionManager.shared
    @StateObject private var repository: NoteRepository
    @StateObject private var recorder: MacAudioRecorderService
    @StateObject private var coordinator: CaptureCoordinator

    private let hotkeyManager = GlobalHotkeyManager()
    private let overlayController: OverlayWindowController

    init() {
        let appSupportRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Voxbrief Mac", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupportRoot, withIntermediateDirectories: true)

        let audioFileManager = AudioFileManager(baseDirectoryOverride: appSupportRoot)
        let repository = NoteRepository(
            audioFileManager: audioFileManager,
            customStorageURL: appSupportRoot.appendingPathComponent("notes_store.json")
        )
        let recorder = MacAudioRecorderService(audioFileManager: audioFileManager)
        let pipeline = NoteProcessingPipeline(repository: repository, audioFileManager: audioFileManager)
        let coordinator = CaptureCoordinator(
            recorder: recorder,
            repository: repository,
            pipeline: pipeline,
            pasteInjector: PasteInjector()
        )

        _repository = StateObject(wrappedValue: repository)
        _recorder = StateObject(wrappedValue: recorder)
        _coordinator = StateObject(wrappedValue: coordinator)
        overlayController = OverlayWindowController(coordinator: coordinator, recorder: recorder)

        hotkeyManager.onBothCommandKeysPressed = { [weak coordinator] in
            coordinator?.beginCapture()
        }
    }

    var body: some Scene {
        MenuBarExtra("Voxbrief", systemImage: menuBarSymbolName) {
            MenuBarContentView(accessibility: accessibility, coordinator: coordinator, hotkeyManager: hotkeyManager)
        }
        .menuBarExtraStyle(.menu)

        Window("Capture History", id: "history") {
            HistoryView(repository: repository)
        }

        Settings {
            PreferencesView(accessibility: accessibility)
        }
    }

    private var menuBarSymbolName: String {
        switch coordinator.state {
        case .idle: return "waveform"
        case .listening: return "waveform.circle.fill"
        case .processing: return "sparkles"
        case .success: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}

/// Menu bar dropdown content: permission gate, hotkey reminder, and navigation. Requesting
/// Accessibility and starting the hotkey tap both happen from here (on first appearance and
/// whenever the trust state flips) rather than unconditionally at launch, since `start()` is a
/// no-op until the user has actually granted Accessibility.
private struct MenuBarContentView: View {
    @ObservedObject var accessibility: AccessibilityPermissionManager
    @ObservedObject var coordinator: CaptureCoordinator
    let hotkeyManager: GlobalHotkeyManager

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if accessibility.isTrusted {
                Text("Press both ⌘ keys to capture")
                Button("Capture History…") { openWindow(id: "history") }
            } else {
                Button("Grant Accessibility Access…") {
                    accessibility.requestPrompt()
                    accessibility.openSystemSettings()
                }
                Text("Required for the global hotkey and paste.")
            }

            Divider()

            SettingsLink {
                Text("Settings…")
            }
            Button("Quit Voxbrief") {
                NSApplication.shared.terminate(nil)
            }
        }
        .onAppear { syncHotkeyState() }
        .onChange(of: accessibility.isTrusted) { _, _ in syncHotkeyState() }
    }

    private func syncHotkeyState() {
        if accessibility.isTrusted {
            hotkeyManager.start()
        } else {
            hotkeyManager.stop()
        }
    }
}
