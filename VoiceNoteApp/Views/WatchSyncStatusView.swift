import SwiftUI

public struct WatchSyncStatusView: View {
    @ObservedObject var syncService: WatchSyncService
    @Environment(\.dismiss) private var dismiss
    
    public init(syncService: WatchSyncService = .shared) {
        self.syncService = syncService
    }
    
    public var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Apple Watch Connection")) {
                    HStack {
                        Label("WatchConnectivity", systemImage: "applewatch")
                        Spacer()
                        Text(syncService.isSupported ? "Supported" : "Not Supported")
                            .foregroundColor(syncService.isSupported ? .green : .red)
                    }
                    
                    HStack {
                        Text("Paired")
                        Spacer()
                        Text(syncService.isPaired ? "Yes" : "No")
                            .foregroundColor(syncService.isPaired ? .green : .secondary)
                    }
                    
                    HStack {
                        Text("Watch App Installed")
                        Spacer()
                        Text(syncService.isWatchAppInstalled ? "Yes" : "No")
                            .foregroundColor(syncService.isWatchAppInstalled ? .green : .secondary)
                    }
                    
                    HStack {
                        Text("Live Reachable")
                        Spacer()
                        Text(syncService.isReachable ? "Connected" : "Background / Idle")
                            .foregroundColor(syncService.isReachable ? .green : .orange)
                    }
                }
                
                Section(header: Text("Background Sync Statistics")) {
                    HStack {
                        Text("Transferred Memos Received")
                        Spacer()
                        Text("\(syncService.receivedFilesCount)")
                            .bold()
                    }
                    
                    if let lastSync = syncService.lastSyncDate {
                        HStack {
                            Text("Last Sync Received")
                            Spacer()
                            Text(lastSync.relativeOrFormattedString)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    HStack {
                        Text("Status Message")
                        Spacer()
                        Text(syncService.latestSyncMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("Diagnostics & Testing")) {
                    Button {
                        syncService.pingWatch()
                    } label: {
                        Label("Ping Connected Watch", systemImage: "arrow.triangle.2.circlepath")
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("How Watch Sync Works")
                            .font(.subheadline.bold())
                        Text("Recordings captured from the Apple Watch complication or Live Activity are saved locally on the watch first. When the watch connects or background fetch runs, files are automatically synced to the iPhone in the background via WCSession file transfer.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Watch Companion Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
