import SwiftUI

/// Add/edit sheet for a single custom `NoteTemplate`. `template == nil` means "add new"; a
/// non-nil `template` pre-fills the form and saves back as an update. Built-in templates never
/// reach this view in edit mode (`TemplatesView` only wires tap-to-edit for custom rows), but the
/// destructive delete section still guards on `isBuiltIn` as defense-in-depth.
public struct TemplateEditView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store: TemplateStore
    private let existingTemplate: NoteTemplate?

    @State private var name: String
    @State private var summary: String
    @State private var sections: [TemplateSection]

    public init(store: TemplateStore, template: NoteTemplate?) {
        self.store = store
        self.existingTemplate = template
        _name = State(initialValue: template?.name ?? "")
        _summary = State(initialValue: template?.summary ?? "")
        _sections = State(initialValue: template?.sections ?? [])
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasAtLeastOneNamedSection: Bool {
        sections.contains { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Name")) {
                    TextField("e.g. Meeting Notes, Journal Entry", text: $name)
                        .autocorrectionDisabled()
                }

                Section(
                    header: Text("Summary"),
                    footer: Text("One line describing what kind of transcript this fits -- Voxbrief shows this to the LLM so it can decide whether a given note should use this template.")
                ) {
                    TextField("e.g. A quick personal journal entry, no particular structure", text: $summary, axis: .vertical)
                }

                Section(
                    header: Text("Sections"),
                    footer: Text("Each section becomes one part of the generated note. \"Format\" controls how its content is rendered -- e.g. a bullet list or a single paragraph.")
                ) {
                    ForEach($sections) { $section in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Section Title", text: $section.title)
                            TextField("Instructions for the LLM", text: $section.instructions, axis: .vertical)
                                .font(.footnote)
                            Picker("Format", selection: $section.style) {
                                ForEach(TemplateSectionStyle.allCases, id: \.self) { style in
                                    Text(style.displayName).tag(style)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { sections.remove(atOffsets: $0) }

                    Button {
                        sections.append(TemplateSection(fieldKey: "", title: "", instructions: "", style: .paragraph))
                    } label: {
                        Label("Add Section", systemImage: "plus")
                    }
                }

                if let existingTemplate, !existingTemplate.isBuiltIn {
                    Section {
                        Button("Delete Template", role: .destructive) {
                            store.delete(id: existingTemplate.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existingTemplate == nil ? "Add Template" : "Edit Template")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty || !hasAtLeastOneNamedSection)
                }
            }
            .trackFeedbackScreen("TemplateEdit")
        }
    }

    private func save() {
        let sectionTuples = sections.map { (title: $0.title, instructions: $0.instructions, style: $0.style) }

        if let template = existingTemplate, !template.isBuiltIn {
            // `TemplateStore.update` re-derives `fieldKey`s from title/instructions/style itself,
            // so the (possibly blank, for a freshly-added row) `fieldKey`s on `sections` here
            // don't matter -- only name/summary/sections' title-instructions-style are used.
            store.update(NoteTemplate(
                id: template.id,
                name: trimmedName,
                summary: summary,
                sections: sections,
                isBuiltIn: false,
                createdAt: template.createdAt
            ))
        } else {
            store.add(name: trimmedName, summary: summary, sections: sectionTuples)
        }
    }
}
