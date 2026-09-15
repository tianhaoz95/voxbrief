import SwiftUI

public struct QuickRecordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recordingService = AudioRecordingService.shared
    @State private var hasStarted = false
    @State private var errorMessage: String? = nil
    
    let onFinish: (VoiceNote) -> Void
    
    public init(onFinish: @escaping (VoiceNote) -> Void) {
        self.onFinish = onFinish
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                Spacer()
                
                // Status banner
                Text(recordingService.isRecording ? "Listening & Capturing Idea..." : "Ready to Record")
                    .font(.headline)
                    .foregroundColor(recordingService.isRecording ? .blue : .secondary)
                
                // Timer counter
                Text(recordingService.recordingDuration.formattedDuration)
                    .font(.system(size: 54, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
                
                // Pulsing Waveform circle
                ZStack {
                    if recordingService.isRecording {
                        Circle()
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 140 + CGFloat(recordingService.audioLevel * 70),
                                   height: 140 + CGFloat(recordingService.audioLevel * 70))
                            .animation(.easeInOut(duration: 0.1), value: recordingService.audioLevel)
                    }
                    
                    Circle()
                        .fill(recordingService.isRecording ? Color.red : Color.blue)
                        .frame(width: 110, height: 110)
                        .shadow(radius: 8)
                    
                    Image(systemName: recordingService.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.white)
                }
                .onTapGesture {
                    toggleRecording()
                }
                
                Text(recordingService.isRecording ? "Tap button to stop and run 2-stage cleanup" : "Tap microphone to speak your idea")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Record Voice Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if recordingService.isRecording {
                            recordingService.cancelRecording()
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
        Task {
            let granted = await recordingService.requestPermission()
            if granted {
                do {
                    try recordingService.startRecording()
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
            if let result = recordingService.stopRecording() {
                let note = VoiceNote(
                    id: result.noteId,
                    createdAt: Date(),
                    duration: result.duration,
                    audioFileName: "\(result.noteId.uuidString).\(AudioConstants.fileExtension)",
                    title: "Processing Voice Note...",
                    summary: "Extracting transcript and structuring requirements...",
                    rawTranscript: "",
                    cleanedNote: "",
                    requirements: [],
                    conditions: [],
                    actionItems: [],
                    tags: [],
                    status: .transcribingASR,
                    source: .phoneApp
                )
                onFinish(note)
                dismiss()
            }
        } else {
            do {
                try recordingService.startRecording()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
