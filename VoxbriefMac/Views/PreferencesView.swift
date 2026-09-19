import AVFoundation
import ServiceManagement
import SwiftUI

/// Mac Settings window. Mirrors the iPhone app's `SettingsView` where it makes sense to behave
/// identically (same `@AppStorage` keys for the Ollama toggle, same `OnDeviceLLMService` for the
/// on-device model tier) plus the Mac-only permission/launch-at-login controls this app needs.
struct PreferencesView: View {
    @AppStorage("use_local_llm_endpoint") private var useLocalLLM: Bool = false
    @AppStorage("local_llm_endpoint_url") private var localLLMUrl: String = "http://127.0.0.1:11434/api/generate"
    @AppStorage("launch_at_login") private var launchAtLoginStored: Bool = false

    @ObservedObject var accessibility: AccessibilityPermissionManager
    @StateObject private var llmService = OnDeviceLLMService.shared

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
                    isGranted: AVCaptureDeviceAudioAuthorization.isAuthorized,
                    onFix: nil
                )
                permissionRow(
                    title: "Accessibility",
                    isGranted: accessibility.isTrusted,
                    onFix: accessibility.isTrusted ? nil : { accessibility.requestPrompt(); accessibility.openSystemSettings() }
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
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 460)
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

/// Thin wrapper so the permissions section can read current microphone authorization
/// synchronously without needing an async round trip just to render a checkmark.
private enum AVCaptureDeviceAudioAuthorization {
    static var isAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }
}
