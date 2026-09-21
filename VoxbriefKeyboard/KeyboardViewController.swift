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
///    `openVoxbrief` for why this tries three different techniques, and surfaces failure in the
///    UI when none of them open anything, rather than trusting any one of them blindly.
/// 2. Every time this extension becomes active again (the user switched back manually -- see
///    CLAUDE.md on why that's a required tap, not something this can automate), it checks
///    `KeyboardHandoff` for a result waiting from that flow and inserts it immediately.
public final class KeyboardViewController: UIInputViewController {
    private var hostingController: UIHostingController<KeyboardView>?
    private var lastOpenAttemptFailed = false
    /// Identifies the most recent `openVoxbrief()` call so a stale timer or completion handler
    /// from an earlier tap can't clobber state for a newer one (or one that already succeeded).
    private var openAttemptToken = UUID()

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
            onKey: { [weak self] key in self?.handle(key) },
            onRecord: { [weak self] in self?.openVoxbrief() },
            onNextKeyboard: { [weak self] in self?.advanceToNextInputMode() }
        )
    }

    private func handle(_ key: KeyboardKey) {
        // The dedicated API for a custom keyboard's key-tap feedback (click sound + light haptic
        // on supported hardware) -- unlike UIImpactFeedbackGenerator/UISelectionFeedbackGenerator,
        // this works without Full Access, since most users never grant it and Apple designed this
        // specifically so third-party keyboards aren't stuck silent by default. Respects the
        // user's own Settings > Sounds > Keyboard Clicks preference automatically.
        UIDevice.current.playInputClick()
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

    /// Fires all three known techniques for opening a URL from an extension immediately, rather
    /// than trying one and waiting to hear back before falling back to the next:
    /// `extensionContext?.open(_:completionHandler:)`'s completion handler is documented, and was
    /// confirmed here, to sometimes never be called at all from a custom keyboard extension --
    /// gating anything else on that callback meant it silently never ran either. The one that
    /// actually works in practice is SwiftUI's own `OpenURLAction`, obtained from a fresh
    /// `EnvironmentValues` rather than through `extensionContext` or `UIApplication` directly
    /// (h/t Itsuki, "When ExtensionContext.Open Does NOT Open My App!", Apr 2026, for tracking
    /// this down) -- the other two are kept as harmless redundancy in case that ever regresses.
    /// All three require "Allow Full Access"; if that isn't granted they fail the same silent
    /// way, which is correct OS policy, not a bug in any of them.
    ///
    /// There's no reliable positive signal that any of them actually worked -- if one did, iOS
    /// switches away to Voxbrief and this extension is normally suspended well before anything
    /// below would notice. So this uses the inverse: if we're still here, foregrounded and
    /// responding, a second later, nothing opened anything, and that's surfaced in the keyboard's
    /// own UI (`KeyboardView`'s `openFailed`) instead of leaving the user staring at a button
    /// that visibly did nothing.
    private func openVoxbrief() {
        guard let url = URL(string: "voxbrief://record?source=keyboard") else { return }
        lastOpenAttemptFailed = false

        let token = UUID()
        openAttemptToken = token

        openViaResponderChain(url)
        EnvironmentValues().openURL(url)
        extensionContext?.open(url, completionHandler: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            guard let self, self.openAttemptToken == token, self.hasFullAccess else { return }
            self.lastOpenAttemptFailed = true
            self.hostingController?.rootView = self.makeKeyboardView()
        }
    }

    private func openViaResponderChain(_ url: URL) {
        var responder: UIResponder? = self
        while let current = responder {
            if let application = current as? UIApplication {
                application.perform(#selector(UIApplication.openURL(_:)), with: url)
                return
            }
            responder = current.next
        }
    }

    /// A no-op (returns immediately) unless Full Access is granted -- `KeyboardHandoff` needs the
    /// shared App Group container, which iOS blocks from a restricted keyboard.
    private func insertPendingPasteIfAny() {
        guard hasFullAccess, let text = KeyboardHandoff.consumePendingPaste() else { return }
        textDocumentProxy.insertText(text)
    }
}
