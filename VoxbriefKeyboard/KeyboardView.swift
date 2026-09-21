import SwiftUI

/// What a key press means to `KeyboardViewController`, which is the only thing that actually
/// touches `textDocumentProxy` (this view has no access to it).
enum KeyboardKey: Hashable {
    case character(String)
    case backspace
    case space
    case newline
}

private enum KeyboardPage {
    case letters
    case numbers
}

/// A deliberately basic full keyboard -- QWERTY letters, a shift key, a numbers/punctuation page,
/// backspace, space, return, and the required "switch keyboard" globe button -- plus a Record bar
/// that hands off to the main Voxbrief app (see KeyboardViewController.openVoxbrief). No
/// autocorrect/predictive text/swipe-typing in this first pass; the point is "doesn't force you to
/// switch keyboards for normal typing," not matching the system keyboard's polish.
struct KeyboardView: View {
    let hasFullAccess: Bool
    /// True when the last tap of the Record bar tried to open Voxbrief and none of the opening
    /// techniques worked, despite Full Access being on -- see `KeyboardViewController.openVoxbrief`.
    let openFailed: Bool
    let onKey: (KeyboardKey) -> Void
    let onRecord: () -> Void
    let onNextKeyboard: () -> Void

    @State private var isShifted = false
    @State private var page: KeyboardPage = .letters

    private let letterRows: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"]
    ]

    private let numberRows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
        [".", ",", "?", "!", "'"]
    ]

    private var currentRows: [[String]] { page == .letters ? letterRows : numberRows }

    var body: some View {
        VStack(spacing: 6) {
            recordBar

            ForEach(Array(currentRows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 6) {
                    if index == 2, page == .letters {
                        shiftKey
                    }
                    ForEach(row, id: \.self) { letter in
                        keyButton(displayed(letter), inserting: letter)
                    }
                    if index == 2 {
                        backspaceKey
                    }
                }
            }

            bottomRow
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(Color(UIColor.systemGray5))
    }

    private func displayed(_ letter: String) -> String {
        guard page == .letters else { return letter }
        return isShifted ? letter.uppercased() : letter
    }

    private var recordBar: some View {
        VStack(spacing: 2) {
            Button(action: onRecord) {
                Label(
                    hasFullAccess ? "Record with Voxbrief" : "Record (enable Full Access in Settings)",
                    systemImage: "mic.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            // .buttonStyle(.borderedProminent) drew its own default system chrome behind the
            // accent color, mismatched against this keyboard's flat background. Applying the
            // background/shape/inset to the Button itself (not just its Label's inner content)
            // and clipping explicitly, rather than relying on an ancestor's ambient horizontal
            // padding to inset it, keeps this self-contained -- this extension's keyboard-service
            // hosting context (UIInputViewController, not a normal in-app view controller) was
            // seen to sometimes let a Label-only background bleed to the true view edges with
            // square corners despite matching code working fine in a normal app screen.
            .background(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 2)

            if openFailed {
                Text("Couldn't open Voxbrief. Try again, or check Full Access in Settings.")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 2)
            }
        }
    }

    private func keyButton(_ displayText: String, inserting rawLetter: String) -> some View {
        Button {
            onKey(.character(displayed(rawLetter)))
            if isShifted, page == .letters {
                isShifted = false
            }
        } label: {
            Text(displayText)
                .font(.system(size: 20))
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Color(UIColor.systemBackground), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var shiftKey: some View {
        Button {
            UIDevice.current.playInputClick()
            isShifted.toggle()
        } label: {
            Image(systemName: isShifted ? "shift.fill" : "shift")
                .frame(width: 40, height: 42)
                .background(Color(UIColor.systemGray3), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var backspaceKey: some View {
        Button {
            onKey(.backspace)
        } label: {
            Image(systemName: "delete.left")
                .frame(width: 40, height: 42)
                .background(Color(UIColor.systemGray3), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var bottomRow: some View {
        HStack(spacing: 6) {
            Button {
                UIDevice.current.playInputClick()
                page = (page == .letters) ? .numbers : .letters
            } label: {
                Text(page == .letters ? "123" : "ABC")
                    .font(.system(size: 16))
                    .frame(width: 44, height: 42)
                    .background(Color(UIColor.systemGray3), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            Button {
                UIDevice.current.playInputClick()
                onNextKeyboard()
            } label: {
                Image(systemName: "globe")
                    .frame(width: 40, height: 42)
                    .background(Color(UIColor.systemGray3), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            Button {
                onKey(.space)
            } label: {
                Text("space")
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(Color(UIColor.systemBackground), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            Button {
                onKey(.newline)
            } label: {
                Text("return")
                    .font(.system(size: 15))
                    .foregroundStyle(.white)
                    .frame(width: 74, height: 42)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
    }
}
