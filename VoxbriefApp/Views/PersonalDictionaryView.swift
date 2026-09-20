import SwiftUI

public struct PersonalDictionaryView: View {
    @ObservedObject private var store: PersonalDictionaryStore
    @State private var editingEntry: DictionaryEntry?
    @State private var isPresentingNewEntry = false

    public init(store: PersonalDictionaryStore) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.entries.isEmpty {
                ContentUnavailableView(
                    "No Dictionary Terms",
                    systemImage: "text.book.closed",
                    description: Text("Add jargon, product names, and people's names so the on-device models recognize and preserve them.")
                )
            } else {
                List {
                    ForEach(store.entries) { entry in
                        Button {
                            editingEntry = entry
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.term)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                if !entry.aliases.isEmpty {
                                    Text("aka: \(entry.aliases.joined(separator: ", "))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { store.delete(at: $0) }
                }
            }
        }
        .navigationTitle("Personal Dictionary")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingNewEntry = true
                } label: {
                    Label("Add Term", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingNewEntry) {
            DictionaryEntryEditView(store: store, entry: nil)
        }
        .sheet(item: $editingEntry) { entry in
            DictionaryEntryEditView(store: store, entry: entry)
        }
    }
}
