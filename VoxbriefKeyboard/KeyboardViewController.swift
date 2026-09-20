import UIKit
import SwiftUI

/// The keyboard extension's entry point (`NSExtensionPrincipalClass` in Info.plist, wired via
/// project.yml). Hosts `KeyboardView` (SwiftUI) and translates its key taps into
/// `textDocumentProxy` calls -- the view itself has no access to that, by design, so it can't be
/// tested/previewed without a real host text field.
///
/// Two responsibilities beyond normal typing:
/// 1. The Record bar opens the main Voxbrief app via `extensionContext?.open(_:)`, passing
///    `source=keyboard` so `VoxbriefApp.handleDeepLink` routes to `KeyboardRecordSheet` instead of
///    the normal record sheet.
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

    private func openVoxbrief() {
        guard let url = URL(string: "voxbrief://record?source=keyboard") else { return }
        extensionContext?.open(url, completionHandler: nil)
    }

    /// A no-op (returns immediately) unless Full Access is granted -- `KeyboardHandoff` needs the
    /// shared App Group container, which iOS blocks from a restricted keyboard.
    private func insertPendingPasteIfAny() {
        guard hasFullAccess, let text = KeyboardHandoff.consumePendingPaste() else { return }
        textDocumentProxy.insertText(text)
    }
}
