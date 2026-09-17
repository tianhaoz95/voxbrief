import SwiftUI
import WatchKit

@main
struct VoxbriefWatchApp: App {
    @WKExtensionDelegateAdaptor(ExtensionDelegate.self) var extensionDelegate
    
    var body: some Scene {
        WindowGroup {
            WatchMainRecordView()
        }
    }
}
