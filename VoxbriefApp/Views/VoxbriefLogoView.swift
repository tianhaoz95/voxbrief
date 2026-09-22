import SwiftUI

public struct VoxbriefLogoView: View {
    public enum Size {
        case large
        case inline
    }

    public var size: Size

    public init(size: Size = .large) {
        self.size = size
    }

    public var body: some View {
        HStack(spacing: size == .large ? 10 : 7) {
            ZStack {
                RoundedRectangle(cornerRadius: size == .large ? 9 : 7, style: .continuous)
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
                    .frame(width: size == .large ? 34 : 26, height: size == .large ? 34 : 26)
                    .shadow(color: Color.blue.opacity(0.35), radius: size == .large ? 5 : 2, y: 1)

                Image(systemName: "waveform")
                    .font(.system(size: size == .large ? 17 : 13, weight: .bold))
                    .foregroundStyle(.white)
            }

            HStack(spacing: 0) {
                Text("Vox")
                    .foregroundStyle(.primary)
                Text("Brief")
                    .foregroundStyle(Color.accentColor)
            }
            .font(.system(size: size == .large ? 32 : 19, weight: .bold, design: .rounded))
            .tracking(-0.5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("VoxBrief")
    }
}
