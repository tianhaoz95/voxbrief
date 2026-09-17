import Foundation
import WatchConnectivity
import Combine

@MainActor
public final class WatchSyncService: NSObject, ObservableObject {
    public static let shared = WatchSyncService()
    
    @Published public private(set) var isSupported: Bool = false
    @Published public private(set) var isReachable: Bool = false
    @Published public private(set) var pendingTransfersCount: Int = 0
    @Published public private(set) var lastSyncMessage: String = "Ready"
    
    private let storage = WatchStorage.shared
    
    public override init() {
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
    
    /// Syncs all pending notes to iOS app via WCSession file transfers
    public func syncPendingNotes() {
        guard WCSession.isSupported() else { return }
        
        let pending = storage.pendingNotes()
        guard !pending.isEmpty else {
            lastSyncMessage = "No pending notes to sync"
            return
        }
        
        lastSyncMessage = "Syncing \(pending.count) note(s)..."
        
        for note in pending {
            let fileURL = storage.fileURL(for: note.localFileName)
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                storage.updateSyncState(for: note.id, state: .failed)
                continue
            }
            
            let payload = WatchSyncPayload(
                noteId: note.id,
                createdAt: note.createdAt,
                duration: note.duration,
                source: note.source,
                audioFileName: note.localFileName
            )
            
            // Initiate background file transfer
            let transfer = WCSession.default.transferFile(fileURL, metadata: payload.dictionaryRepresentation)
            storage.updateSyncState(for: note.id, state: .transferring)
            print("[WatchSyncService] Queued background file transfer for note \(note.id), transfer ID: \(transfer)")
        }
        
        pendingTransfersCount = WCSession.default.outstandingFileTransfers.count
    }
}

// MARK: - WCSessionDelegate

extension WatchSyncService: WCSessionDelegate {
    public nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            if let error = error {
                self.lastSyncMessage = "Activation error: \(error.localizedDescription)"
            } else {
                self.lastSyncMessage = "WCSession Active"
                // Trigger auto sync on activation
                self.syncPendingNotes()
            }
        }
    }
    
    public nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            if session.isReachable {
                self.syncPendingNotes()
            }
        }
    }
    
    /// Handles live messages from the iPhone, e.g. the "Ping Connected Watch" diagnostic in
    /// WatchSyncStatusView. Without this, `sendMessage(_:replyHandler:errorHandler:)` on the iOS
    /// side has nothing to deliver to on the watch and always fails with "payload could not be
    /// delivered" -- WCSessionDelegate's `didReceiveMessage` is optional, so a missing
    /// implementation compiles fine but silently drops every incoming message.
    public nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let action = message[SyncConstants.keyAction] as? String
        if action == SyncConstants.actionPing {
            replyHandler([SyncConstants.keyAction: SyncConstants.actionAck, "status": "watchOS Ready"])
        } else {
            replyHandler(["status": "acknowledged"])
        }
    }

    public nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let metadata = fileTransfer.file.metadata ?? [:]
        let payload = WatchSyncPayload.from(dictionary: metadata)
        
        Task { @MainActor in
            if let error = error {
                print("[WatchSyncService] File transfer failed: \(error)")
                if let id = payload?.noteId {
                    self.storage.updateSyncState(for: id, state: .failed)
                }
                self.lastSyncMessage = "Transfer failed: \(error.localizedDescription)"
            } else {
                print("[WatchSyncService] File transfer completed successfully!")
                if let id = payload?.noteId {
                    self.storage.updateSyncState(for: id, state: .synced)
                }
                self.lastSyncMessage = "Synced to iPhone"
            }
            self.pendingTransfersCount = WCSession.default.outstandingFileTransfers.count
        }
    }
}
