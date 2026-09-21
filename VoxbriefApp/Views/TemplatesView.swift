import SwiftUI

/// Lists every available Stage 2 output template -- built-in (read-only) and user-created
/// (editable/deletable) -- mirroring `PersonalDictionaryView`'s shape.
public struct TemplatesView: View {
    @ObservedObject private var store: TemplateStore
    @State private var editingTemplate: NoteTemplate?
    @State private var isPresentingNewTemplate = false

    public init(store: TemplateStore) {
        self.store = store
    }

    public var body: some View {
        List {
            Section(
                header: Text("Built-In"),
                footer: Text("Voxbrief picks whichever of these best fits each note automatically. Built-in templates can't be edited or removed.")
            ) {
                ForEach(NoteTemplate.builtIns) { template in
                    NavigationLink {
                        TemplateDetailView(template: template)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.name)
                                .font(.body)
                                .foregroundColor(.primary)
                            Text(template.summary)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section(
                header: Text("Custom"),
                footer: Text("Add your own template to teach Voxbrief a new format -- it becomes one more option the LLM can choose for a note.")
            ) {
                if store.customTemplates.isEmpty {
                    Text("No custom templates yet.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(store.customTemplates) { template in
                        Button {
                            editingTemplate = template
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.name)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                Text(template.summary)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete { store.delete(at: $0) }
                }
            }
        }
        .navigationTitle("Templates")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isPresentingNewTemplate = true
                } label: {
                    Label("Add Template", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingNewTemplate) {
            TemplateEditView(store: store, template: nil)
        }
        .sheet(item: $editingTemplate) { template in
            TemplateEditView(store: store, template: template)
        }
    }
}
