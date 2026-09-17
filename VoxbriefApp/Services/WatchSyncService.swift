import Foundation
import UIKit
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

    /// Tracks the currently-running "ingest + process an incoming file" background task, if any,
    /// so its expiration handler and the normal completion path can't both try to end it.
    private var activeBackgroundTaskId: UIBackgroundTaskIdentifier = .invalid

    /// Ends the active background task assertion exactly once, however processing finished
    /// (completed normally, threw, or the OS called the expiration handler because time ran out).
    private func endActiveBackgroundTask() {
        guard activeBackgroundTaskId != .invalid else { return }
        UIApplication.shared.endBackgroundTask(activeBackgroundTaskId)
        activeBackgroundTaskId = .invalid
    }
    
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
    
    /// Handles audio file transferred from Apple Watch in the background.
    ///
    /// `file.fileURL` points to a temporary location that WatchConnectivity deletes as soon as
    /// this method returns, so the copy to permanent storage must happen synchronously here --
    /// deferring it into a dispatched `Task` (as an earlier version of this did) loses the race
    /// and the source file is gone by the time the copy runs, silently dropping every transfer.
    public nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let metadata = file.metadata ?? [:]
        let payload = WatchSyncPayload.from(dictionary: metadata)
        let noteId = payload?.noteId ?? UUID()
        let createdAt = payload?.createdAt ?? Date()
        let duration = payload?.duration ?? 0
        let source = payload?.source ?? .watchApp

        do {
            let persistentFileName = try self.audioFileManager.copyIncomingAudioFile(
                from: file.fileURL,
                noteId: noteId
            )

            Task { @MainActor in
                // The app may be launched into the background just to receive this file, with only
                // a short OS-granted execution window before suspension. Without this assertion,
                // Stage 1/2 processing (model load + inference) can easily exceed that window and
                // get killed mid-flight, leaving the note stuck at a non-terminal status forever --
                // this extends the window and gives processing a real chance to reach .ready/.failed.
                self.activeBackgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "IngestAndProcessVoiceNote") { [weak self] in
                    self?.endActiveBackgroundTask()
                }
                defer { self.endActiveBackgroundTask() }

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

                // Trigger the 2-Stage Pipeline (ASR + LLM)
                await self.pipeline.process(note: note)
            }
        } catch {
            print("[WatchSyncService] Error handling incoming file: \(error)")
            Task { @MainActor in
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
