import Foundation
import AVFoundation
import Combine

@MainActor
public final class AudioRecordingService: NSObject, ObservableObject {
    public static let shared = AudioRecordingService()
    
    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var recordingDuration: TimeInterval = 0
    @Published public private(set) var audioLevel: Float = 0.0
    
    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var currentNoteId: UUID?
    private var currentAudioURL: URL?
    
    private let audioFileManager: AudioFileManager
    
    public init(audioFileManager: AudioFileManager = .shared) {
        self.audioFileManager = audioFileManager
        super.init()
    }
    
    public func requestPermission() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    public func startRecording(for noteId: UUID = UUID()) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        
        let fileURL = audioFileManager.newAudioFileURL(for: noteId)
        self.currentNoteId = noteId
        self.currentAudioURL = fileURL
        
        let settings = AudioConstants.voiceRecordingSettings
        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.delegate = self
        
        guard recorder.record() else {
            throw NSError(domain: "AudioRecordingService", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to begin recording."])
        }
        
        self.audioRecorder = recorder
        self.isRecording = true
        self.recordingDuration = 0
        
        // Start duration & meter timer
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self, let recorder = self.audioRecorder, recorder.isRecording else { return }
            self.recordingDuration = recorder.currentTime
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            // Normalize power from (-60dB ... 0dB) to (0.0 ... 1.0)
            let normalized = max(0.0, min(1.0, (power + 60.0) / 60.0))
            self.audioLevel = normalized
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
        
        self.isRecording = false
        self.audioRecorder = nil
        self.audioLevel = 0
        
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        
        return (noteId, url, duration)
    }
    
    public func cancelRecording() {
        timer?.invalidate()
        timer = nil
        audioRecorder?.stop()
        if let url = currentAudioURL {
            try? FileManager.default.removeItem(at: url)
        }
        self.isRecording = false
        self.audioRecorder = nil
        self.audioLevel = 0
    }
}

extension AudioRecordingService: AVAudioRecorderDelegate {
    public nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // Handled in stopRecording
    }
}
