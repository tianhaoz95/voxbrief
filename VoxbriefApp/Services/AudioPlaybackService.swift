import Foundation
import AVFoundation
import Combine

@MainActor
public final class AudioPlaybackService: NSObject, ObservableObject {
    public static let shared = AudioPlaybackService()
    
    @Published public private(set) var isPlaying: Bool = false
    @Published public private(set) var currentTime: TimeInterval = 0
    @Published public private(set) var duration: TimeInterval = 0
    @Published public private(set) var currentlyPlayingFileName: String?
    
    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?
    private let audioFileManager: AudioFileManager
    
    public init(audioFileManager: AudioFileManager = .shared) {
        self.audioFileManager = audioFileManager
        super.init()
    }
    
    public func play(fileName: String) {
        if currentlyPlayingFileName == fileName && audioPlayer != nil {
            if isPlaying {
                pause()
            } else {
                resume()
            }
            return
        }
        
        stop()
        
        let fileURL = audioFileManager.url(for: fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("[AudioPlaybackService] Audio file not found at \(fileURL.path)")
            return
        }
        
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            
            let player = try AVAudioPlayer(contentsOf: fileURL)
            player.delegate = self
            player.prepareToPlay()
            player.play()
            
            self.audioPlayer = player
            self.currentlyPlayingFileName = fileName
            self.duration = player.duration
            self.currentTime = 0
            self.isPlaying = true
            
            startProgressTimer()
        } catch {
            print("[AudioPlaybackService] Failed to play audio: \(error)")
        }
    }
    
    public func pause() {
        audioPlayer?.pause()
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }
    
    public func resume() {
        guard let player = audioPlayer else { return }
        player.play()
        isPlaying = true
        startProgressTimer()
    }
    
    public func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentTime = 0
        currentlyPlayingFileName = nil
        timer?.invalidate()
        timer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    public func seek(to progress: Double) {
        guard let player = audioPlayer else { return }
        let targetTime = player.duration * max(0.0, min(1.0, progress))
        player.currentTime = targetTime
        self.currentTime = targetTime
    }
    
    private func startProgressTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.audioPlayer else { return }
            self.currentTime = player.currentTime
        }
    }
}

extension AudioPlaybackService: AVAudioPlayerDelegate {
    public nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stop()
        }
    }
}
