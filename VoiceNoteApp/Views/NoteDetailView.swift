import SwiftUI

public struct NoteDetailView: View {
    @StateObject private var viewModel: NoteDetailViewModel
    @Environment(\.dismiss) private var dismiss
    
    public init(note: VoiceNote) {
        _viewModel = StateObject(wrappedValue: NoteDetailViewModel(note: note))
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Info Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(viewModel.note.source.displayName, systemImage: viewModel.note.source.iconName)
                            .font(.caption.bold())
                            .foregroundColor(.blue)
                        
                        Spacer()
                        
                        Text(viewModel.note.createdAt.relativeOrFormattedString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(viewModel.note.title)
                        .font(.title2.bold())
                        .foregroundColor(.primary)
                    
                    if !viewModel.note.summary.isEmpty {
                        Text(viewModel.note.summary)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    // Tags
                    if !viewModel.note.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(viewModel.note.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.secondary.opacity(0.12))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(14)
                
                // Audio Player Card (if audio exists)
                if viewModel.hasAudio {
                    audioPlayerCard
                }
                
                // Segmented Picker for View Mode
                Picker("View Mode", selection: $viewModel.selectedTab) {
                    ForEach(NoteDetailViewModel.DetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                
                // Content based on selected tab
                switch viewModel.selectedTab {
                case .cleanedNote:
                    cleanedNoteSection
                case .rawTranscript:
                    rawTranscriptSection
                case .pipeline:
                    pipelineSection
                }
            }
            .padding()
        }
        .navigationTitle("Note Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Button {
                    viewModel.toggleFavorite()
                } label: {
                    Image(systemName: viewModel.note.isFavorite ? "star.fill" : "star")
                        .foregroundColor(viewModel.note.isFavorite ? .yellow : .primary)
                }
                
                ShareLink(item: viewModel.note.cleanedNote) {
                    Image(systemName: "square.and.arrow.up")
                }
                
                Menu {
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
    }
    
    // MARK: - Audio Player Card
    
    private var audioPlayerCard: some View {
        let playback = viewModel.playbackService
        let isPlaying = playback.isPlaying && playback.currentlyPlayingFileName == viewModel.note.audioFileName
        
        return VStack(spacing: 12) {
            HStack(spacing: 14) {
                Button {
                    viewModel.togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                        .foregroundColor(.blue)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(isPlaying ? playback.currentTime.formattedDuration : "00:00")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.primary)
                        Spacer()
                        Text(viewModel.note.duration.formattedDuration)
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    
                    // Simple progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 6)
                            
                            let progress = isPlaying && playback.duration > 0 ? (playback.currentTime / playback.duration) : 0.0
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.blue)
                                .frame(width: geo.size.width * CGFloat(progress), height: 6)
                        }
                    }
                    .frame(height: 6)
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(14)
    }
    
    // MARK: - Cleaned Note Section
    
    private var cleanedNoteSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // (a) Requirements converted into bullet points
            if !viewModel.note.requirements.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "target")
                            .foregroundColor(.purple)
                        Text("Requirements")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.note.requirements, id: \.self) { req in
                            HStack(alignment: .top, spacing: 8) {
                                Text("•")
                                    .font(.title3.bold())
                                    .foregroundColor(.purple)
                                Text(req)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.purple.opacity(0.08))
                    .cornerRadius(12)
                }
            }
            
            // (b) Enumerated conditions using numbered formatting
            if !viewModel.note.conditions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "list.number")
                            .foregroundColor(.orange)
                        Text("Enumerated Conditions & Flow")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(viewModel.note.conditions.enumerated()), id: \.offset) { index, cond in
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(index + 1).")
                                    .font(.body.bold())
                                    .foregroundColor(.orange)
                                    .frame(width: 24, alignment: .leading)
                                Text(cond)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(12)
                }
            }
            
            // Action Items
            if !viewModel.note.actionItems.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Action Items")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.note.actionItems, id: \.self) { action in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "square")
                                    .foregroundColor(.green)
                                Text(action)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(12)
                }
            }
            
            // (c) Cleaned Layout Markdown Text
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "doc.plaintext")
                        .foregroundColor(.blue)
                    Text("Formatted Cleaned Note")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                
                Text(viewModel.note.cleanedNote)
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
            }
        }
    }
    
    // MARK: - Raw Transcript Section
    
    private var rawTranscriptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform.badge.mic")
                    .foregroundColor(.secondary)
                Text("Stage 1 Verbatim ASR Output")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            Text(viewModel.note.rawTranscript.isEmpty ? "_No raw transcript available_" : viewModel.note.rawTranscript)
                .font(.body)
                .foregroundColor(.secondary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(UIColor.secondarySystemBackground))
                .cornerRadius(12)
        }
    }
    
    // MARK: - 2-Stage Pipeline Diagnostics Section
    
    private var pipelineSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            pipelineStep(
                number: "1",
                title: "Stage 1: Speech-to-Text (ASR)",
                description: "Converts high-quality audio into verbatim text transcript.",
                status: viewModel.note.rawTranscript.isEmpty ? "Pending" : "Completed",
                isDone: !viewModel.note.rawTranscript.isEmpty
            )
            
            pipelineStep(
                number: "2",
                title: "Stage 2: On-Device LLM Cleanup",
                description: "Fixes typos & grammar, formats requirements into bullet points, and structures enumerated conditions into numbered lists.",
                status: viewModel.note.cleanedNote.isEmpty ? "Pending" : "Completed",
                isDone: !viewModel.note.cleanedNote.isEmpty
            )
            
            if viewModel.isReprocessing {
                HStack {
                    ProgressView()
                    Text("Re-running on-device model...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding()
            } else {
                Button {
                    viewModel.reprocessNote()
                } label: {
                    Label("Re-process With On-Device LLM", systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.top, 8)
            }
        }
    }
    
    private func pipelineStep(number: String, title: String, description: String, status: String, isDone: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(isDone ? Color.green : Color.orange)
                    .frame(width: 32, height: 32)
                Text(number)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.subheadline.bold())
                    Spacer()
                    Text(status)
                        .font(.caption2.bold())
                        .foregroundColor(isDone ? .green : .orange)
                }
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
    }
}
