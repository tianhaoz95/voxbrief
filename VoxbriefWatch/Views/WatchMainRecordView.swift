import SwiftUI
import WatchKit

public struct WatchMainRecordView: View {
    @StateObject private var recorder = WatchAudioRecorder.shared
    @StateObject private var syncService = WatchSyncService.shared
    @StateObject private var storage = WatchStorage.shared
    
    @State private var currentSource: NoteSource = .watchApp
    @State private var showingSavedToast = false
    @State private var savedNoteDuration: String = ""
    @State private var showingNotes = false
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Spacer(minLength: 16)

                if recorder.isRecording {
                    // Active Recording UI
                    VStack(spacing: 6) {
                        Text("Recording Idea...")
                            .font(.caption2.bold())
                            .foregroundColor(.red)
                        
                        Text(recorder.recordingDuration.formattedDuration)
                            .font(.system(size: 28, weight: .semibold, design: .monospaced))
                            .foregroundColor(.primary)
                        
                        Button {
                            stopAndSave()
                        } label: {
                            CaptureWaveformView(isRecording: true, audioLevel: recorder.audioLevel, diameter: 30, systemImage: "stop.fill")
                        }
                        .buttonStyle(.plain)
                        
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
                            CaptureWaveformView(isRecording: false, audioLevel: 0, diameter: 30, systemImage: "mic.fill")
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
            .navigationDestination(isPresented: $showingNotes) {
                WatchNotesListView()
            }
            .onAppear {
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-voxbriefWatchRecording") {
                    recorder.setSimulatedRecording(active: true, duration: 18.0, level: 0.7)
                } else if args.contains("-voxbriefWatchNotes") {
                    showingNotes = true
                }
            }
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
                if (try? recorder.startRecording(source: source)) != nil {
                    WKInterfaceDevice.current().play(.start)
                }
            }
        }
    }

    private func stopAndSave() {
        if let savedNote = recorder.stopRecording(source: currentSource) {
            WKInterfaceDevice.current().play(.success)
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
        if url.host == "record" {
            let source: NoteSource = url.query?.contains("complication") == true ? .watchComplication : .watchApp
            startRecording(source: source)
        } else if url.host == "navigate" {
            let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let screen = queryItems.first(where: { $0.name == "screen" })?.value
            if screen == "notes" {
                showingNotes = true
            } else if screen == "record" {
                startRecording(source: .watchApp)
            }
        }
    }
}
