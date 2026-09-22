import SwiftUI

/// First-run explainer shown once, priming microphone and speech recognition permissions
/// up front instead of surprising the user with system prompts mid-recording.
public struct OnboardingView: View {
    let onFinished: () -> Void

    @State private var isRequestingPermissions = false

    public init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
                .padding(.bottom, 20)

            Text("Welcome to Voxbrief")
                .font(.largeTitle.bold())
                .minimumScaleFactor(0.6)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("Capture ideas instantly, anywhere, and let on-device AI turn them into structured notes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .padding(.top, 8)

            Spacer()

            VStack(alignment: .leading, spacing: 22) {
                featureRow(
                    icon: "applewatch.radiowaves.left.and.right",
                    color: .blue,
                    title: "One-Tap Watch Capture",
                    description: "Record instantly from a watch face complication or Live Activity, even offline."
                )
                featureRow(
                    icon: "waveform.badge.mic",
                    color: .purple,
                    title: "On-Device Speech-to-Text",
                    description: "Stage 1 transcribes your voice privately, with nothing leaving your device."
                )
                featureRow(
                    icon: "sparkles",
                    color: .orange,
                    title: "AI Cleanup & Structure",
                    description: "Stage 2 turns rambling thoughts into bullets, numbered steps, and checklists."
                )
            }
            .padding(.horizontal, 28)

            Spacer()

            Button {
                requestPermissionsAndFinish()
            } label: {
                HStack {
                    if isRequestingPermissions {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Get Started")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 14))
            .controlSize(.large)
            .disabled(isRequestingPermissions)
            .padding(.horizontal, 28)

            Text("We'll ask for microphone access so recording and cleanup can happen entirely on this device.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.top, 10)
                .padding(.bottom, 24)
        }
        .trackFeedbackScreen("Onboarding")
    }

    private func featureRow(icon: String, color: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(color.gradient)
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func requestPermissionsAndFinish() {
        isRequestingPermissions = true
        Task {
            // Speech recognition runs entirely through on-device Whisper (WhisperKit), which
            // needs no OS-level speech-recognition permission -- only the microphone matters here.
            _ = await AudioRecordingService.shared.requestPermission()
            isRequestingPermissions = false
            onFinished()
        }
    }
}
