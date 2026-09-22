import AppKit
import Combine
import SwiftUI

/// Hosts `OverlayView` in a small floating, non-activating panel that appears near the top of the
/// screen whenever a capture is in progress.
///
/// The panel deliberately never becomes key/main window (`.nonactivatingPanel`, and it's never
/// sent `makeKeyAndOrderFront`) -- the whole point of the feature is that the text field the user
/// was typing into keeps focus the entire time, so the eventual paste lands there. That's also why
/// there's no keyboard shortcut for Cancel/Complete (Escape/Return): wiring those up would require
/// the panel to accept key events, which would steal focus from the target field. Only the mouse
/// buttons work, which a non-activating panel can still receive without becoming key.
@MainActor
public final class OverlayWindowController {
    private let panel: NSPanel
    private var cancellable: AnyCancellable?
    private let coordinator: CaptureCoordinator

    public init(coordinator: CaptureCoordinator, recorder: MacAudioRecorderService) {
        self.coordinator = coordinator
        let content = OverlayView(coordinator: coordinator, recorder: recorder)
        let hosting = NSHostingView(rootView: content)
        let size = NSSize(width: 360, height: 165)
        hosting.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = hosting
        panel.isReleasedWhenClosed = false
        self.panel = panel

        cancellable = coordinator.$state.sink { [weak self] state in
            self?.handle(state: state)
        }
    }

    private func handle(state: CaptureCoordinator.State) {
        switch state {
        case .idle:
            panel.orderOut(nil)
        case .listening, .processing, .success, .failed:
            // The Notes browser's "Add Recording" sheet (MacAddRecordingSheet) already has its own
            // full recording UI, including Cancel. Showing this floating HUD at the same time let
            // either surface drive `state` independently -- e.g. cancelling from here left that
            // sheet open with no active recording and no feedback that anything had changed.
            guard !coordinator.isAppendCapture else {
                panel.orderOut(nil)
                return
            }
            positionPanel()
            panel.orderFrontRegardless()
        }
    }

    private func positionPanel() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let size = panel.frame.size
        let originX = screenFrame.midX - size.width / 2
        let originY = screenFrame.maxY - size.height - 80
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }
}
