import SwiftUI

@main
struct VoiceNoteApp: App {
    @StateObject private var watchSyncService = WatchSyncService.shared
    @StateObject private var noteRepository = NoteRepository.shared
    @StateObject private var pipeline = NoteProcessingPipeline.shared
    
    var body: some Scene {
        WindowGroup {
            NoteListView()
                .environmentObject(watchSyncService)
                .environmentObject(noteRepository)
                .environmentObject(pipeline)
        }
    }
}
