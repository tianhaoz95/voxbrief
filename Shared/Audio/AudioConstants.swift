import Foundation
import AVFoundation

public struct AudioConstants {
    public static let fileExtension = "m4a"
    public static let audioDirectoryName = "NotesAudio"
    
    /// Audio recording settings optimized for voice transcription and rapid WatchConnectivity sync
    public static var voiceRecordingSettings: [String: Any] {
        return [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 32000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 64000
        ]
    }
}
