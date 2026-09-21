import SwiftUI

/// A premium, audio-reactive capture button shared across iOS, watchOS, and macOS -- a
/// glossy gradient core surrounded by a ring of independently wobbling bars driven by live
/// microphone level, replacing the flat "solid circle + one scaling halo" look every capture
/// screen used to duplicate. Purely presentational: the caller supplies `isRecording`/
/// `audioLevel` and wraps this in whatever tap/click handling, size, and surrounding duration/
/// label text makes sense for that platform.
///
/// Lives in `Shared/` (not `VoxbriefApp/`) specifically so it compiles into the iOS, watchOS,
/// *and* macOS targets without any per-platform duplication -- all APIs used here (TimelineView,
/// gradients, Capsule/Circle, rotationEffect) are available on all three.
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

    private static let barCount = 28

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                ring(time: t)
                core(time: t)
            }
        }
        .frame(width: diameter * 2.1, height: diameter * 2.1)
    }

    private var gradientColors: [Color] {
        isRecording
            ? [Color(red: 1.0, green: 0.40, blue: 0.38), Color(red: 0.72, green: 0.07, blue: 0.18)]
            : [Color.accentColor.opacity(0.85), Color.accentColor]
    }

    private var glowColor: Color {
        isRecording ? Color.red : Color.accentColor
    }

    @ViewBuilder
    private func ring(time: TimeInterval) -> some View {
        let radius = diameter * 0.62
        let level = Double(min(max(audioLevel, 0), 1))
        ForEach(0..<Self.barCount, id: \.self) { index in
            let phase = (Double(index) / Double(Self.barCount)) * 2 * .pi
            let wobble = 0.5 + 0.5 * sin(time * 2.6 + phase * 3.0)
            let liveLevel = isRecording ? level : 0.05
            let length = diameter * (0.07 + 0.24 * liveLevel * wobble)
            Capsule()
                .fill(
                    LinearGradient(colors: gradientColors, startPoint: .top, endPoint: .bottom)
                        .opacity(0.45 + 0.4 * liveLevel)
                )
                .frame(width: diameter * 0.026, height: length)
                .offset(y: -radius)
                .rotationEffect(.radians(phase))
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: audioLevel)
    }

    @ViewBuilder
    private func core(time: TimeInterval) -> some View {
        let breathe = isRecording ? 1.0 : 1.0 + 0.02 * sin(time * 1.6)
        ZStack {
            Circle()
                .fill(LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: diameter, height: diameter)
                .shadow(color: glowColor.opacity(0.4), radius: diameter * 0.16, y: diameter * 0.05)

            // A soft top-left highlight for a glossy, dimensional look instead of a flat fill.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.32), .white.opacity(0)],
                        center: UnitPoint(x: 0.32, y: 0.26),
                        startRadius: 0,
                        endRadius: diameter * 0.55
                    )
                )
                .frame(width: diameter, height: diameter)

            Image(systemName: systemImage ?? (isRecording ? "stop.fill" : "mic.fill"))
                .font(.system(size: diameter * 0.34, weight: .semibold))
                .foregroundStyle(.white)
        }
        .scaleEffect(breathe)
        .animation(.easeInOut(duration: 0.3), value: isRecording)
    }
}
