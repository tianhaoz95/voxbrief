import AVFoundation
import Foundation

/// Mac analogue of the iOS `AudioRecordingService`. macOS has no `AVAudioSession` (that's an
/// iOS-only concept for arbitrating shared audio hardware between apps), so this talks to
/// `AVAudioRecorder` directly against the default input device.
@MainActor
public final class MacAudioRecorderService: ObservableObject {
    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var audioLevel: Float = 0.0
    @Published public private(set) var recordingDuration: TimeInterval = 0.0

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var currentNoteId: UUID?
    private var currentAudioURL: URL?

    private let audioFileManager: AudioFileManager

    public init(audioFileManager: AudioFileManager) {
        self.audioFileManager = audioFileManager
    }

    public func requestPermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public func startRecording(for noteId: UUID = UUID()) throws {
        let fileURL = audioFileManager.newAudioFileURL(for: noteId)
        currentNoteId = noteId
        currentAudioURL = fileURL

        let recorder = try AVAudioRecorder(url: fileURL, settings: AudioConstants.voiceRecordingSettings)
        recorder.isMeteringEnabled = true

        guard recorder.record() else {
            throw NSError(domain: "MacAudioRecorderService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to begin recording."])
        }

        audioRecorder = recorder
        isRecording = true
        recordingDuration = 0

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.audioRecorder, recorder.isRecording else { return }
                recorder.updateMeters()
                let power = recorder.averagePower(forChannel: 0)
                let normalized = max(0.0, min(1.0, (power + 60.0) / 60.0))
                self.audioLevel = normalized
                self.recordingDuration = recorder.currentTime
            }
        }
    }

    public func stopRecording() -> (noteId: UUID, fileURL: URL, duration: TimeInterval)? {
        guard isRecording, let recorder = audioRecorder, let noteId = currentNoteId, let url = currentAudioURL else {
            return nil
        }

        let duration = recorder.currentTime
        recorder.stop()
        timer?.invalidate()
        timer = nil

        isRecording = false
        audioRecorder = nil
        audioLevel = 0
        recordingDuration = 0

        return (noteId, url, duration)
    }

    public func cancelRecording() {
        timer?.invalidate()
        timer = nil
        audioRecorder?.stop()
        if let url = currentAudioURL {
            try? FileManager.default.removeItem(at: url)
        }
        isRecording = false
        audioRecorder = nil
        audioLevel = 0
        recordingDuration = 0
        currentNoteId = nil
        currentAudioURL = nil
    }
}
