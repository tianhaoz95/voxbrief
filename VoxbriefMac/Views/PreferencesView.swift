import ServiceManagement
import SwiftUI

/// Mac Settings window. Mirrors the iPhone app's `SettingsView` where it makes sense to behave
/// identically (same `@AppStorage` keys for the Ollama toggle, same `OnDeviceLLMService` for the
/// on-device model tier) plus the Mac-only permission/launch-at-login controls this app needs.
struct PreferencesView: View {
    @AppStorage("use_local_llm_endpoint") private var useLocalLLM: Bool = false
    @AppStorage("local_llm_endpoint_url") private var localLLMUrl: String = "http://127.0.0.1:11434/api/generate"
    @AppStorage("launch_at_login") private var launchAtLoginStored: Bool = false
    @AppStorage("auto_check_for_updates") private var autoCheckForUpdates: Bool = true
    @AppStorage(NoteProcessingPipeline.lightCleanupEnabledKey) private var lightCleanupEnabled: Bool = true

    @ObservedObject var accessibility: AccessibilityPermissionManager
    @StateObject private var microphone = MicrophonePermissionManager.shared
    @StateObject private var llmService = OnDeviceLLMService.shared
    @StateObject private var dictionaryStore = PersonalDictionaryStore.shared
    @StateObject private var updateChecker = UpdateChecker.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        Form {
            Section("Capture") {
                LabeledContent("Hotkey") {
                    Text("Press both ⌘ keys")
                        .foregroundStyle(.secondary)
                }
                Toggle("Launch at Login", isOn: launchAtLoginBinding)
            }

            Section("Permissions") {
                permissionRow(
                    title: "Microphone",
                    isGranted: microphone.isAuthorized,
                    onFix: microphone.isAuthorized ? nil : { microphone.requestOrOpenSystemSettings() }
                )
                permissionRow(
                    title: "Accessibility",
                    isGranted: accessibility.isTrusted,
                    onFix: accessibility.isTrusted ? nil : { accessibility.requestAccessOrOpenSettings() }
                )
            }

            Section {
                Toggle("Use Local LLM Endpoint (Ollama)", isOn: $useLocalLLM)
                if useLocalLLM {
                    TextField("http://127.0.0.1:11434/api/generate", text: $localLLMUrl)
                        .font(.subheadline.monospaced())
                        .textFieldStyle(.roundedBorder)
                }
            } header: {
                Text("Stage 2: LLM Cleanup")
            } footer: {
                Text("When enabled, captures are sent to the endpoint below instead of the on-device model. Off by default so nothing ever leaves this Mac unless you opt in.")
            }

            Section {
                Toggle("Enable Light Cleanup", isOn: $lightCleanupEnabled)
            } header: {
                Text("Light Cleanup")
            } footer: {
                Text("The Light Cleanup tab shows a lightly-proofread, near-verbatim version of the transcript alongside the fully restructured note. It's generated on demand the first time you open that tab, not automatically for every note -- turn it off to skip it entirely.")
            }

            Section {
                LabeledContent(OnDeviceLLMService.smallModelDisplayName) {
                    Text("\(OnDeviceLLMService.smallModelParameterCount) · bundled")
                        .foregroundStyle(.secondary)
                }
                largeModelRow
            } header: {
                Text("On-Device Models")
            } footer: {
                Text("The small model ships with the app and always works offline. Download the larger model for meaningfully better cleanup quality.")
            }

            Section(
                header: Text("Personal Dictionary"),
                footer: Text("Add jargon, product names, and people's names the on-device models don't know, so both Stage 1 (speech recognition) and Stage 2 (LLM cleanup) recognize and preserve them.")
            ) {
                Button {
                    openWindow(id: "dictionary")
                } label: {
                    LabeledContent("Manage Terms") {
                        Text("\(dictionaryStore.entries.count)")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            Section(header: Text("Updates")) {
                Toggle("Automatically Check for Updates", isOn: $autoCheckForUpdates)
                updateStatusRow
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 680)
        .onAppear { microphone.refresh() }
        .task {
            if autoCheckForUpdates, updateChecker.state == .idle {
                await updateChecker.checkNow()
            }
        }
    }

    @ViewBuilder
    private var updateStatusRow: some View {
        switch updateChecker.state {
        case .idle, .checking:
            HStack {
                Text("Checking for updates…")
                    .foregroundStyle(.secondary)
                Spacer()
                ProgressView()
                    .controlSize(.small)
            }
        case .upToDate:
            LabeledContent("Status") {
                Label("Up to Date", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Button("Check for Updates") {
                Task { await updateChecker.checkNow() }
            }
        case .updateAvailable(let update):
            VStack(alignment: .leading, spacing: 6) {
                LabeledContent("Status") {
                    Label("Version \(update.version) Available", systemImage: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                }
                HStack {
                    Button("Download") { openURL(update.downloadURL) }
                    Button("Release Notes") { openURL(update.releasePageURL) }
                }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent("Status") {
                    Label("Check Failed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task { await updateChecker.checkNow() }
                }
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginStored },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    launchAtLoginStored = newValue
                } catch {
                    print("[PreferencesView] Failed to \(newValue ? "register" : "unregister") launch-at-login: \(error)")
                }
            }
        )
    }

    @ViewBuilder
    private func permissionRow(title: String, isGranted: Bool, onFix: (() -> Void)?) -> some View {
        LabeledContent(title) {
            if isGranted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Open System Settings") { onFix?() }
            }
        }
    }

    @ViewBuilder
    private var largeModelRow: some View {
        switch llmService.largeModelState {
        case .notDownloaded:
            LabeledContent(OnDeviceLLMService.largeModelDisplayName) {
                Button("Download (\(Self.byteFormatter.string(fromByteCount: OnDeviceLLMService.largeModelApproxDownloadBytes)))") {
                    llmService.downloadLargeModel()
                }
            }
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent(OnDeviceLLMService.largeModelDisplayName) {
                    Button("Cancel") { llmService.cancelDownload() }
                }
                ProgressView(value: progress)
            }
        case .ready:
            LabeledContent(OnDeviceLLMService.largeModelDisplayName) {
                HStack {
                    Label("Downloaded", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Button("Delete", role: .destructive) { llmService.deleteLargeModel() }
                }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent(OnDeviceLLMService.largeModelDisplayName) {
                    Button("Retry") { llmService.downloadLargeModel() }
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
