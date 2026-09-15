import Foundation
import AVFoundation
import Combine

@MainActor
public final class WatchAudioRecorder: NSObject, ObservableObject {
    public static let shared = WatchAudioRecorder()
    
    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var recordingDuration: TimeInterval = 0
    @Published public private(set) var audioLevel: Float = 0.0
    
    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var currentNoteId: UUID?
    private var currentFileURL: URL?
    
    private let storage = WatchStorage.shared
    
    public override init() {
        super.init()
    }
    
    public func requestPermission() async -> Bool {
        if #available(watchOS 10.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        } else {
            return await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    public func startRecording(source: NoteSource = .watchApp) throws -> UUID {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)
        
        let noteId = UUID()
        let fileURL = storage.newRecordingURL(for: noteId)
        self.currentNoteId = noteId
        self.currentFileURL = fileURL
        
        let settings = AudioConstants.voiceRecordingSettings
        let recorder = try AVAudioRecorder(url: fileURL, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.delegate = self
        
        guard recorder.record() else {
            throw NSError(domain: "WatchAudioRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to record on watchOS."])
        }
        
        self.audioRecorder = recorder
        self.isRecording = true
        self.recordingDuration = 0
        
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let recorder = self.audioRecorder, recorder.isRecording else { return }
            self.recordingDuration = recorder.currentTime
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            let normalized = max(0.0, min(1.0, (power + 55.0) / 55.0))
            self.audioLevel = normalized
        }
        
        return noteId
    }
    
    public func stopRecording(source: NoteSource = .watchApp) -> WatchLocalNote? {
        guard isRecording, let recorder = audioRecorder, let noteId = currentNoteId, let fileURL = currentFileURL else {
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
        
        let fileName = fileURL.lastPathComponent
        let note = WatchLocalNote(
            id: noteId,
            createdAt: Date(),
            duration: duration,
            localFileName: fileName,
            source: source,
            syncState: .pending
        )
        
        storage.addNote(note)
        return note
    }
    
    public func cancelRecording() {
        timer?.invalidate()
        timer = nil
        audioRecorder?.stop()
        if let url = currentFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        self.isRecording = false
        self.audioRecorder = nil
        self.audioLevel = 0
    }
}

extension WatchAudioRecorder: AVAudioRecorderDelegate {
    public nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        // Handled in stopRecording
    }
}
