import SwiftUI

/// Add/edit sheet for a single `DictionaryEntry`. `entry == nil` means "add new"; a non-nil
/// `entry` pre-fills the form and saves back as an update.
public struct DictionaryEntryEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store: PersonalDictionaryStore
    private let existingEntry: DictionaryEntry?

    @State private var term: String
    @State private var aliasesText: String

    public init(store: PersonalDictionaryStore, entry: DictionaryEntry?) {
        self.store = store
        self.existingEntry = entry
        _term = State(initialValue: entry?.term ?? "")
        _aliasesText = State(initialValue: entry?.aliases.joined(separator: ", ") ?? "")
    }

    private var trimmedTerm: String {
        term.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Term")) {
                    TextField("e.g. Voxbrief, Kubernetes, Priya Patel", text: $term)
                        .autocorrectionDisabled()
                }

                Section(
                    header: Text("Common Mis-transcriptions (optional)"),
                    footer: Text("Comma-separated. Whenever the speech recognizer produces one of these, it's replaced with the term above.")
                ) {
                    TextField("e.g. fox brief, vox brief", text: $aliasesText)
                        .autocorrectionDisabled()
                }

                if existingEntry != nil {
                    Section {
                        Button("Delete Term", role: .destructive) {
                            if let id = existingEntry?.id {
                                store.delete(id: id)
                            }
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existingEntry == nil ? "Add Term" : "Edit Term")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(trimmedTerm.isEmpty)
                }
            }
        }
    }

    private func save() {
        let aliases = aliasesText.components(separatedBy: ",")

        if var entry = existingEntry {
            entry.term = trimmedTerm
            entry.aliases = aliases
            store.update(entry)
        } else {
            store.add(term: trimmedTerm, aliases: aliases)
        }
    }
}
