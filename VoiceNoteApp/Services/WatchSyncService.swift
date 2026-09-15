import Foundation
import WatchConnectivity
import Combine

@MainActor
public final class WatchSyncService: NSObject, ObservableObject {
    public static let shared = WatchSyncService()
    
    @Published public private(set) var isSupported: Bool = false
    @Published public private(set) var isPaired: Bool = false
    @Published public private(set) var isWatchAppInstalled: Bool = false
    @Published public private(set) var isReachable: Bool = false
    @Published public private(set) var lastSyncDate: Date?
    @Published public private(set) var receivedFilesCount: Int = 0
    @Published public private(set) var latestSyncMessage: String = "Ready"
    
    private let repository: NoteRepository
    private let audioFileManager: AudioFileManager
    private let pipeline: NoteProcessingPipeline
    
    public init(
        repository: NoteRepository = .shared,
        audioFileManager: AudioFileManager = .shared,
        pipeline: NoteProcessingPipeline = .shared
    ) {
        self.repository = repository
        self.audioFileManager = audioFileManager
        self.pipeline = pipeline
        super.init()
        
        setupSession()
    }
    
    public func setupSession() {
        guard WCSession.isSupported() else {
            isSupported = false
            return
        }
        
        isSupported = true
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }
    
    /// Requests connected watch to trigger an immediate background sync check
    public func pingWatch() {
        guard WCSession.default.isReachable else {
            latestSyncMessage = "Watch is not reachable right now."
            return
        }
        
        WCSession.default.sendMessage([SyncConstants.keyAction: SyncConstants.actionPing], replyHandler: { reply in
            Task { @MainActor in
                self.latestSyncMessage = "Watch responded: \(reply)"
            }
        }, errorHandler: { error in
            Task { @MainActor in
                self.latestSyncMessage = "Ping failed: \(error.localizedDescription)"
            }
        })
    }
}

// MARK: - WCSessionDelegate

extension WatchSyncService: WCSessionDelegate {
    public nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isReachable = session.isReachable
            if let error = error {
                self.latestSyncMessage = "Activation error: \(error.localizedDescription)"
            } else {
                self.latestSyncMessage = "Connected (state: \(activationState.rawValue))"
            }
        }
    }
    
    public nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in
            self.latestSyncMessage = "Session became inactive"
        }
    }
    
    public nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate if deactivated (e.g. switching watches)
        WCSession.default.activate()
    }
    
    public nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
        }
    }
    
    /// Handles audio file transferred from Apple Watch in the background
    public nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metadata = file.metadata ?? [:]
        let payload = WatchSyncPayload.from(dictionary: metadata)
        let noteId = payload?.noteId ?? UUID()
        let createdAt = payload?.createdAt ?? Date()
        let duration = payload?.duration ?? 0
        let source = payload?.source ?? .watchApp
        
        Task { @MainActor in
            do {
                // 1. Copy incoming audio file to permanent storage
                let persistentFileName = try self.audioFileManager.copyIncomingAudioFile(
                    from: file.fileURL,
                    noteId: noteId
                )
                
                // 2. Register initial voice note entry in repository
                let note = VoiceNote(
                    id: noteId,
                    createdAt: createdAt,
                    duration: duration,
                    audioFileName: persistentFileName,
                    title: "Incoming Note...",
                    summary: "Processing audio from \(source.displayName)...",
                    rawTranscript: "",
                    cleanedNote: "",
                    requirements: [],
                    conditions: [],
                    actionItems: [],
                    tags: [],
                    status: .syncing,
                    source: source
                )
                self.repository.save(note)
                self.receivedFilesCount += 1
                self.lastSyncDate = Date()
                self.latestSyncMessage = "Received voice note from \(source.displayName)"
                
                // 3. Trigger 2-Stage Pipeline (ASR + LLM)
                await self.pipeline.process(note: note)
                
            } catch {
                print("[WatchSyncService] Error handling incoming file: \(error)")
                self.latestSyncMessage = "File handling error: \(error.localizedDescription)"
            }
        }
    }
    
    /// Handles user info dictionary sync
    public nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        Task { @MainActor in
            self.latestSyncMessage = "Received userInfo: \(userInfo.keys.joined(separator: ", "))"
        }
    }
    
    /// Handles live messages
    public nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        Task { @MainActor in
            let action = message[SyncConstants.keyAction] as? String
            if action == SyncConstants.actionPing {
                replyHandler([SyncConstants.keyAction: SyncConstants.actionAck, "status": "iOS Ready"])
            } else {
                replyHandler(["status": "acknowledged"])
            }
        }
    }
}
