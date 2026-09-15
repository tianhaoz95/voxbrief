import SwiftUI

public struct NoteListView: View {
    @StateObject private var viewModel = NoteListViewModel()
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Watch Sync Status Banner
                watchSyncBanner
                
                // Tag Filter Bar
                tagFilterBar
                
                // Main Notes List
                if viewModel.notes.isEmpty {
                    emptyStateView
                } else {
                    List {
                        ForEach(viewModel.notes) { note in
                            NavigationLink(destination: NoteDetailView(note: note)) {
                                NoteRowView(note: note)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    viewModel.toggleFavorite(note: note)
                                } label: {
                                    Label(note.isFavorite ? "Unfavorite" : "Favorite", systemImage: note.isFavorite ? "star.slash" : "star.fill")
                                }
                                .tint(.yellow)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    viewModel.delete(note: note)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                
                                if note.status == .failed {
                                    Button {
                                        viewModel.retryProcessing(note: note)
                                    } label: {
                                        Label("Retry", systemImage: "arrow.triangle.2.circlepath")
                                    }
                                    .tint(.blue)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Voice Notes")
            .searchable(text: $viewModel.searchText, prompt: "Search notes, requirements, tags...")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        viewModel.showingSyncStatus = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "applewatch")
                            if viewModel.syncService.isReachable {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 7, height: 7)
                            }
                        }
                    }
                }
                
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Menu {
                        Picker("Source Filter", selection: $viewModel.filterSource) {
                            Text("All Sources").tag(NoteSource?.none)
                            Text("Apple Watch").tag(NoteSource?.some(.watchApp))
                            Text("Watch Complication").tag(NoteSource?.some(.watchComplication))
                            Text("Watch Live Activity").tag(NoteSource?.some(.watchLiveActivity))
                            Text("iPhone Direct").tag(NoteSource?.some(.phoneApp))
                        }
                        
                        Toggle(isOn: $viewModel.onlyFavorites) {
                            Label("Favorites Only", systemImage: "star")
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    
                    Button {
                        viewModel.showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        if viewModel.pipeline.activeProcessingCount > 0 {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Processing memo pipeline...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            Text("\(viewModel.notes.count) notes")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button {
                            viewModel.showingRecordSheet = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "mic.fill")
                                Text("Record")
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                        }
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingRecordSheet) {
                QuickRecordSheet { newNote in
                    Task {
                        NoteRepository.shared.save(newNote)
                        await viewModel.pipeline.process(note: newNote)
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingSyncStatus) {
                WatchSyncStatusView(syncService: viewModel.syncService)
            }
            .sheet(isPresented: $viewModel.showingSettings) {
                SettingsView()
            }
        }
    }
    
    // MARK: - Subviews
    
    private var watchSyncBanner: some View {
        Button {
            viewModel.showingSyncStatus = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Watch Sync Active")
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                    Text(viewModel.syncService.latestSyncMessage)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(UIColor.secondarySystemBackground))
        }
    }
    
    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All Filter
                filterChip(title: "All", isSelected: viewModel.selectedTag == nil) {
                    viewModel.selectedTag = nil
                }
                
                ForEach(viewModel.allTags, id: \.self) { tag in
                    filterChip(title: tag, isSelected: viewModel.selectedTag == tag) {
                        if viewModel.selectedTag == tag {
                            viewModel.selectedTag = nil
                        } else {
                            viewModel.selectedTag = tag
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
    
    private func filterChip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color(UIColor.secondarySystemBackground))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Notes Captured Yet")
                .font(.headline)
            Text("Record an idea using your Apple Watch complication, Live Activity, or the record button below.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button {
                viewModel.showingRecordSheet = true
            } label: {
                Label("Capture First Idea", systemImage: "mic.fill")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
            }
            .padding(.top, 8)
            
            Spacer()
        }
    }
}
