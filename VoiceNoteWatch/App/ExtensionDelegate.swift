import Foundation
import WatchKit

public final class ExtensionDelegate: NSObject, WKExtensionDelegate {
    
    public func applicationDidFinishLaunching() {
        // Activate WCSession immediately on launch
        _ = WatchSyncService.shared
        scheduleNextBackgroundRefresh()
    }
    
    public func applicationDidBecomeActive() {
        // Trigger sync check whenever app becomes active
        WatchSyncService.shared.syncPendingNotes()
    }
    
    public func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let refreshTask as WKApplicationRefreshBackgroundTask:
                // Handle periodic background fetch / sync
                print("[ExtensionDelegate] Running periodic background refresh task")
                
                Task { @MainActor in
                    WatchSyncService.shared.syncPendingNotes()
                    self.scheduleNextBackgroundRefresh()
                    refreshTask.setTaskCompletedWithSnapshot(false)
                }
                
            case let snapshotTask as WKSnapshotRefreshBackgroundTask:
                snapshotTask.setTaskCompleted(restoredDefaultState: true, estimatedSnapshotExpiration: Date.distantFuture, userInfo: nil)
                
            case let urlSessionTask as WKURLSessionRefreshBackgroundTask:
                urlSessionTask.setTaskCompletedWithSnapshot(false)
                
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
    
    /// Schedules periodic background refresh (every 15-30 minutes)
    public func scheduleNextBackgroundRefresh() {
        let fireDate = Date(timeIntervalSinceNow: 15 * 60)
        WKExtension.shared().scheduleBackgroundRefresh(
            withPreferredDate: fireDate,
            userInfo: nil
        ) { error in
            if let error = error {
                print("[ExtensionDelegate] Failed to schedule background refresh: \(error)")
            } else {
                print("[ExtensionDelegate] Scheduled background refresh for \(fireDate)")
            }
        }
    }
}
