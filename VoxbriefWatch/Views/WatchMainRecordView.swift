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
            VStack(spacing: 6) {
                if recorder.isRecording {
                    // MARK: - Active Recording State
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                            Text("RECORDING")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .tracking(0.8)
                                .foregroundColor(.red)
                        }
                        .padding(.top, 2)
                        
                        Text(recorder.recordingDuration.formattedDuration)
                            .font(.system(size: 26, weight: .bold, design: .monospaced))
                            .foregroundColor(.primary)
                            .monospacedDigit()
                        
                        Button {
                            stopAndSave()
                        } label: {
                            CaptureWaveformView(isRecording: true, audioLevel: recorder.audioLevel, diameter: 44, systemImage: "stop.fill")
                        }
                        .buttonStyle(.plain)
                        
                        Text("Tap to stop & save")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                } else {
                    // MARK: - Ready / Idle State
                    VStack(spacing: 4) {
                        VoxbriefLogoView(size: .watch)
                            .padding(.top, 2)
                        
                        if showingSavedToast {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(.green)
                                Text("Saved (\(savedNoteDuration))")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.green)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15), in: Capsule())
                        } else {
                            Text("Capture Idea")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        
                        Button {
                            startRecording(source: .watchApp)
                        } label: {
                            CaptureWaveformView(isRecording: false, audioLevel: 0, diameter: 44, systemImage: "mic.fill")
                        }
                        .buttonStyle(.plain)
                        
                        Text("Tap to record")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer(minLength: 0)
                
                // MARK: - Bottom Pill Dock
                HStack(spacing: 8) {
                    NavigationLink(destination: WatchNotesListView()) {
                        HStack(spacing: 5) {
                            Image(systemName: "tray.full.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text("\(storage.notes.count)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    if storage.pendingNotes().count > 0 {
                        Button {
                            syncService.syncPendingNotes()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10, weight: .bold))
                                Text("\(storage.pendingNotes().count)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.orange)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.18), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                            Text("Synced")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(Color.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 2)
            }
            .padding(.horizontal, 4)
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
