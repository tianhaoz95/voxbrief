import SwiftUI

public struct VoxbriefLogoView: View {
    public enum Size {
        case large
        case inline
        case watch
    }

    public var size: Size

    public init(size: Size = .large) {
        self.size = size
    }

    private var iconDimension: CGFloat {
        switch size {
        case .large: return 34
        case .inline: return 26
        case .watch: return 18
        }
    }

    private var iconCornerRadius: CGFloat {
        switch size {
        case .large: return 9
        case .inline: return 7
        case .watch: return 5
        }
    }

    private var iconSymbolSize: CGFloat {
        switch size {
        case .large: return 17
        case .inline: return 13
        case .watch: return 9
        }
    }

    private var fontSize: CGFloat {
        switch size {
        case .large: return 32
        case .inline: return 18
        case .watch: return 14
        }
    }

    private var spacing: CGFloat {
        switch size {
        case .large: return 10
        case .inline: return 7
        case .watch: return 5
        }
    }

    public var body: some View {
        HStack(spacing: spacing) {
            ZStack {
                RoundedRectangle(cornerRadius: iconCornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.22, green: 0.58, blue: 0.98),
                                Color(red: 0.12, green: 0.38, blue: 0.94)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: iconDimension, height: iconDimension)
                    .shadow(color: Color.blue.opacity(0.35), radius: size == .large ? 5 : 2, y: 1)

                Image(systemName: "waveform")
                    .font(.system(size: iconSymbolSize, weight: .bold))
                    .foregroundStyle(.white)
            }

            HStack(spacing: 0) {
                Text("Vox")
                    .foregroundStyle(.primary)
                Text("Brief")
                    .foregroundStyle(Color.accentColor)
            }
            .font(.system(size: fontSize, weight: .bold, design: .rounded))
            .tracking(-0.5)
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("VoxBrief")
    }
}
