import SwiftUI

public struct WatchMainRecordView: View {
    @StateObject private var recorder = WatchAudioRecorder.shared
    @StateObject private var syncService = WatchSyncService.shared
    @StateObject private var storage = WatchStorage.shared
    
    @State private var currentSource: NoteSource = .watchApp
    @State private var showingSavedToast = false
    @State private var savedNoteDuration: String = ""
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                if recorder.isRecording {
                    // Active Recording UI
                    VStack(spacing: 6) {
                        Text("Recording Idea...")
                            .font(.caption2.bold())
                            .foregroundColor(.red)
                        
                        Text(recorder.recordingDuration.formattedDuration)
                            .font(.system(size: 28, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                        
                        // Audio level pulsing meter
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.25))
                                .frame(
                                    width: 60 + CGFloat(recorder.audioLevel * 30),
                                    height: 60 + CGFloat(recorder.audioLevel * 30)
                                )
                                .animation(.easeOut(duration: 0.1), value: recorder.audioLevel)
                            
                            Button {
                                stopAndSave()
                            } label: {
                                Image(systemName: "stop.fill")
                                    .font(.title3)
                                    .foregroundColor(.white)
                                    .frame(width: 54, height: 54)
                                    .background(Color.red)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                        
                        Text("Tap to stop & save")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                } else {
                    // Ready to Record UI
                    VStack(spacing: 6) {
                        if showingSavedToast {
                            Text("Saved! Syncing...")
                                .font(.caption2.bold())
                                .foregroundColor(.green)
                        } else {
                            Text("Quick Idea Capture")
                                .font(.caption2.bold())
                                .foregroundColor(.secondary)
                        }
                        
                        Button {
                            startRecording(source: .watchApp)
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color.blue.opacity(0.2))
                                    .frame(width: 72, height: 72)
                                
                                Circle()
                                    .fill(Color.blue)
                                    .frame(width: 58, height: 58)
                                
                                Image(systemName: "mic.fill")
                                    .font(.title2)
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.plain)
                        
                        Text("Tap to record")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer(minLength: 2)
                
                // Bottom Bar: Local Queue & Force Sync
                HStack {
                    NavigationLink(destination: WatchNotesListView()) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                            Text("\(storage.notes.count)")
                        }
                        .font(.caption2)
                    }
                    
                    Spacer()
                    
                    if storage.pendingNotes().count > 0 {
                        Button {
                            syncService.syncPendingNotes()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("\(storage.pendingNotes().count)")
                            }
                            .font(.caption2.bold())
                            .foregroundColor(.orange)
                        }
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(4)
            .navigationTitle("VoiceNote")
            .onOpenURL { url in
                handleDeepLink(url: url)
            }
        }
    }
    
    private func startRecording(source: NoteSource) {
        currentSource = source
        Task {
            let granted = await recorder.requestPermission()
            if granted {
                _ = try? recorder.startRecording(source: source)
            }
        }
    }
    
    private func stopAndSave() {
        if let savedNote = recorder.stopRecording(source: currentSource) {
            savedNoteDuration = savedNote.duration.formattedDuration
            showingSavedToast = true
            
            // Queue sync immediately
            syncService.syncPendingNotes()
            
            // Hide toast after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                showingSavedToast = false
            }
        }
    }
    
    private func handleDeepLink(url: URL) {
        // Deep link from complication: voicenote://record?source=watch_complication
        if url.host == "record" {
            let source: NoteSource = url.query?.contains("complication") == true ? .watchComplication : .watchApp
            startRecording(source: source)
        }
    }
}
