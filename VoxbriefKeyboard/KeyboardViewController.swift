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
    /// Identifies the most recent `openVoxbrief()` call so a stale timer or completion handler
    /// from an earlier tap can't clobber state for a newer one (or one that already succeeded).
    private var openAttemptToken = UUID()
    /// Temporary, on-screen diagnostic trail for `openVoxbrief()` -- both known techniques for a
    /// keyboard extension to open its host app are reported (by other apps that do it, and by
    /// Apple's own docs for `extensionContext.open`) to actually work, so a categorical "this
    /// isn't possible" conclusion was wrong; there's a specific, fixable reason it isn't working
    /// *here*, and this narrows down which step. Remove once that's found -- see KeyboardView.
    private var diagnostics: String?

    public override func viewDidLoad() {
        super.viewDidLoad()
        installKeyboardView()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        lastOpenAttemptFailed = false
        openAttemptToken = UUID()
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
            diagnostics: diagnostics,
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

    /// Fires *both* known techniques immediately, rather than trying one and waiting to hear
    /// back before falling back to the other: `extensionContext?.open(_:completionHandler:)`'s
    /// completion handler is documented, and reproduces here, to sometimes never be called at
    /// all from a custom keyboard extension -- gating the responder-chain fallback on that
    /// callback (the previous approach) meant it silently never ran either. Both techniques
    /// require "Allow Full Access"; if that isn't granted they fail the same silent way, which
    /// is correct OS policy, not a bug in either one.
    ///
    /// There's no reliable positive signal that either one actually worked -- if one did, iOS
    /// switches away to Voxbrief and this extension is normally suspended well before anything
    /// below would notice. So this uses the inverse: if we're still here, foregrounded and
    /// responding, a second later, neither attempt opened anything, and that's surfaced in the
    /// keyboard's own UI (`KeyboardView`'s `openFailed`) instead of leaving the user staring at
    /// a button that visibly did nothing.
    private func openVoxbrief() {
        guard let url = URL(string: "voxbrief://record?source=keyboard") else { return }
        lastOpenAttemptFailed = false

        let token = UUID()
        openAttemptToken = token

        var log = [String]()
        log.append("ctx=\(extensionContext == nil ? "nil" : "present")")

        let foundApplication = openViaResponderChain(url)
        log.append("chain=\(foundApplication ? "found+performed" : "no UIApplication")")

        // A third technique: SwiftUI's own OpenURLAction, obtained from a fresh EnvironmentValues
        // rather than through extensionContext or UIApplication directly. Reported (Itsuki,
        // "When ExtensionContext.Open Does NOT Open My App!", Apr 2026) to succeed in exactly
        // this "extensionContext.open silently returns false from an extension" scenario.
        EnvironmentValues().openURL(url)
        log.append("swiftUIOpenURL=called")

        diagnostics = log.joined(separator: " ")
        hostingController?.rootView = makeKeyboardView()

        extensionContext?.open(url) { [weak self] success in
            DispatchQueue.main.async {
                guard let self, self.openAttemptToken == token else { return }
                log.append("open()=\(success)")
                self.diagnostics = log.joined(separator: " ")
                self.hostingController?.rootView = self.makeKeyboardView()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.openAttemptToken == token, self.hasFullAccess else { return }
            self.lastOpenAttemptFailed = true
            log.append("still here @1.2s")
            self.diagnostics = log.joined(separator: " ")
            self.hostingController?.rootView = self.makeKeyboardView()
        }
    }

    /// Returns whether a `UIApplication` instance was actually found while walking the chain --
    /// independent of whether `perform(openURL:)` on it did anything, this alone tells us
    /// whether the extension's responder chain leads to a real UIApplication at all on this
    /// iOS version/device, which existing reports of this technique disagree on.
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

    /// A no-op (returns immediately) unless Full Access is granted -- `KeyboardHandoff` needs the
    /// shared App Group container, which iOS blocks from a restricted keyboard.
    private func insertPendingPasteIfAny() {
        guard hasFullAccess, let text = KeyboardHandoff.consumePendingPaste() else { return }
        textDocumentProxy.insertText(text)
    }
}
