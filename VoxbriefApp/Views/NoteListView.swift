import SwiftUI
#if canImport(FeedbackKit)
import FeedbackKit
#endif

public struct NoteListView: View {
    @StateObject private var viewModel = NoteListViewModel()
    @StateObject private var syncService = WatchSyncService.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedDetailNote: VoiceNote? = nil
    @State private var selectedDetailTab: NoteDetailViewModel.DetailTab = .cleanedNote
    /// `.sheet(item:)`, not `.sheet(isPresented:)` -- a second "keyboardRecord" deep link while
    /// the sheet from a previous keyboard-triggered recording is still up (e.g. the user left via
    /// the system back arrow instead of tapping Close, so it was never actually dismissed) needs
    /// to force a genuinely fresh `KeyboardRecordSheet`, not just leave the stale one from last
    /// time on screen. A bool toggled false-then-true in the same synchronous call (as
    /// `applyNavigation` does) never observably changes from `.sheet(isPresented:)`'s point of
    /// view, so the old sheet (and its already-`.readyToPaste` @State) never gets torn down. A
    /// fresh, distinct id on every trigger guarantees SwiftUI always treats it as a new
    /// presentation instead.
    @State private var keyboardRecordTrigger: KeyboardRecordTrigger?
    @State private var isSearchExpanded: Bool = false
    @FocusState private var isSearchFieldFocused: Bool
    @Namespace private var searchAnimationNamespace

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isSearchExpanded {
                    searchAndTagsHeader
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                notesList
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    VoxbriefLogoView(size: .inline)
                }
                .hideSharedBackgroundIfAvailable()

                ToolbarItem(placement: .navigationBarTrailing) {
                    searchToolbarButton
                }
                .hideSharedBackgroundIfAvailable()

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    trailingToolbarGroup
                }

                ToolbarItem(placement: .bottomBar) {
                    recordBottomBarButton
                }
            }
            .sheet(isPresented: $viewModel.showingRecordSheet) {
                QuickRecordSheet {}
            }
            .sheet(item: $keyboardRecordTrigger) { _ in
                KeyboardRecordSheet()
            }
            .sheet(isPresented: $viewModel.showingSyncStatus) {
                WatchSyncStatusView(syncService: syncService)
            }
            .sheet(isPresented: $viewModel.showingSettings) {
                SettingsView()
            }
            .sheet(item: $viewModel.mergeSourceNote) { source in
                NoteMergePickerSheet(source: source, candidates: viewModel.mergeCandidates(excluding: source)) { target in
                    viewModel.confirmMerge(source: source, into: target)
                }
            }
            .navigationDestination(item: $selectedDetailNote) { note in
                NoteDetailView(note: note, initialTab: selectedDetailTab)
            }
            .trackFeedbackScreen("NoteList")
            .onAppear {
                applyLaunchArguments()
            }
            .onReceive(NotificationCenter.default.publisher(for: .voxbriefNavigate)) { notification in
                guard let userInfo = notification.userInfo as? [String: String],
                      let screen = userInfo["screen"] else { return }
                applyNavigation(screen: screen, tab: userInfo["tab"])
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await viewModel.refresh() }
                }
            }
            .onChange(of: viewModel.showingSyncStatus) { _, isShowing in
                if !isShowing {
                    #if canImport(FeedbackKit)
                    FeedbackKit.currentScreen = "NoteList"
                    #endif
                }
            }
            .onChange(of: viewModel.showingSettings) { _, isShowing in
                if !isShowing {
                    #if canImport(FeedbackKit)
                    FeedbackKit.currentScreen = "NoteList"
                    #endif
                }
            }
        }
    }

    private func applyLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        if let screenIdx = args.firstIndex(of: "-voxbriefScreen"), screenIdx + 1 < args.count {
            let screen = args[screenIdx + 1]
            let tab = args.firstIndex(of: "-voxbriefTab").flatMap { idx in
                idx + 1 < args.count ? args[idx + 1] : nil
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                applyNavigation(screen: screen, tab: tab)
            }
        }
        if let searchIdx = args.firstIndex(of: "-voxbriefSearch"), searchIdx + 1 < args.count {
            let query = args[searchIdx + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    isSearchExpanded = true
                }
                viewModel.searchText = query
            }
        }
        if let tagIdx = args.firstIndex(of: "-voxbriefTag"), tagIdx + 1 < args.count {
            let tag = args[tagIdx + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    isSearchExpanded = true
                }
                viewModel.selectedTag = tag
            }
        }
    }

    private func applyNavigation(screen: String, tab: String?) {
        viewModel.showingRecordSheet = false
        viewModel.showingSyncStatus = false
        viewModel.showingSettings = false
        keyboardRecordTrigger = nil
        selectedDetailNote = nil

        switch screen {
        case "list":
            collapseSearch()
        case "search":
            withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                isSearchExpanded = true
                isSearchFieldFocused = true
            }
        case "detail":
            collapseSearch()
            if let note = viewModel.notes.first {
                switch tab {
                case "raw": selectedDetailTab = .rawTranscript
                case "pipeline": selectedDetailTab = .pipeline
                case "light": selectedDetailTab = .lightCleanup
                default: selectedDetailTab = .cleanedNote
                }
                selectedDetailNote = note
            }
        case "record":
            viewModel.showingRecordSheet = true
        case "keyboardRecord":
            keyboardRecordTrigger = KeyboardRecordTrigger()
        case "settings":
            viewModel.showingSettings = true
        case "sync":
            viewModel.showingSyncStatus = true
        default:
            break
        }
    }

    // MARK: - Subviews

    private var notesList: some View {
        List {
            if viewModel.notes.isEmpty {
                emptyStateView
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .frame(maxWidth: .infinity, minHeight: 350)
            } else {
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
                            .tint(.accentColor)
                        }

                        if note.status == .ready {
                            Button {
                                viewModel.beginMerge(source: note)
                            } label: {
                                Label("Append To…", systemImage: "arrow.triangle.merge")
                            }
                            .tint(.blue)
                        }
                    }
                    .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            await viewModel.refresh()
        }
    }

    @ViewBuilder
    private var searchToolbarButton: some View {
        if !isSearchExpanded {
            Button {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
                    isSearchExpanded = true
                    isSearchFieldFocused = true
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .matchedGeometryEffect(id: "searchIcon", in: searchAnimationNamespace)
            }
            .accessibilityLabel("Search and filter tags")
            .matchedGeometryEffect(id: "searchContainer", in: searchAnimationNamespace)
        }
    }

    @ViewBuilder
    private var trailingToolbarGroup: some View {
        Button {
            viewModel.showingSyncStatus = true
        } label: {
            Image(systemName: "applewatch")
                .foregroundStyle(watchIconColor)
        }
        .accessibilityLabel(syncService.isReachable ? "Apple Watch connected" : "Apple Watch disconnected")

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

            Divider()

            ShareLink(item: viewModel.exportAllNotesMarkdown()) {
                Label("Export All Notes", systemImage: "square.and.arrow.up.on.square")
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

    private var recordBottomBarButton: some View {
        Button {
            viewModel.showingRecordSheet = true
        } label: {
            Image(systemName: "mic.fill")
        }
        .tint(Color.accentColor)
        .overlay(alignment: .topTrailing) {
            if viewModel.pipeline.activeProcessingCount > 0 {
                Circle()
                    .fill(.orange)
                    .frame(width: 7, height: 7)
                    .offset(x: 8, y: -6)
            }
        }
    }

    private var watchIconColor: Color {
        syncService.isReachable ? .green : .secondary
    }

    private var searchAndTagsHeader: some View {
        VStack(spacing: 0) {
            searchBar
            if !viewModel.allTags.isEmpty {
                tagFilterBar
            }
            Divider()
        }
        .background(Color.appGroupedBackground)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 16))
                    .matchedGeometryEffect(id: "searchIcon", in: searchAnimationNamespace)

                TextField("Search notes, requirements, tags...", text: $viewModel.searchText)
                    .font(.body)
                    .focused($isSearchFieldFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit {
                        isSearchFieldFocused = false
                    }

                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 15))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search text")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(UIColor.secondarySystemFill))
            }
            .matchedGeometryEffect(id: "searchContainer", in: searchAnimationNamespace)

            Button("Cancel") {
                collapseSearch()
            }
            .font(.body)
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, viewModel.allTags.isEmpty ? 8 : 4)
    }

    private func collapseSearch() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
            isSearchExpanded = false
        }
        viewModel.searchText = ""
        viewModel.selectedTag = nil
        isSearchFieldFocused = false
    }

    private var tagFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background {
                    Capsule()
                        .fill(isSelected ? Color.accentColor : Color(UIColor.tertiarySystemFill))
                }
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    private var isAnyFilterActive: Bool {
        !viewModel.searchText.isEmpty || viewModel.selectedTag != nil || viewModel.filterSource != nil || viewModel.onlyFavorites
    }

    private var emptyStateView: some View {
        VStack(spacing: 18) {
            Spacer()

            if isAnyFilterActive {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(.tertiary)

                VStack(spacing: 6) {
                    Text("No Matching Notes")
                        .font(.title3.weight(.semibold))
                    Text("Try searching with different keywords or clearing your filters.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(.tertiary)

                VStack(spacing: 6) {
                    Text("No Notes Yet")
                        .font(.title3.weight(.semibold))
                    Text("Record from your Apple Watch, or tap the mic icon to capture an idea.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A fresh, distinct instance is created on every `voxbrief://record?source=keyboard` deep link
/// (see `NoteListView.applyNavigation`) specifically so `.sheet(item:)` always presents a brand
/// new `KeyboardRecordSheet`, even if one from a previous keyboard-triggered recording was
/// somehow still up.
private struct KeyboardRecordTrigger: Identifiable {
    let id = UUID()
}

