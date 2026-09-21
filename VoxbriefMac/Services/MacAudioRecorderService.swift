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

    /// Resolves microphone access before recording. Critically, this is what actually registers
    /// the app in System Settings > Privacy & Security > Microphone in the first place -- opening
    /// an `AVAudioRecorder` on its own does not reliably trigger the TCC prompt on macOS the way
    /// `AVCaptureDevice.requestAccess` does. `.notDetermined` prompts the OS's native dialog once;
    /// `.denied`/`.restricted` return `false` without prompting (the OS never re-prompts once
    /// denied), which is the caller's cue to point the user at System Settings instead.
    public func ensureMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
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
