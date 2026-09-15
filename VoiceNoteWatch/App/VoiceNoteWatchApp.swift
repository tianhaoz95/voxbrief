import SwiftUI
import WatchKit

@main
struct VoiceNoteWatchApp: App {
    @WKExtensionDelegateAdaptor(ExtensionDelegate.self) var extensionDelegate
    
    var body: some Scene {
        WindowGroup {
            WatchMainRecordView()
        }
    }
}
