import SwiftUI

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("use_local_llm_endpoint") private var useLocalLLM: Bool = false
    @AppStorage("local_llm_endpoint_url") private var localLLMUrl: String = "http://127.0.0.1:11434/api/generate"
    @AppStorage("app_appearance") private var appearance: String = "system"
    @AppStorage(NoteProcessingPipeline.lightCleanupEnabledKey) private var lightCleanupEnabled: Bool = true
    @StateObject private var llmService = OnDeviceLLMService.shared
    @StateObject private var dictionaryStore = PersonalDictionaryStore.shared
    @State private var showingSimulationAlert = false
    @State private var simulatedTitle = ""
    @State private var keyboardStatus: KeyboardSetupStatus = .notAdded

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Appearance")) {
                    Picker("Theme", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }

                Section(
                    header: Text("Stage 2: LLM Cleanup"),
                    footer: Text("When enabled, notes are sent to the endpoint below instead of the on-device model. Off by default so nothing ever leaves this device unless you opt in.")
                ) {
                    Toggle("Use Local LLM Endpoint (Ollama)", isOn: $useLocalLLM)

                    if useLocalLLM {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Endpoint URL")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            TextField("http://127.0.0.1:11434/api/generate", text: $localLLMUrl)
                                .font(.subheadline.monospaced())
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                    } else {
                        HStack {
                            Label("Framework", systemImage: "shippingbox")
                            Spacer()
                            Text("MLX Swift")
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Label("Active Model", systemImage: "cpu")
                            Spacer()
                            Text(activeModelSummary)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section(
                    header: Text("Voxbrief Keyboard"),
                    footer: Text(keyboardStatusFooter)
                ) {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            keyboardStatusIcon
                            VStack(alignment: .leading, spacing: 2) {
                                Text(keyboardStatusTitle)
                                    .foregroundStyle(.primary)
                                Text("Tap to open Settings")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Section(
                    header: Text("Light Cleanup"),
                    footer: Text("The Light Cleanup tab shows a lightly-proofread, near-verbatim version of the transcript alongside the fully restructured note. It's generated on demand the first time you open that tab, not automatically for every note -- turn it off here to skip it entirely.")
                ) {
                    Toggle("Enable Light Cleanup", isOn: $lightCleanupEnabled)
                }

                Section(
                    header: Text("Personal Dictionary"),
                    footer: Text("Add jargon, product names, and people's names the on-device models don't know, so both Stage 1 (speech recognition) and Stage 2 (LLM cleanup) recognize and preserve them.")
                ) {
                    NavigationLink {
                        PersonalDictionaryView(store: dictionaryStore)
                    } label: {
                        HStack {
                            Label("Manage Terms", systemImage: "text.book.closed")
                            Spacer()
                            Text("\(dictionaryStore.entries.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(
                    header: Text("On-Device Models"),
                    footer: Text(OnDeviceLLMService.isSupportedOnThisDevice
                        ? "The small model ships with the app and always works offline. Download the larger model for meaningfully better cleanup quality — it only needs network once, to download."
                        : "On-device models require a real iPhone or iPad. The Simulator's graphics stack doesn't support MLX, so this won't work here — try a physical device.")
                ) {
                    modelRow(
                        name: OnDeviceLLMService.smallModelDisplayName,
                        detail: "\(OnDeviceLLMService.smallModelParameterCount) parameters · bundled with the app",
                        trailing: AnyView(
                            OnDeviceLLMService.isSupportedOnThisDevice
                                ? AnyView(
                                    Label("Ready", systemImage: "checkmark.circle.fill")
                                        .labelStyle(.titleAndIcon)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.green)
                                )
                                : AnyView(
                                    Label("Unsupported", systemImage: "exclamationmark.triangle.fill")
                                        .labelStyle(.titleAndIcon)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.red)
                                )
                        )
                    )

                    largeModelRow
                }
                
                Section(header: Text("Stage 1 ASR (Speech Recognition)")) {
                    HStack {
                        Label("Recognition Engine", systemImage: "waveform")
                        Spacer()
                        Text("Whisper (on-device, WhisperKit)")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Label("Model", systemImage: "cpu")
                        Spacer()
                        Text(ASRService.defaultModel)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Label("Language", systemImage: "globe")
                        Spacer()
                        Text("English (US)")
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Simulator & Developer Tools")) {
                    Button {
                        simulateIncomingWatchMemo()
                    } label: {
                        Label("Simulate Incoming Watch Audio Sync", systemImage: "applewatch.and.arrow.forward")
                    }
                    
                    Text("Injects a simulated voice memo from the Apple Watch to test the background sync ingestion and 2-stage processing pipeline.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("About Voxbrief")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Architecture")
                        Spacer()
                        Text("iOS + watchOS Companion")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Settings & Pipeline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Simulated Memo Ingested", isPresented: $showingSimulationAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Simulated memo '\(simulatedTitle)' has been added and processed through Stage 1 ASR and Stage 2 LLM cleanup.")
            }
            .onAppear {
                keyboardStatus = KeyboardSetupStatus.current
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Refreshes after the user goes to Settings.app to add the keyboard / grant Full
                // Access and comes back -- this sheet stays alive the whole time (backgrounding
                // the app doesn't dismiss it), so re-checking only on .onAppear would miss that.
                if newPhase == .active {
                    keyboardStatus = KeyboardSetupStatus.current
                }
            }
        }
    }

    // MARK: - Voxbrief Keyboard Status

    private var keyboardStatusTitle: String {
        switch keyboardStatus {
        case .notAdded: return "Add Voxbrief as a Keyboard"
        case .addedFullAccessUnconfirmed: return "Confirm Full Access"
        case .ready: return "Voxbrief Keyboard Ready"
        }
    }

    private var keyboardStatusFooter: String {
        switch keyboardStatus {
        case .notAdded:
            return "Settings > General > Keyboard > Keyboards > Add New Keyboard > Voxbrief."
        case .addedFullAccessUnconfirmed:
            // Deliberately doesn't say "you haven't turned this on" -- there's no API for this
            // app to check that directly (see KeyboardSetupStatus), so this state also covers
            // the case where Full Access genuinely is already on but Voxbrief hasn't detected it
            // yet, which only happens the next time the keyboard itself runs.
            return "Voxbrief is added as a keyboard, but this app can't yet confirm Full Access is on -- that's a separate switch from just adding the keyboard. If you haven't already, turn it on in Settings > General > Keyboard > Keyboards > Voxbrief > Allow Full Access. Either way, switch to the Voxbrief keyboard in any text field once (tap the globe key) to update this status."
        case .ready:
            return "Voxbrief is added as a keyboard with Full Access granted. Switch to it from any text field's globe key, then tap Record."
        }
    }

    @ViewBuilder
    private var keyboardStatusIcon: some View {
        switch keyboardStatus {
        case .notAdded:
            Image(systemName: "keyboard")
                .foregroundStyle(.red)
        case .addedFullAccessUnconfirmed:
            Image(systemName: "questionmark.circle.fill")
                .foregroundStyle(.orange)
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }

    // MARK: - On-Device Model Manager

    private var activeModelSummary: String {
        llmService.isUsingLargeModel
            ? "\(OnDeviceLLMService.largeModelDisplayName) (downloaded)"
            : "Qwen3-0.6B (bundled)"
    }

    private func modelRow(name: String, detail: String, trailing: AnyView) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var largeModelRow: some View {
        let sizeString = Self.byteFormatter.string(fromByteCount: OnDeviceLLMService.largeModelApproxDownloadBytes)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(OnDeviceLLMService.largeModelDisplayName)
                        .font(.subheadline.weight(.medium))
                    Text("\(OnDeviceLLMService.largeModelParameterCount) parameters · \(sizeString) download")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                largeModelStatusBadge
            }

            switch llmService.largeModelState {
            case .notDownloaded:
                Button {
                    llmService.downloadLargeModel()
                } label: {
                    Label("Download Model", systemImage: "arrow.down.circle")
                        .font(.subheadline.weight(.semibold))
                }

            case .downloading(let progress):
                ProgressView(value: progress)
                HStack {
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel") {
                        llmService.cancelDownload()
                    }
                    .font(.caption)
                }

            case .ready:
                Button(role: .destructive) {
                    llmService.deleteLargeModel()
                } label: {
                    Label("Delete Downloaded Model", systemImage: "trash")
                        .font(.caption)
                }

            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                Button {
                    llmService.downloadLargeModel()
                } label: {
                    Label("Retry Download", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var largeModelStatusBadge: some View {
        switch llmService.largeModelState {
        case .notDownloaded:
            Text("Not Downloaded")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .downloading:
            Label("Downloading", systemImage: "arrow.down.circle")
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        case .failed:
            Label("Failed", systemImage: "exclamationmark.triangle.fill")
                .labelStyle(.titleAndIcon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
        }
    }

    private func simulateIncomingWatchMemo() {
        let noteId = UUID()
        let sampleTranscript = "Hey, so um we need to build the authentication flow for the voice note companion app. First condition is if biometric auth is enabled, use Face ID. Second condition is if user cancels Face ID, fall back to device passcode. Then make sure to encrypt all audio files on disk with AES-256. Requirements include instant lock on backgrounding and support for watch face complications. Remember to check with the security team."
        
        Task {
            let llmResult = try? await LLMCopywriterService.shared.processTranscript(sampleTranscript, mode: .full)
            let lightResult = try? await LLMCopywriterService.shared.processTranscript(sampleTranscript, mode: .light)

            let simulatedNote = VoiceNote(
                id: noteId,
                createdAt: Date(),
                duration: 35.0,
                audioFileName: nil,
                title: llmResult?.title ?? "Authentication Flow Spec",
                summary: llmResult?.summary ?? "Biometric auth and encryption requirements captured from Apple Watch.",
                rawTranscript: sampleTranscript,
                cleanedNote: llmResult?.cleanedMarkdown ?? sampleTranscript,
                requirements: llmResult?.requirements ?? [
                    "Encrypt all audio files on disk with AES-256",
                    "Instant lock on backgrounding",
                    "Support for watch face complications"
                ],
                conditions: llmResult?.conditions ?? [
                    "If biometric auth is enabled, use Face ID",
                    "If user cancels Face ID, fall back to device passcode"
                ],
                actionItems: llmResult?.actionItems ?? [
                    "Check with the security team"
                ],
                tags: llmResult?.tags ?? ["#iOS", "#watchOS", "#security"],
                status: .ready,
                source: .watchComplication,
                cleanupEngine: llmResult?.engine,
                lightCleanedNote: lightResult?.cleanedMarkdown,
                lightCleanupEngine: lightResult?.engine
            )
            
            await NoteRepository.shared.save(simulatedNote)
            simulatedTitle = simulatedNote.title
            showingSimulationAlert = true
        }
    }
}
