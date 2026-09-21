import SwiftUI

/// A premium, audio-reactive capture visualization shared across iOS, watchOS, and macOS -- a
/// flowing, Siri-style gradient sound wave above a glossy gradient button, replacing the flat
/// "solid circle + one scaling halo" look every capture screen used to duplicate. Purely
/// presentational: the caller supplies `isRecording`/`audioLevel` and wraps this in whatever
/// tap/click handling, size, and surrounding duration/label text makes sense for that platform.
///
/// Lives in `Shared/` (not `VoxbriefApp/`) specifically so it compiles into the iOS, watchOS,
/// *and* macOS targets without any per-platform duplication -- all APIs used here (TimelineView,
/// gradients, Capsule/Circle) are available on all three.
public struct CaptureWaveformView: View {
    public var isRecording: Bool
    public var audioLevel: Float
    public var diameter: CGFloat
    public var systemImage: String?

    public init(isRecording: Bool, audioLevel: Float, diameter: CGFloat = 96, systemImage: String? = nil) {
        self.isRecording = isRecording
        self.audioLevel = audioLevel
        self.diameter = diameter
        self.systemImage = systemImage
    }

    private static let barCount = 32

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            VStack(spacing: diameter * 0.14) {
                waveform(time: t)
                core(time: t)
            }
        }
        .frame(width: diameter * 2.7, height: diameter * 1.95)
    }

    /// A multi-stop, Siri-like gradient rather than a single flat color -- warm coral through
    /// magenta into violet while recording, a softer accent-toned sweep at rest.
    private var waveGradient: [Color] {
        isRecording
            ? [Color(red: 1.0, green: 0.52, blue: 0.30), Color(red: 0.98, green: 0.22, blue: 0.55), Color(red: 0.62, green: 0.20, blue: 0.92)]
            : [Color.accentColor.opacity(0.55), Color.accentColor, Color.accentColor.opacity(0.55)]
    }

    private var coreGradient: [Color] {
        isRecording
            ? [Color(red: 1.0, green: 0.40, blue: 0.38), Color(red: 0.72, green: 0.07, blue: 0.18)]
            : [Color.accentColor.opacity(0.85), Color.accentColor]
    }

    private var glowColor: Color {
        isRecording ? Color.red : Color.accentColor
    }

    /// A real (if synthetic, since there's no live FFT data) sound-wave shape: each bar's height
    /// blends two out-of-phase, differently-paced sine terms so the whole row ripples left-to-right
    /// like an actual waveform instead of every bar just bobbing in place, shaped by a bell-curve
    /// envelope (tallest in the middle, tapering at the edges) -- the classic Siri/Voice-Memos
    /// waveform silhouette -- and scaled by live microphone level.
    @ViewBuilder
    private func waveform(time: TimeInterval) -> some View {
        let width = diameter * 2.7
        let barWidth = max(2.0, diameter * 0.028)
        let spacing = (width - barWidth * CGFloat(Self.barCount)) / CGFloat(Self.barCount - 1)
        let level = Double(min(max(audioLevel, 0), 1))
        let liveLevel = isRecording ? level : 0.05

        HStack(spacing: spacing) {
            ForEach(0..<Self.barCount, id: \.self) { index in
                let x = Double(index) / Double(Self.barCount - 1)
                let waveA = sin(time * 2.2 + x * 9.5)
                let waveB = sin(time * 3.6 - x * 5.5 + 1.1)
                let envelope = 0.3 + 0.7 * (1.0 - pow((x - 0.5) * 2, 2))
                let magnitude = max(0.05, (0.55 + 0.45 * waveA) * 0.6 + (0.55 + 0.45 * waveB) * 0.4)
                let height = diameter * 0.05 + diameter * 0.75 * liveLevel * magnitude * envelope
                Capsule()
                    .fill(LinearGradient(colors: waveGradient, startPoint: .leading, endPoint: .trailing))
                    .frame(width: barWidth, height: max(diameter * 0.05, height))
            }
        }
        .frame(width: width, height: diameter * 0.85)
        .shadow(color: glowColor.opacity(0.25), radius: diameter * 0.1)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: audioLevel)
    }

    @ViewBuilder
    private func core(time: TimeInterval) -> some View {
        let breathe = isRecording ? 1.0 : 1.0 + 0.025 * sin(time * 1.6)
        let coreDiameter = diameter * 0.78
        ZStack {
            Circle()
                .fill(LinearGradient(colors: coreGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: coreDiameter, height: coreDiameter)
                .shadow(color: glowColor.opacity(0.45), radius: coreDiameter * 0.22, y: coreDiameter * 0.06)

            // A soft top-left highlight for a glossy, dimensional look instead of a flat fill.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.32), .white.opacity(0)],
                        center: UnitPoint(x: 0.32, y: 0.26),
                        startRadius: 0,
                        endRadius: coreDiameter * 0.55
                    )
                )
                .frame(width: coreDiameter, height: coreDiameter)

            Image(systemName: systemImage ?? (isRecording ? "stop.fill" : "mic.fill"))
                .font(.system(size: coreDiameter * 0.38, weight: .semibold))
                .foregroundStyle(.white)
        }
        .scaleEffect(breathe)
        .animation(.easeInOut(duration: 0.3), value: isRecording)
    }
}
