import SwiftUI

public struct QuickRecordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recordingService = AudioRecordingService.shared
    @ObservedObject private var pipeline = NoteProcessingPipeline.shared
    @ObservedObject private var repository = NoteRepository.shared
    private let coordinator = RecordingCoordinator.shared

    @State private var hasStarted = false
    @State private var errorMessage: String? = nil
    @State private var activeNoteId: UUID? = nil
    @State private var phase: Phase = .recording

    let appendingToNoteId: UUID?
    let onFinish: () -> Void

    private enum Phase: Equatable {
        case recording
        case processing
    }

    public init(appendingToNoteId: UUID? = nil, onFinish: @escaping () -> Void) {
        self.appendingToNoteId = appendingToNoteId
        self.onFinish = onFinish
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                switch phase {
                case .recording:
                    recordingView
                case .processing:
                    processingView
                }

                Spacer()
            }
            .padding()
            .navigationTitle(phase == .recording ? "Record" : "Transcribing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if phase == .recording {
                        Button("Cancel") {
                            if recordingService.isRecording {
                                coordinator.cancelRecording()
                            }
                            dismiss()
                        }
                    } else {
                        Button("Close") {
                            onFinish()
                            dismiss()
                        }
                    }
                }
            }
            .trackFeedbackScreen("QuickRecord")
            .onAppear {
                startAutoRecord()
            }
        }
    }

    // MARK: - Recording View

    private var recordingView: some View {
        VStack(spacing: 28) {
            Text(recordingService.isRecording ? "Listening…" : "Ready to Record")
                .font(.headline)
                .foregroundStyle(recordingService.isRecording ? Color.accentColor : .secondary)

            if appendingToNoteId != nil {
                Label("Adding to existing note", systemImage: "arrow.triangle.merge")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(recordingService.recordingDuration.formattedDuration)
                .font(.system(size: 52, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .monospacedDigit()
                .contentTransition(.numericText())

            CaptureWaveformView(isRecording: recordingService.isRecording, audioLevel: recordingService.audioLevel)
                .onTapGesture {
                    toggleRecording()
                }

            Text(recordingService.isRecording ? "Tap to stop and run cleanup" : "Tap the microphone to speak your idea")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }

    // MARK: - Processing View (Streaming Transcription)

    private var processingView: some View {
        let note = activeNoteId.flatMap { repository.note(withId: $0) }
        let liveTranscript = activeNoteId.flatMap { pipeline.streamingTranscripts[$0] } ?? ""
        let isReady = note?.status == .ready
        let isFailed = note?.status == .failed
        let isCleaningLLM = note?.status == .cleaningLLM
        let textToDisplay = !liveTranscript.isEmpty ? liveTranscript : (note?.cleanedNote.isEmpty == false ? (note?.cleanedNote ?? "") : (note?.rawTranscript ?? ""))

        return VStack(spacing: 20) {
            if isFailed {
                Label("Processing Failed", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                if let error = note?.errorMessage ?? errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else if isReady {
                Label("Note Ready", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            } else if isCleaningLLM {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Polishing with on-device LLM…")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                }
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Transcribing audio…")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                }
            }

            if !textToDisplay.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(textToDisplay)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id("bottom")
                        }
                        .padding(16)
                    }
                    .frame(maxHeight: 220)
                    .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .onChange(of: textToDisplay) { _, _ in
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Decoding speech…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
                .background(Color.appSecondaryBackground.opacity(0.5), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if isReady || isFailed {
                Button(isReady ? "Done" : "Dismiss") {
                    onFinish()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            } else {
                Text("Processing continues in background if closed")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .onChange(of: note?.status) { _, newStatus in
            if newStatus == .ready {
                Task {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    onFinish()
                    dismiss()
                }
            }
        }
    }
    
    private func startAutoRecord() {
        if ProcessInfo.processInfo.arguments.contains("-voxbriefSimulateRecording") {
            recordingService.setSimulatedRecording(active: true, duration: 14.5, level: 0.68)
            hasStarted = true
            return
        }
        Task {
            let granted = await recordingService.requestPermission()
            if granted {
                do {
                    try await coordinator.beginRecording(appendingTo: appendingToNoteId)
                    hasStarted = true
                } catch {
                    errorMessage = error.localizedDescription
                }
            } else {
                errorMessage = "Microphone permission is required to record audio."
            }
        }
    }

    private func toggleRecording() {
        if recordingService.isRecording {
            if let note = coordinator.finishRecording() {
                activeNoteId = note.id
                withAnimation(.easeInOut(duration: 0.2)) {
                    phase = .processing
                }
            } else {
                onFinish()
                dismiss()
            }
        } else {
            Task {
                do {
                    try await coordinator.beginRecording(appendingTo: appendingToNoteId)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
