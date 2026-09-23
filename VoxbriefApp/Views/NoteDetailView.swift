import SwiftUI

public struct NoteDetailView: View {
    @StateObject private var viewModel: NoteDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var copiedField: CopyField?
    @State private var showingAddRecording = false

    private enum CopyField: Equatable {
        case fullRewrite, lightCleanup, rawTranscript
    }

    /// `repository`/`pipeline`/`playbackService` default to the iOS app's `.shared` singletons.
    /// `VoxbriefMac`'s Notes browser passes its own instances explicitly instead (see
    /// `NotesBrowserView`), since the Mac app's note history and audio storage are intentionally
    /// separate from those singletons' default locations.
    public init(
        note: VoiceNote,
        initialTab: NoteDetailViewModel.DetailTab = .cleanedNote,
        repository: NoteRepository = .shared,
        pipeline: NoteProcessingPipeline = .shared,
        playbackService: AudioPlaybackService = .shared
    ) {
        _viewModel = StateObject(wrappedValue: NoteDetailViewModel(
            note: note,
            initialTab: initialTab,
            repository: repository,
            pipeline: pipeline,
            playbackService: playbackService
        ))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if viewModel.note.status == .failed {
                    failureBanner
                }

                if viewModel.usedFallbackCleanup {
                    fallbackCleanupBanner
                }

                if viewModel.note.segments.count > 1 {
                    recordingsSection
                } else if viewModel.hasAudio {
                    audioPlayerCard
                }

                Picker("View Mode", selection: $viewModel.selectedTab) {
                    ForEach(NoteDetailViewModel.DetailTab.visible) { tab in
                        Image(systemName: tab.iconName)
                            .accessibilityLabel(tab.rawValue)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                switch viewModel.selectedTab {
                case .cleanedNote:
                    cleanedNoteSection
                case .lightCleanup:
                    lightCleanupSection
                case .rawTranscript:
                    rawTranscriptSection
                case .pipeline:
                    pipelineSection
                }

                metadataFooter
            }
            .padding()
        }
        .background(AppPageBackground())
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingAddRecording = true
                } label: {
                    Image(systemName: "waveform.badge.plus")
                }
                .disabled(viewModel.note.status.isProcessing)
                .accessibilityLabel("Add Recording")

                Button {
                    viewModel.toggleFavorite()
                } label: {
                    Image(systemName: viewModel.note.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(viewModel.note.isFavorite ? .yellow : .primary)
                }

                ShareLink(item: viewModel.note.cleanedNote) {
                    Image(systemName: "square.and.arrow.up")
                }

                Menu {
                    Button {
                        viewModel.beginEditing()
                    } label: {
                        Label("Edit Note", systemImage: "pencil")
                    }

                    Button {
                        viewModel.reprocessNote()
                    } label: {
                        Label("Re-run LLM Cleanup", systemImage: "sparkles")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $viewModel.isEditing) {
            editSheet
        }
        .sheet(isPresented: $showingAddRecording) {
            #if os(iOS)
            QuickRecordSheet(appendingToNoteId: viewModel.note.id) {}
            #elseif os(macOS)
            MacAddRecordingSheet(noteId: viewModel.note.id)
            #endif
        }
        .trackFeedbackScreen("NoteDetail")
        .onAppear {
            if viewModel.selectedTab == .lightCleanup {
                viewModel.ensureLightCleanupGenerated()
            }
        }
        .onChange(of: viewModel.selectedTab) { _, newTab in
            if newTab == .lightCleanup {
                viewModel.ensureLightCleanupGenerated()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label(viewModel.note.source.displayName, systemImage: viewModel.note.source.iconName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if viewModel.note.duration > 0 {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text(viewModel.note.duration.formattedDuration)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(viewModel.note.createdAt.relativeOrFormattedString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(viewModel.note.title)
                .font(.title2.bold())
                .foregroundStyle(.primary)

            if !viewModel.note.summary.isEmpty {
                Text(viewModel.note.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !viewModel.note.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(viewModel.note.tags, id: \.self) { tag in
                            Text(tag)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.appTertiaryFill, in: Capsule())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
    }

    // MARK: - Failure Banner

    private var failureBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.note.errorMessage ?? "Processing failed.")
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                if viewModel.isReprocessing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Retrying…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("Retry") {
                        viewModel.retryFullProcessing()
                    }
                    .font(.caption.weight(.semibold))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Fallback Cleanup Banner

    private var fallbackCleanupBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 6) {
                Text("Basic cleanup only — the on-device LLM wasn't available for this note, so a simpler rule-based pass formatted it instead.")
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                if viewModel.isReprocessing {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Retrying…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("Try the On-Device LLM Again") {
                        viewModel.reprocessNote()
                    }
                    .font(.caption.weight(.semibold))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Edit Sheet

    private var editSheet: some View {
        NavigationStack {
            Form {
                Section(header: Text("Title")) {
                    TextField("Note title", text: $viewModel.editedTitle)
                }

                Section(header: Text("Cleaned Note (Markdown)")) {
                    TextEditor(text: $viewModel.editedCleanedNote)
                        .frame(minHeight: 300)
                        .font(.body.monospaced())
                }
            }
            .navigationTitle("Edit Note")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelEditing()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        viewModel.saveEdits()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Audio Player Card

    private var audioPlayerCard: some View {
        let playback = viewModel.playbackService
        let isCurrentTrack = playback.currentlyPlayingFileName == viewModel.note.audioFileName
        let isPlaying = playback.isPlaying && isCurrentTrack

        return HStack(spacing: 14) {
            Button {
                viewModel.togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(isCurrentTrack ? playback.currentTime.formattedDuration : "00:00")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(viewModel.note.duration.formattedDuration)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.appTertiaryFill)
                            .frame(height: 4)

                        let progress = isCurrentTrack && playback.duration > 0 ? (playback.currentTime / playback.duration) : 0.0
                        Capsule()
                            .fill(Color.accentColor)
                            .frame(width: geo.size.width * CGFloat(progress), height: 4)
                    }
                    .contentShape(Rectangle())
                    .frame(maxHeight: .infinity)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard geo.size.width > 0 else { return }
                                let progress = min(max(0, value.location.x / geo.size.width), 1)
                                viewModel.seek(to: Double(progress))
                            }
                    )
                }
                .frame(height: 20)
            }
        }
        .padding(14)
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Recordings Section (multi-segment notes)

    /// Shown instead of `audioPlayerCard` once a note has more than one recording folded into it
    /// (see "Add Recording" and "Append To…"), so each take stays individually playable rather
    /// than only exposing whichever one happens to be `note.audioFileName` (the latest).
    private var recordingsSection: some View {
        let playback = viewModel.playbackService
        let sortedSegments = viewModel.note.segments.sorted(by: { $0.createdAt < $1.createdAt })

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(icon: "mic", tint: .accentColor, title: "Recordings (\(sortedSegments.count))")

            VStack(spacing: 10) {
                ForEach(sortedSegments) { segment in
                    let isCurrentTrack = playback.currentlyPlayingFileName == segment.audioFileName
                    let isPlaying = playback.isPlaying && isCurrentTrack

                    HStack(spacing: 12) {
                        Button {
                            viewModel.togglePlayback(fileName: segment.audioFileName)
                        } label: {
                            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(segment.createdAt.relativeOrFormattedString)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                            Text(segment.duration.formattedDuration)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Cleaned Note Section

    private var cleanedNoteSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(viewModel.note.effectiveTemplateSections.enumerated()), id: \.offset) { _, section in
                infoCard(
                    icon: icon(for: section.style),
                    tint: tint(for: section.style),
                    title: section.title,
                    items: section.items,
                    marker: marker(for: section.style)
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    sectionHeader(icon: "doc.plaintext", tint: .accentColor, title: "Formatted Note")
                    Spacer()
                    if let engine = viewModel.note.cleanupEngine, engine != CleanupEngineLabel.notApplicable {
                        Text(engine)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    copyButton(text: viewModel.note.cleanedNote, field: .fullRewrite)
                }

                MarkdownLiteText(viewModel.note.cleanedNote)
                    .foregroundStyle(.primary)
            }
            .padding(16)
            .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - Light Cleanup Section

    private var lightCleanupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader(icon: "wand.and.stars", tint: .blue, title: "Light Cleanup")
                Spacer()
                if let engine = viewModel.note.lightCleanupEngine, engine != CleanupEngineLabel.notApplicable {
                    Text(engine)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                copyButton(text: viewModel.note.lightCleanedNote ?? "", field: .lightCleanup)
            }

            Text("Typos, grammar, and filler words fixed -- original wording and order kept, nothing restructured.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let lightNote = viewModel.note.lightCleanedNote, !lightNote.isEmpty {
                MarkdownLiteText(lightNote)
                    .foregroundStyle(.primary)
            } else if viewModel.isGeneratingLightCleanup {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Generating light cleanup…")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            } else if viewModel.note.status == .ready {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Light cleanup hasn't been generated for this note yet.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Button("Generate Light Cleanup") {
                        viewModel.ensureLightCleanupGenerated()
                    }
                    .font(.subheadline.weight(.semibold))
                }
            } else {
                Text("Light cleanup will be available once this note finishes processing.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private enum ItemMarker {
        case bullet, number, checkbox, plain
    }

    /// Maps a `TemplateSectionStyle` (from `viewModel.note.effectiveTemplateSections`) to this
    /// view's own icon/tint/marker scheme -- kept as a separate small mapping rather than storing
    /// icon/tint/marker directly on `TemplateSectionContent`, since those are presentation
    /// concerns specific to this one view, not part of what Stage 2 actually generates. The
    /// Design Doc template's three sections map to exactly the icons/tints/markers this view used
    /// before multi-template support existed, so its visual output is unchanged.
    private func icon(for style: TemplateSectionStyle) -> String {
        switch style {
        case .bullet: return "target"
        case .numbered: return "list.number"
        case .checklist: return "checkmark"
        case .paragraph: return "text.alignleft"
        }
    }

    private func tint(for style: TemplateSectionStyle) -> Color {
        switch style {
        case .bullet: return .purple
        case .numbered: return .orange
        case .checklist: return .green
        case .paragraph: return .blue
        }
    }

    private func marker(for style: TemplateSectionStyle) -> ItemMarker {
        switch style {
        case .bullet: return .bullet
        case .numbered: return .number
        case .checklist: return .checkbox
        case .paragraph: return .plain
        }
    }

    private func copyButton(text: String, field: CopyField) -> some View {
        Button {
            PlatformPasteboard.copy(text)
            withAnimation(.easeInOut(duration: 0.15)) {
                copiedField = field
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if copiedField == field {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        copiedField = nil
                    }
                }
            }
        } label: {
            Image(systemName: copiedField == field ? "checkmark" : "doc.on.doc")
                .font(.caption)
                .foregroundStyle(copiedField == field ? Color.green : Color.secondary)
        }
        .buttonStyle(.plain)
        .disabled(text.isEmpty)
        .accessibilityLabel("Copy")
    }

    private func sectionHeader(icon: String, tint: Color, title: String) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(tint)
                    .frame(width: 22, height: 22)
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
        }
    }

    private func infoCard(icon: String, tint: Color, title: String, items: [String], marker: ItemMarker) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeader(icon: icon, tint: tint, title: title)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 10) {
                        markerView(marker, index: index, tint: tint)
                        Text(item)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func markerView(_ marker: ItemMarker, index: Int, tint: Color) -> some View {
        switch marker {
        case .bullet:
            Circle()
                .fill(tint)
                .frame(width: 5, height: 5)
                .padding(.top, 7)
        case .number:
            Text("\(index + 1)")
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .frame(width: 16, alignment: .leading)
                .padding(.top, 2)
        case .checkbox:
            Image(systemName: "square")
                .font(.system(size: 15))
                .foregroundStyle(tint)
                .padding(.top, 1)
        case .plain:
            EmptyView()
        }
    }

    // MARK: - Raw Transcript Section

    private var rawTranscriptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader(icon: "waveform", tint: .secondary, title: "Verbatim ASR Output")
                Spacer()
                copyButton(text: viewModel.note.rawTranscript, field: .rawTranscript)
            }

            Text(viewModel.note.rawTranscript.isEmpty ? "No raw transcript available." : viewModel.note.rawTranscript)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - 2-Stage Pipeline Diagnostics Section

    private enum PipelineStepState {
        case pending, active, done
    }

    /// Stage 1 only ever runs during a full retry (`retryFullProcessing`) -- a plain Stage-2-only
    /// reprocess (`reprocessNote`) starts from an existing transcript and never revisits ASR.
    private var asrStepState: PipelineStepState {
        if viewModel.note.status == .transcribingASR { return .active }
        return viewModel.note.rawTranscript.isEmpty ? .pending : .done
    }

    private var llmStepState: PipelineStepState {
        if viewModel.note.status == .cleaningLLM { return .active }
        if viewModel.isReprocessing && asrStepState == .done { return .pending }
        return viewModel.note.cleanedNote.isEmpty ? .pending : .done
    }

    private var pipelineSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            pipelineStep(
                number: 1,
                title: "Speech-to-Text (ASR)",
                description: "Converts audio into a verbatim text transcript.",
                icon: "waveform",
                state: asrStepState
            )

            connectorLine(filled: asrStepState == .done)

            pipelineStep(
                number: 2,
                title: "On-Device LLM Cleanup",
                description: "Formats requirements into bullets, conditions into numbered steps, and fixes grammar.",
                icon: "sparkles",
                state: llmStepState
            )

            if viewModel.isReprocessing {
                liveProgressBanner
            } else {
                Button {
                    viewModel.reprocessNote()
                } label: {
                    Label("Re-process With On-Device LLM", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 12)
            }
        }
    }

    /// Live status card shown while a reprocess/retry is in flight -- reflects the note's actual
    /// `NoteProcessingStatus` (not a fake timer), with an animated icon so progress reads as
    /// "alive" rather than a bare spinner.
    private var liveProgressBanner: some View {
        let status = viewModel.note.status
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: status.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.pulse, options: .repeating, isActive: true)
                    .frame(width: 22)

                Text(status.stepDescription)
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.opacity)
                    .animation(.easeInOut, value: status)

                Spacer(minLength: 0)
            }

            ProgressView()
                .progressViewStyle(.linear)
                .tint(Color.accentColor)
        }
        .padding(14)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.top, 12)
    }

    private func connectorLine(filled: Bool) -> some View {
        Rectangle()
            .fill(filled ? Color.green : Color.appTertiaryFill)
            .frame(width: 2, height: 16)
            .padding(.leading, 27)
            .animation(.easeInOut(duration: 0.3), value: filled)
    }

    private func pipelineStep(number: Int, title: String, description: String, icon: String, state: PipelineStepState) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(stepColor(state))
                    .frame(width: 28, height: 28)

                switch state {
                case .done:
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                case .active:
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse, options: .repeating, isActive: true)
                case .pending:
                    Text("\(number)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: state)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.appSecondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func stepColor(_ state: PipelineStepState) -> Color {
        switch state {
        case .done: return .green
        case .active: return .accentColor
        case .pending: return Color.appTertiaryFill
        }
    }

    // MARK: - Metadata Footer

    private var metadataFooter: some View {
        VStack(spacing: 6) {
            Divider()
                .padding(.top, 12)
                .padding(.bottom, 6)

            HStack(spacing: 6) {
                Label(viewModel.note.source.displayName, systemImage: viewModel.note.source.iconName)

                if viewModel.note.duration > 0 {
                    Text("·")
                    Text(viewModel.note.duration.formattedDuration)
                }

                Text("·")
                Text(viewModel.note.createdAt.fullFormattedString)
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}
