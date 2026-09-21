import SwiftUI

public struct QuickRecordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recordingService = AudioRecordingService.shared
    private let coordinator = RecordingCoordinator.shared
    @State private var hasStarted = false
    @State private var errorMessage: String? = nil

    let appendingToNoteId: UUID?
    let onFinish: () -> Void

    public init(appendingToNoteId: UUID? = nil, onFinish: @escaping () -> Void) {
        self.appendingToNoteId = appendingToNoteId
        self.onFinish = onFinish
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

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

                Spacer()
            }
            .padding()
            .navigationTitle("Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if recordingService.isRecording {
                            coordinator.cancelRecording()
                        }
                        dismiss()
                    }
                }
            }
            .onAppear {
                startAutoRecord()
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
            if coordinator.finishRecording() != nil {
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
