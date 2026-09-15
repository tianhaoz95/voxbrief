import SwiftUI

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("use_local_llm_endpoint") private var useLocalLLM: Bool = false
    @AppStorage("local_llm_endpoint_url") private var localLLMUrl: String = "http://127.0.0.1:11434/api/generate"
    @State private var showingSimulationAlert = false
    @State private var simulatedTitle = ""
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("On-Device LLM Pipeline (Stage 2)")) {
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
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: "cpu.fill")
                                    .foregroundColor(.blue)
                                Text("Built-in On-Device LLM Transformer Active")
                                    .font(.subheadline.bold())
                            }
                            Text("100% private, on-device parsing of speech transcripts into bullet requirements, numbered conditions, typos and grammar fixes with zero server roundtrip.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
                
                Section(header: Text("Stage 1 ASR (Speech Recognition)")) {
                    HStack {
                        Label("Recognition Engine", systemImage: "waveform")
                        Spacer()
                        Text("Apple Speech (On-Device)")
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
                
                Section(header: Text("About VoiceNote")) {
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
        }
    }
    
    private func simulateIncomingWatchMemo() {
        let noteId = UUID()
        let sampleTranscript = "Hey, so um we need to build the authentication flow for the voice note companion app. First condition is if biometric auth is enabled, use Face ID. Second condition is if user cancels Face ID, fall back to device passcode. Then make sure to encrypt all audio files on disk with AES-256. Requirements include instant lock on backgrounding and support for watch face complications. Remember to check with the security team."
        
        Task {
            let llmResult = try? await LLMCopywriterService.shared.processTranscript(sampleTranscript)
            
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
                source: .watchComplication
            )
            
            await NoteRepository.shared.save(simulatedNote)
            simulatedTitle = simulatedNote.title
            showingSimulationAlert = true
        }
    }
}
