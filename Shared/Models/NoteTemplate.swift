import Foundation

/// How a `TemplateSection`'s content should be rendered in both the assembled Markdown
/// (`LLMCopywriterService.assembleMarkdown`) and `NoteDetailView`'s structured cards.
public enum TemplateSectionStyle: String, Codable, Sendable, Hashable, CaseIterable {
    case bullet
    case numbered
    case checklist
    case paragraph

    public var displayName: String {
        switch self {
        case .bullet: return "Bullet List"
        case .numbered: return "Numbered List"
        case .checklist: return "Checklist"
        case .paragraph: return "Paragraph"
        }
    }
}

/// One section of a `NoteTemplate` -- describes what the LLM should put in a given part of the
/// note, not the content itself (see `TemplateSectionContent` for that).
public struct TemplateSection: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    /// The JSON key the LLM is asked to emit for this section, e.g. "requirements", "subject".
    /// Always derived (slugified from `title`) by `TemplateStore`, never typed directly by the
    /// user -- kept as an implementation detail the same way `DictionaryEntry.id` is invisible
    /// in its own edit UI.
    public var fieldKey: String
    /// Display heading, e.g. "🎯 Requirements".
    public var title: String
    /// Tells the LLM what content belongs in this section.
    public var instructions: String
    public var style: TemplateSectionStyle

    public init(id: UUID = UUID(), fieldKey: String, title: String, instructions: String, style: TemplateSectionStyle) {
        self.id = id
        self.fieldKey = fieldKey
        self.title = title
        self.instructions = instructions
        self.style = style
    }
}

/// A named output format for Stage 2's "full" LLM rewrite -- replaces what used to be a single
/// hardcoded requirements/conditions/actionItems schema. The LLM picks whichever template best
/// fits a given transcript (see `LLMCopywriterService`'s classify-then-generate flow) from the
/// combination of `builtIns` plus whatever the user has created via `TemplateStore`.
public struct NoteTemplate: Identifiable, Codable, Sendable, Hashable {
    public let id: UUID
    public var name: String
    /// One-line description used purely to help the LLM decide whether a transcript fits this
    /// template -- not shown as body content anywhere.
    public var summary: String
    public var sections: [TemplateSection]
    /// Built-in templates are compiled-in (see `builtIns`), never persisted, and can't be edited
    /// or deleted -- `TemplateStore.update`/`delete` no-op for these.
    public var isBuiltIn: Bool
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String, summary: String, sections: [TemplateSection], isBuiltIn: Bool = false, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.summary = summary
        self.sections = sections
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
    }
}

/// The actual generated content for one `TemplateSection`, stored on a `VoiceNote` once Stage 2
/// finishes. `title`/`style` are copied from the `TemplateSection` at generation time (rather
/// than looked up live by `fieldKey`) so a note keeps rendering correctly even if its template is
/// later edited or deleted.
public struct TemplateSectionContent: Codable, Sendable, Hashable {
    public var title: String
    public var style: TemplateSectionStyle
    public var items: [String]

    public init(title: String, style: TemplateSectionStyle, items: [String]) {
        self.title = title
        self.style = style
        self.items = items
    }
}

// MARK: - Built-in templates

extension NoteTemplate {
    /// Fixed, never-changing IDs for the built-in templates. These are compiled into the app
    /// (never persisted to `custom_templates.json`), but a `VoiceNote.templateId` still needs a
    /// stable value to reference across app launches and versions -- so these are literal UUID
    /// strings, never `UUID()`.
    private enum BuiltInID {
        static let designDoc = UUID(uuidString: "8C6E3D1A-9B9A-4E2A-9A9E-4A6E3F5C1A10")!
        static let email = UUID(uuidString: "3F2A7E9C-1D4B-4C8E-9C7D-2B5A6E1F4D22")!
        static let shortTweet = UUID(uuidString: "5A1C9E4F-6D2B-4A7E-8F3C-7E9D2A4B6C33")!
        static let taskList = UUID(uuidString: "0F2D3D28-3643-43F7-8E1F-5093C245A2C0")!
        static let generalNotes = UUID(uuidString: "D4E7B2A9-3C6F-4D1E-9A8B-1F5C3E7A9D44")!
    }

    /// Today's original (and, until now, only) schema -- kept as a selectable template rather
    /// than removed, both so existing notes' shape has a home and so users who want that
    /// structure can still get it. Section titles match the old hardcoded `assembleMarkdown`
    /// strings exactly, so Markdown for this template renders byte-identical to before.
    public static let designDoc = NoteTemplate(
        id: BuiltInID.designDoc,
        name: "Design Doc",
        summary: "Structured technical or planning notes with concrete requirements, sequential conditions or if/then logic, and action items to follow up on.",
        sections: [
            TemplateSection(fieldKey: "requirements", title: "🎯 Requirements", instructions: "Concrete requirements or must-haves mentioned in the transcript.", style: .bullet),
            TemplateSection(fieldKey: "conditions", title: "🔢 Enumerated Conditions & Workflow", instructions: "Sequential steps or if/then logic described in the transcript.", style: .numbered),
            TemplateSection(fieldKey: "actionItems", title: "✅ Action Items", instructions: "Concrete follow-up tasks mentioned in the transcript.", style: .checklist)
        ],
        isBuiltIn: true
    )

    public static let email = NoteTemplate(
        id: BuiltInID.email,
        name: "Email",
        summary: "A message meant to be sent to someone -- has a clear recipient, subject, and body, reads like something you'd paste into an email client.",
        sections: [
            TemplateSection(fieldKey: "subject", title: "Subject", instructions: "A short email subject line summarizing the message.", style: .paragraph),
            TemplateSection(fieldKey: "body", title: "Body", instructions: "The full email body in clear prose, fixing grammar and filler words.", style: .paragraph)
        ],
        isBuiltIn: true
    )

    public static let shortTweet = NoteTemplate(
        id: BuiltInID.shortTweet,
        name: "Short Tweet",
        summary: "A brief, punchy public post or announcement -- one short idea, not a list of tasks or a message to one person.",
        sections: [
            TemplateSection(
                fieldKey: "tweetText",
                title: "Tweet",
                instructions: "The post text itself, tightened to roughly 280 characters or fewer. Do not include hashtags here -- those are captured separately.",
                style: .paragraph
            )
        ],
        isBuiltIn: true
    )

    /// A flat dump of to-dos with no other structure -- distinct from Design Doc's `actionItems`
    /// section, which is one part of a larger requirements/conditions/action-items note. Exists
    /// so a transcript that's just "call the dentist, buy milk, book flights" gets a clean
    /// standalone checklist instead of being force-fit into Design Doc (empty requirements/
    /// conditions sections) or flattened into General Notes prose.
    public static let taskList = NoteTemplate(
        id: BuiltInID.taskList,
        name: "Task List",
        summary: "A flat list of to-dos or tasks to get done -- no requirements, conditions, recipient, or narrative, just standalone action items.",
        sections: [
            TemplateSection(fieldKey: "tasks", title: "✅ Tasks", instructions: "Each distinct to-do or task mentioned in the transcript, as its own item.", style: .checklist)
        ],
        isBuiltIn: true
    )

    /// The safe catch-all: free-form prose, no forced structure. Used both as a selectable
    /// template and as `fallbackDefault` -- deliberately *not* Design Doc, so a transcript the
    /// classifier can't confidently place doesn't get force-fit into a rigid schema anyway,
    /// which is the exact problem this whole redesign exists to fix.
    public static let generalNotes = NoteTemplate(
        id: BuiltInID.generalNotes,
        name: "General Notes",
        summary: "Anything that doesn't clearly fit a more specific format -- a general thought, idea, or note with no particular structure.",
        sections: [
            TemplateSection(fieldKey: "notes", title: "📝 Notes", instructions: "The cleaned-up content in clear prose, fixing grammar and filler words.", style: .paragraph)
        ],
        isBuiltIn: true
    )

    public static let builtIns: [NoteTemplate] = [designDoc, email, shortTweet, taskList, generalNotes]

    /// Used when template classification fails outright (unparsable response) or returns a name
    /// that doesn't match any known template.
    public static let fallbackDefault = generalNotes
}
