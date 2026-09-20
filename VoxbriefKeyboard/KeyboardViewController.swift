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
///    prerequisite obvious instead of the button just doing nothing with no explanation.
/// 2. Every time this extension becomes active again (the user switched back manually -- see
///    CLAUDE.md on why that's a required tap, not something this can automate), it checks
///    `KeyboardHandoff` for a result waiting from that flow and inserts it immediately.
public final class KeyboardViewController: UIInputViewController {
    private var hostingController: UIHostingController<KeyboardView>?

    public override func viewDidLoad() {
        super.viewDidLoad()
        installKeyboardView()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
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

    /// `extensionContext?.open(_:completionHandler:)` is the documented API for this, but it's
    /// widely reported (and confirmed here) to silently do nothing from a keyboard extension
    /// specifically. The technique that's actually reliable: unlike most extension types, a
    /// keyboard extension's view sits in the *host app's* view hierarchy, so its responder chain
    /// leads to the host's real `UIApplication` instance -- walk up to it and open the URL there,
    /// via `perform(_:with:)` since `UIApplication.openURL(_:)` can't be called directly from an
    /// extension target (the compiler won't let a non-app target reference it).
    private func openVoxbrief() {
        guard let url = URL(string: "voxbrief://record?source=keyboard") else { return }
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
