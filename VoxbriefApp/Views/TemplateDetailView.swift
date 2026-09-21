import SwiftUI

/// Read-only view of a `NoteTemplate`'s full content -- its summary and every section's title,
/// instructions, and format. Used for built-in templates (which have no edit sheet, since they
/// can't be edited), reached by tapping a row in `TemplatesView`. Custom templates already show
/// their full content via `TemplateEditView`'s form, so this isn't used for those.
public struct TemplateDetailView: View {
    private let template: NoteTemplate

    public init(template: NoteTemplate) {
        self.template = template
    }

    public var body: some View {
        Form {
            Section(
                header: Text("Summary"),
                footer: Text("What Voxbrief shows the LLM to help it decide whether a transcript fits this template.")
            ) {
                Text(template.summary)
                    .foregroundStyle(.secondary)
            }

            Section(
                header: Text("Sections"),
                footer: Text("Each section becomes one part of the generated note. \"Format\" controls how its content is rendered.")
            ) {
                ForEach(template.sections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(.body.weight(.semibold))
                        if !section.instructions.isEmpty {
                            Text(section.instructions)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Text(section.style.displayName)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle(template.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
