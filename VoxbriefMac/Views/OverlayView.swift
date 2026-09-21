import SwiftUI

/// Content of the floating capture overlay. Purely presentational -- all state comes from
/// `CaptureCoordinator` and `MacAudioRecorderService`; button taps just call back into the
/// coordinator.
struct OverlayView: View {
    @ObservedObject var coordinator: CaptureCoordinator
    @ObservedObject var recorder: MacAudioRecorderService

    var body: some View {
        VStack(spacing: 14) {
            statusRow
            actionRow
        }
        .padding(20)
        .frame(width: 340, height: 150)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }

    @ViewBuilder
    private var statusRow: some View {
        switch coordinator.state {
        case .idle:
            EmptyView()
        case .listening:
            VStack(spacing: 10) {
                Label("Listening…", systemImage: "waveform")
                    .font(.headline)
                LevelMeter(level: recorder.audioLevel)
            }
        case .processing:
            VStack(spacing: 10) {
                Label("Cleaning up…", systemImage: "sparkles")
                    .font(.headline)
                    .symbolEffect(.pulse)
                ProgressView()
                    .controlSize(.small)
            }
        case .success:
            Label("Pasted", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        switch coordinator.state {
        case .listening, .processing:
            HStack(spacing: 12) {
                Button(role: .cancel) {
                    coordinator.cancelCapture()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                if coordinator.state == .listening {
                    Button {
                        coordinator.completeCapture()
                    } label: {
                        Label("Complete", systemImage: "checkmark")
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .buttonStyle(.bordered)
        case .idle, .success, .failed:
            EmptyView()
        }
    }
}

/// Small animated level meter driven by the live microphone level. Each bar is filled with a
/// vertical gradient (brighter at the tip) rather than a flat color, and driven by a spring
/// instead of a linear ease, for a livelier, more premium feel matching `CaptureWaveformView`
/// (used elsewhere in the app) without changing this HUD's compact horizontal-bars layout.
private struct LevelMeter: View {
    var level: Float

    private let barCount = 24

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.55)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 3, height: barHeight(for: index))
            }
        }
        .frame(height: 28)
        .animation(.spring(response: 0.22, dampingFraction: 0.65), value: level)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let midpoint = Double(barCount) / 2
        let distanceFromCenter = abs(Double(index) - midpoint) / midpoint
        let falloff = 1.0 - distanceFromCenter * 0.7
        let magnitude = CGFloat(max(0.08, Double(level) * falloff))
        return 4 + magnitude * 24
    }
}
