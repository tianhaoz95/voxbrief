import UIKit
import SwiftUI

/// The keyboard extension's entry point (`NSExtensionPrincipalClass` in Info.plist, wired via
/// project.yml). Hosts `KeyboardView` (SwiftUI) and translates its key taps into
/// `textDocumentProxy` calls -- the view itself has no access to that, by design, so it can't be
/// tested/previewed without a real host text field.
///
/// Two responsibilities beyond normal typing:
/// 1. The Record bar opens the main Voxbrief app, passing `source=keyboard` so
///    `VoxbriefApp.handleDeepLink` routes to `KeyboardRecordSheet` instead of the normal record
///    sheet. This -- like `insertPendingPasteIfAny` below -- only actually works once the user has
///    granted "Allow Full Access": opening a URL is one of the capabilities iOS blocks from a
///    restricted keyboard extension (same trust boundary as network access), so without it this
///    is a silent no-op by OS policy, not a bug. See `KeyboardView`'s dynamic Record label and
///    `KeyboardSetupStatus`/`SettingsView` in the main app, which exist specifically to make that
///    prerequisite obvious instead of the button just doing nothing with no explanation. See
///    `openVoxbrief` for why this tries two different techniques, and surfaces failure in the UI
///    when it can't open at all, rather than trusting either one blindly.
/// 2. Every time this extension becomes active again (the user switched back manually -- see
///    CLAUDE.md on why that's a required tap, not something this can automate), it checks
///    `KeyboardHandoff` for a result waiting from that flow and inserts it immediately.
public final class KeyboardViewController: UIInputViewController {
    private var hostingController: UIHostingController<KeyboardView>?
    private var lastOpenAttemptFailed = false

    public override func viewDidLoad() {
        super.viewDidLoad()
        installKeyboardView()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        lastOpenAttemptFailed = false
        hostingController?.rootView = makeKeyboardView()
        if hasFullAccess {
            // The only way the main app's Settings screen can ever learn this -- see
            // KeyboardHandoff.reportFullAccessGranted's doc comment.
            KeyboardHandoff.reportFullAccessGranted()
        }
        insertPendingPasteIfAny()
    }

    public override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        insertPendingPasteIfAny()
    }

    private func installKeyboardView() {
        let hosting = UIHostingController(rootView: makeKeyboardView())
        hostingController = hosting

        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hosting.didMove(toParent: self)
    }

    private func makeKeyboardView() -> KeyboardView {
        KeyboardView(
            hasFullAccess: hasFullAccess,
            openFailed: lastOpenAttemptFailed,
            onKey: { [weak self] key in self?.handle(key) },
            onRecord: { [weak self] in self?.openVoxbrief() },
            onNextKeyboard: { [weak self] in self?.advanceToNextInputMode() }
        )
    }

    private func handle(_ key: KeyboardKey) {
        switch key {
        case .character(let text):
            textDocumentProxy.insertText(text)
        case .backspace:
            textDocumentProxy.deleteBackward()
        case .space:
            textDocumentProxy.insertText(" ")
        case .newline:
            textDocumentProxy.insertText("\n")
        }
    }

    /// Tries the officially documented `extensionContext?.open(_:completionHandler:)` first --
    /// it self-reports success/failure via its completion handler, which the responder-chain
    /// trick below can't do. Both techniques require "Allow Full Access"; if that isn't granted
    /// they fail the same silent way, which is correct OS policy, not a bug in either one. If
    /// `open` reports failure (or has no extension context to call it on, which happens if this
    /// is ever invoked before the extension is fully attached), falls back to walking the
    /// responder chain to the host app's real `UIApplication` instance and invoking the
    /// deprecated `openURL(_:)` via `perform(_:with:)` -- a technique some keyboard extensions
    /// need instead, apparently varying by iOS version/device. Either way, if nothing actually
    /// worked, that's surfaced in the keyboard's own UI (`KeyboardView`'s `openFailed`) instead
    /// of leaving the user staring at a button that visibly did nothing.
    private func openVoxbrief() {
        guard let url = URL(string: "voxbrief://record?source=keyboard") else { return }
        lastOpenAttemptFailed = false
        guard let extensionContext else {
            reportOpenResult(succeeded: openViaResponderChain(url))
            return
        }
        extensionContext.open(url) { [weak self] success in
            guard let self else { return }
            DispatchQueue.main.async {
                self.reportOpenResult(succeeded: success || self.openViaResponderChain(url))
            }
        }
    }

    @discardableResult
    private func openViaResponderChain(_ url: URL) -> Bool {
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.perform(#selector(UIApplication.openURL(_:)), with: url)
                return true
            }
            responder = current.next
        }
        return false
    }

    private func reportOpenResult(succeeded: Bool) {
        // Only worth flagging when Full Access is actually on -- otherwise the Record label
        // already explains why nothing happened, and this would just be a redundant, scarier
        // second warning about the same known cause.
        lastOpenAttemptFailed = hasFullAccess && !succeeded
        hostingController?.rootView = makeKeyboardView()
    }

    /// A no-op (returns immediately) unless Full Access is granted -- `KeyboardHandoff` needs the
    /// shared App Group container, which iOS blocks from a restricted keyboard.
    private func insertPendingPasteIfAny() {
        guard hasFullAccess, let text = KeyboardHandoff.consumePendingPaste() else { return }
        textDocumentProxy.insertText(text)
    }
}
