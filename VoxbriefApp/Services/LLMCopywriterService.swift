import Foundation

/// Human-readable labels identifying which Stage 2 engine actually ran. Kept as plain strings
/// (rather than an enum with associated values) so `LLMProcessingResult`/`VoiceNote` stay
/// trivially `Codable` with no hand-written coding logic.
public enum CleanupEngineLabel {
    public static let notApplicable = "N/A"
    public static let ollama = "Ollama"
    public static let ruleBased = "Rule-Based (LLM Unavailable)"

    public static func onDeviceLLM(model: String) -> String {
        "On-Device LLM (\(model))"
    }
}

/// Which of the two Stage 2 rewrite styles to produce. Both run through the same engine chain
/// (Ollama -> on-device LLM -> rule-based fallback), just with a different prompt/transform:
/// `.full` restructures the transcript into requirements/conditions/action items (today's
/// behavior), while `.light` only fixes typos, grammar, and filler words, keeping the original
/// wording and sentence order intact.
public enum RewriteMode: Sendable {
    case full
    case light
}

/// Result produced by the Stage 2 on-device LLM cleanup and copywriting engine
public struct LLMProcessingResult: Sendable, Codable {
    public let title: String
    public let summary: String
    /// Legacy fields kept for backward compatibility (search, `NoteDetailView`'s pre-multi-
    /// template rendering path) -- for the `.full` mode's on-device/Ollama paths these are now
    /// derived from `sections` by matching the Design Doc template's fixed section titles, so
    /// they're only ever non-empty when that specific template was chosen. Rule-based `.full`
    /// output (`transformLocally`) always uses Design Doc, so these stay populated exactly as
    /// before for that path.
    public let requirements: [String]
    public let conditions: [String]
    public let actionItems: [String]
    public let cleanedMarkdown: String
    public let tags: [String]
    public let engine: String
    /// General-purpose structured content for whichever `NoteTemplate` was used -- empty for
    /// `.light` mode (no template concept) and for any caller not yet updated to pass templates.
    public let sections: [TemplateSectionContent]
    public let templateId: UUID?
    public let templateName: String

    public init(
        title: String,
        summary: String,
        requirements: [String],
        conditions: [String],
        actionItems: [String],
        cleanedMarkdown: String,
        tags: [String],
        engine: String,
        sections: [TemplateSectionContent] = [],
        templateId: UUID? = nil,
        templateName: String = ""
    ) {
        self.title = title
        self.summary = summary
        self.requirements = requirements
        self.conditions = conditions
        self.actionItems = actionItems
        self.cleanedMarkdown = cleanedMarkdown
        self.tags = tags
        self.engine = engine
        self.sections = sections
        self.templateId = templateId
        self.templateName = templateName
    }
}

public protocol LLMCopywriterServiceProtocol: Sendable {
    /// `dictionary` is the user's personal jargon/proper-noun list (see `DictionaryEntry`),
    /// injected into the LLM prompt as terms to preserve verbatim. Pass `[]` for none.
    /// `templates` is the available set of output templates (built-in + user-defined, see
    /// `NoteTemplate`/`TemplateStore`) the LLM picks from for `.full` mode -- ignored by `.light`
    /// mode, and treated as `NoteTemplate.builtIns` if passed empty.
    func processTranscript(_ rawTranscript: String, mode: RewriteMode, dictionary: [DictionaryEntry], templates: [NoteTemplate]) async throws -> LLMProcessingResult

    /// Best-effort: starts loading whichever engine would actually serve the next call now,
    /// rather than paying that cost inline on first real use. A no-op is a valid, always-safe
    /// implementation (e.g. for a test double, or when routed to Ollama/ineligible for on-device).
    /// See `NoteProcessingPipeline.warmUp`.
    func warmUp() async
}

public enum LLMCopywriterError: LocalizedError {
    case unparsableResponse

    public var errorDescription: String? {
        switch self {
        case .unparsableResponse:
            return "On-device model response could not be parsed as JSON."
        }
    }
}

public final class LLMCopywriterService: LLMCopywriterServiceProtocol, @unchecked Sendable {
    public static let shared = LLMCopywriterService()
    
    public init() {}

    /// Best-effort: warms the on-device model (see `OnDeviceLLMService.warmUp`) so a call already
    /// in flight by the time `processTranscript` actually runs doesn't pay a cold-load cost. A
    /// no-op when routed to the Ollama endpoint instead (nothing on-device to warm) or when
    /// on-device models aren't supported on this device (e.g. the Simulator).
    public func warmUp() async {
        guard !UserDefaults.standard.bool(forKey: "use_local_llm_endpoint") else { return }
        await OnDeviceLLMService.shared.warmUp()
    }

    /// Processes a raw speech transcript through Stage 2 LLM cleanup and copywriting.
    /// `mode` defaults to `.full`, `dictionary`/`templates` default to `[]` (today's behavior,
    /// plus "use the built-in templates" for `templates`) so existing call sites on the concrete
    /// type don't need to change; callers through `LLMCopywriterServiceProtocol` must pass all
    /// three explicitly since protocol requirements can't carry default argument values.
    public func processTranscript(_ rawTranscript: String, mode: RewriteMode = .full, dictionary: [DictionaryEntry] = [], templates: [NoteTemplate] = []) async throws -> LLMProcessingResult {
        let trimmed = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return LLMProcessingResult(
                title: "Empty Note",
                summary: "No speech content detected.",
                requirements: [],
                conditions: [],
                actionItems: [],
                cleanedMarkdown: "_No content recorded._",
                tags: [],
                engine: CleanupEngineLabel.notApplicable
            )
        }

        // 1. Optional external endpoint (e.g. Ollama running a bigger model at home) -- opt-in,
        //    off by default, for users who want to trade on-device-only for more horsepower.
        if UserDefaults.standard.bool(forKey: "use_local_llm_endpoint"),
           let endpointString = UserDefaults.standard.string(forKey: "local_llm_endpoint_url"),
           let endpointURL = URL(string: endpointString) {
            do {
                return try await callLocalLLMEndpoint(url: endpointURL, transcript: trimmed, mode: mode, dictionary: dictionary, templates: templates)
            } catch {
                print("[LLMCopywriterService] Local LLM endpoint failed, falling back: \(error)")
            }
        }

        // 2. On-device LLM via MLX Swift -- the bundled Qwen3-0.6B model is always available;
        //    the larger downloaded Qwen3-4B model (see Settings) is used automatically once ready.
        do {
            return try await processWithOnDeviceLLM(transcript: trimmed, mode: mode, dictionary: dictionary, templates: templates)
        } catch {
            print("[LLMCopywriterService] On-device LLM failed, falling back to rule-based transformer: \(error)")
        }

        // 3. Deterministic rule-based transformer -- the zero-dependency fallback that always works.
        switch mode {
        case .full:
            return transformLocally(rawTranscript: trimmed)
        case .light:
            return transformLocallyLight(rawTranscript: trimmed)
        }
    }

    // MARK: - On-Device LLM (MLX Swift + Qwen3)

    private struct OnDeviceLLMLightJSONResult: Decodable {
        var title: String?
        var summary: String?
        var cleanedText: String?
        var tags: [String]?
    }

    private func processWithOnDeviceLLM(transcript: String, mode: RewriteMode, dictionary: [DictionaryEntry], templates: [NoteTemplate]) async throws -> LLMProcessingResult {
        switch mode {
        case .full:
            return try await processWithOnDeviceLLMFull(transcript: transcript, dictionary: dictionary, templates: templates)
        case .light:
            return try await processWithOnDeviceLLMLight(transcript: transcript, dictionary: dictionary)
        }
    }

    /// Two on-device calls instead of one: first classify which template best fits this
    /// transcript (a short completion -- cheap even though it's a second round trip, since
    /// `OnDeviceLLMService` caches the loaded model after first use, so this only costs a second
    /// generation pass, not a cold load), then generate content using only that one template's
    /// schema. Deliberately not a single combined prompt: asking a small on-device model to hold
    /// every template's schema in context simultaneously and self-select is exactly the kind of
    /// capacity strain multi-template support needs to avoid.
    private func processWithOnDeviceLLMFull(transcript: String, dictionary: [DictionaryEntry], templates: [NoteTemplate]) async throws -> LLMProcessingResult {
        let availableTemplates = templates.isEmpty ? NoteTemplate.builtIns : templates

        let classificationRaw = try await OnDeviceLLMService.shared.generate(
            systemPrompt: buildClassificationSystemPrompt(templates: availableTemplates),
            userPrompt: transcript,
            maxTokens: 24
        )
        let chosenTemplate = resolveTemplate(fromClassificationRaw: classificationRaw, candidates: availableTemplates, fallback: NoteTemplate.fallbackDefault)

        let generationRaw = try await OnDeviceLLMService.shared.generate(
            systemPrompt: buildGenerationSystemPrompt(template: chosenTemplate, dictionary: dictionary),
            userPrompt: transcript
        )
        let parsed = try parseGenerationResponse(generationRaw, template: chosenTemplate)

        let title: String
        if let candidate = parsed.title?.trimmingCharacters(in: .whitespacesAndNewlines), !candidate.isEmpty {
            title = candidate
        } else {
            title = generateTitle(from: splitIntoSentences(sanitizeSpeechTranscript(transcript)), raw: transcript)
        }

        let summary: String
        if let candidate = parsed.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !candidate.isEmpty {
            summary = candidate
        } else {
            summary = "Voice memo captured and structured on-device."
        }

        let tags = (parsed.tags?.isEmpty == false) ? parsed.tags! : extractTags(from: transcript)
        let (requirements, conditions, actionItems) = Self.legacyFields(from: parsed.sections)
        let markdown = assembleMarkdown(title: title, summary: summary, sections: parsed.sections)

        return LLMProcessingResult(
            title: title,
            summary: summary,
            requirements: requirements,
            conditions: conditions,
            actionItems: actionItems,
            cleanedMarkdown: markdown,
            tags: tags,
            engine: CleanupEngineLabel.onDeviceLLM(model: await OnDeviceLLMService.shared.activeModelDisplayName),
            sections: parsed.sections,
            templateId: chosenTemplate.id,
            templateName: chosenTemplate.name
        )
    }

    // MARK: - Multi-template classification & generation

    private struct TemplateClassificationJSON: Decodable {
        var template: String?
    }

    private struct GenerationUniversalFields: Decodable {
        var title: String?
        var summary: String?
        var tags: [String]?
    }

    /// Builds the system prompt for step A (classify): lists every available template's name and
    /// summary, asks for only `{"template": "<exact name>"}` in response -- a short, single-
    /// purpose completion, deliberately simpler than asking the model to also generate content
    /// in the same call. `internal` (not `private`) so it's directly unit-testable, matching
    /// `dictionaryInstructionBlock`'s existing precedent.
    func buildClassificationSystemPrompt(templates: [NoteTemplate]) -> String {
        let listing = templates.map { "- \"\($0.name)\": \($0.summary)" }.joined(separator: "\n")
        return """
        You choose which note-taking template best fits a spoken voice-memo transcript. Available templates:
        \(listing)
        Respond with ONLY one valid JSON object -- no markdown code fences, no commentary before \
        or after -- using exactly this key: "template" (string, the exact name of the best-fitting \
        template from the list above).
        """
    }

    /// Resolves step A's raw model output into one of `candidates`, falling back to `fallback` if
    /// the response can't be parsed or doesn't match any known template by name (case-
    /// insensitive). `internal` for direct unit testing, no LLM call involved.
    func resolveTemplate(fromClassificationRaw raw: String, candidates: [NoteTemplate], fallback: NoteTemplate) -> NoteTemplate {
        guard let jsonSubstring = Self.extractJSONObject(from: raw),
              let decoded = try? JSONDecoder().decode(TemplateClassificationJSON.self, from: Data(jsonSubstring.utf8)),
              let name = decoded.template?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return fallback
        }
        return candidates.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) ?? fallback
    }

    /// Builds the system prompt for step B (generate): universal `title`/`summary`/`tags` keys
    /// always present, plus one key per `template.sections` (keyed by `fieldKey`, guided by
    /// `instructions`) -- a direct generalization of what used to be a hardcoded 4-key prompt.
    /// `internal` for direct unit testing.
    func buildGenerationSystemPrompt(template: NoteTemplate, dictionary: [DictionaryEntry]) -> String {
        let sectionLines = template.sections.map { section -> String in
            let trimmedInstructions = section.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            let instructions = trimmedInstructions.isEmpty ? "Free-form content relevant to this section." : trimmedInstructions
            switch section.style {
            case .paragraph:
                return "\"\(section.fieldKey)\" (string: \(instructions))"
            case .bullet, .numbered, .checklist:
                return "\"\(section.fieldKey)\" (array of strings: \(instructions))"
            }
        }.joined(separator: ", ")

        return """
        You convert a rough spoken voice-memo transcript into structured notes using the \
        "\(template.name)" format. Respond with ONLY one valid JSON object -- no markdown code \
        fences, no commentary before or after -- using exactly these keys: "title" (string, 8 \
        words or fewer), "summary" (one sentence string), \(sectionLines), "tags" (array of short \
        hashtags starting with #). Use an empty array or empty string for any category with \
        nothing to report. Fix grammar and remove filler words in every \
        string.\(dictionaryInstructionBlock(dictionary))
        """
    }

    /// Parses step B's raw model output. Universal fields decode via a small `Decodable` type,
    /// but each template section's own field can't (its key isn't known at compile time), so
    /// this reads the same JSON via `JSONSerialization` instead and looks each one up by
    /// `fieldKey` -- the same style `callLocalLLMEndpoint` already uses for its own request/
    /// response handling, so no new decoding idiom is introduced. Accepts either an array of
    /// strings or a bare string per section (a small model may emit either shape for what's
    /// conceptually "one blob of prose" in a `.paragraph`-style section). Throws only if the
    /// outer JSON object itself can't be extracted at all; a missing/malformed individual
    /// section degrades to an empty array rather than failing the whole response. `internal`
    /// for direct unit testing.
    func parseGenerationResponse(_ raw: String, template: NoteTemplate) throws -> (title: String?, summary: String?, tags: [String]?, sections: [TemplateSectionContent]) {
        guard let jsonSubstring = Self.extractJSONObject(from: raw) else {
            throw LLMCopywriterError.unparsableResponse
        }
        let jsonData = Data(jsonSubstring.utf8)
        let universal = try? JSONDecoder().decode(GenerationUniversalFields.self, from: jsonData)
        let rawObject = (try? JSONSerialization.jsonObject(with: jsonData)) as? [String: Any]

        let sections: [TemplateSectionContent] = template.sections.map { section in
            let items: [String]
            switch rawObject?[section.fieldKey] {
            case let array as [String]:
                items = array
            case let text as String:
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                items = trimmed.isEmpty ? [] : [trimmed]
            default:
                items = []
            }
            return TemplateSectionContent(title: section.title, style: section.style, items: items)
        }

        return (universal?.title, universal?.summary, universal?.tags, sections)
    }

    /// Derives the legacy `requirements`/`conditions`/`actionItems` arrays from a generic
    /// `sections` array, by matching the Design Doc built-in template's fixed section titles --
    /// works automatically whenever that template was chosen (built-in templates can't be
    /// renamed, so this match is reliable), and correctly comes back empty for every other
    /// template. `internal` for direct unit testing.
    static func legacyFields(from sections: [TemplateSectionContent]) -> (requirements: [String], conditions: [String], actionItems: [String]) {
        let requirements = sections.first(where: { $0.title == NoteTemplate.designDoc.sections[0].title })?.items ?? []
        let conditions = sections.first(where: { $0.title == NoteTemplate.designDoc.sections[1].title })?.items ?? []
        let actionItems = sections.first(where: { $0.title == NoteTemplate.designDoc.sections[2].title })?.items ?? []
        return (requirements, conditions, actionItems)
    }

    private func processWithOnDeviceLLMLight(transcript: String, dictionary: [DictionaryEntry]) async throws -> LLMProcessingResult {
        let systemPrompt = """
        You lightly proofread a rough spoken voice-memo transcript. Fix only typos, grammar \
        mistakes, and obvious speech-to-text errors, and remove filler words (um, uh, you know, \
        sort of, kind of). Also remove any bracketed non-speech annotations the speech recognizer \
        inserted, such as [Laughter], [Music], [Inaudible Remark], or [BLANK_AUDIO] -- these are \
        the recognizer's own audio-event tags, not spoken words. Do NOT reorganize, summarize, \
        restructure into lists, or drop any actual spoken content -- keep the original wording, \
        sentence order, and level of detail as close to verbatim as possible. Respond with ONLY \
        one valid JSON object -- no markdown code fences, \
        no commentary before or after -- using exactly these keys: "title" (string, 8 words or \
        fewer), "summary" (one sentence string), "cleanedText" (string, the full lightly-corrected \
        transcript as continuous prose), "tags" (array of short hashtags starting with #).\(dictionaryInstructionBlock(dictionary))
        """

        let raw = try await OnDeviceLLMService.shared.generate(systemPrompt: systemPrompt, userPrompt: transcript)

        guard let jsonSubstring = Self.extractJSONObject(from: raw) else {
            throw LLMCopywriterError.unparsableResponse
        }
        let decoded = try JSONDecoder().decode(OnDeviceLLMLightJSONResult.self, from: Data(jsonSubstring.utf8))

        let sanitizedFallback = stripASRSpecialTokens(sanitizeSpeechTranscript(transcript))

        let title: String
        if let candidate = decoded.title?.trimmingCharacters(in: .whitespacesAndNewlines), !candidate.isEmpty {
            title = candidate
        } else {
            title = generateTitle(from: splitIntoSentences(sanitizedFallback), raw: transcript)
        }

        let summary: String
        if let candidate = decoded.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !candidate.isEmpty {
            summary = candidate
        } else {
            summary = "Voice memo lightly proofread on-device."
        }

        // Strip as a safety net even when the model returned its own cleanedText -- small models
        // don't always follow the "omit bracketed annotations" instruction reliably.
        let cleanedText: String
        if let candidate = decoded.cleanedText?.trimmingCharacters(in: .whitespacesAndNewlines), !candidate.isEmpty {
            cleanedText = stripASRSpecialTokens(candidate)
        } else {
            cleanedText = sanitizedFallback
        }

        let tags = (decoded.tags?.isEmpty == false) ? decoded.tags! : extractTags(from: transcript)

        return LLMProcessingResult(
            title: title,
            summary: summary,
            requirements: [],
            conditions: [],
            actionItems: [],
            cleanedMarkdown: cleanedText,
            tags: tags,
            engine: CleanupEngineLabel.onDeviceLLM(model: await OnDeviceLLMService.shared.activeModelDisplayName)
        )
    }

    /// Small models occasionally wrap valid JSON in prose or code fences despite instructions;
    /// take the outermost `{...}` span rather than failing on the first stray character.
    private static func extractJSONObject(from text: String) -> String? {
        guard let firstBrace = text.firstIndex(of: "{"),
              let lastBrace = text.lastIndex(of: "}"),
              firstBrace < lastBrace else {
            return nil
        }
        return String(text[firstBrace...lastBrace])
    }

    // MARK: - Personal Dictionary Prompt Injection

    /// Smaller than `ASRService.maxVocabularyTerms` since this string enters a small on-device
    /// model's limited context window on every Stage-2 call (the .full pass eagerly, the .light
    /// pass whenever `NoteProcessingPipeline.generateLightCleanup` runs it on demand).
    static let maxDictionaryTermsInPrompt = 50

    /// Renders the dictionary as a "preserve verbatim" instruction block appended to a system
    /// prompt. An entry with a `contextHint` renders as `term (hint)`, so the model has enough to
    /// judge whether an ambiguous or unfamiliar-looking mention actually fits the surrounding
    /// sentence rather than just matching spelling -- entries without one (most terms) render as
    /// a bare term, same as before this existed. Returns "" for an empty dictionary so callers can
    /// unconditionally interpolate it without branching. `internal` (not `private`) so it's
    /// directly unit-testable.
    func dictionaryInstructionBlock(_ dictionary: [DictionaryEntry]) -> String {
        guard !dictionary.isEmpty else { return "" }
        let rendered = dictionary.prefix(Self.maxDictionaryTermsInPrompt).map { entry -> String in
            if let hint = entry.contextHint?.trimmingCharacters(in: .whitespacesAndNewlines), !hint.isEmpty {
                return "\(entry.term) (\(hint))"
            }
            return entry.term
        }.joined(separator: ", ")
        return "\n\nThe speaker uses these specific proper nouns and jargon terms -- if you see a "
            + "close variant of one in the transcript, use this exact spelling and capitalization "
            + "verbatim rather than correcting, translating, or genericizing it. A parenthetical "
            + "after a term describes what it actually is -- use it to judge whether a given "
            + "mention really matches that term instead of forcing every superficially similar "
            + "word to become it: \(rendered)."
    }

    // MARK: - On-Device NLP & Semantic Transformation Engine
    
    private func transformLocally(rawTranscript: String) -> LLMProcessingResult {
        // 1. Clean speech artifacts, filler words, and fix common tech typos
        let sanitized = sanitizeSpeechTranscript(rawTranscript)
        
        // 2. Break into logical sentences
        let rawSentences = splitIntoSentences(sanitized)
        let cleanedSentences = rawSentences.map { cleanAndFormatSentence($0) }.filter { !$0.isEmpty }
        
        // 3. Extract Requirements (Requirements -> Bullet points)
        var requirements: [String] = []
        // 4. Extract Enumerated Conditions (Conditions -> Numbered formatting)
        var conditions: [String] = []
        // 5. Extract Action Items
        var actionItems: [String] = []
        // 6. Remaining body content
        var generalPoints: [String] = []
        
        for sentence in cleanedSentences {
            if isConditionOrSequential(sentence) {
                let cleanedCondition = stripLeadingMarkers(from: sentence, markers: [
                    "condition 1:", "condition 2:", "condition 3:", "condition:",
                    "first,", "firstly,", "first of all,", "second,", "secondly,",
                    "third,", "thirdly,", "step 1:", "step 2:", "step 3:",
                    "then,", "next,", "finally,", "step 1", "step 2", "first", "second", "third"
                ])
                conditions.append(cleanedCondition)
            } else if isRequirement(sentence) {
                let cleanedReq = stripLeadingMarkers(from: sentence, markers: [
                    "we need to", "we must", "requirement is to", "requirement is",
                    "requirements include", "make sure to", "ensure that", "needs to",
                    "it's essential that", "required to", "must have", "should have"
                ])
                requirements.append(cleanedReq)
            } else if isActionItem(sentence) {
                let cleanedAction = stripLeadingMarkers(from: sentence, markers: [
                    "todo:", "todo", "action item:", "action item", "remember to",
                    "don't forget to", "follow up with", "assign to"
                ])
                actionItems.append(cleanedAction)
            } else {
                generalPoints.append(sentence)
            }
        }
        
        // If no explicit conditions found, inspect sentences for sequential flow
        if conditions.isEmpty && cleanedSentences.count >= 2 {
            for (idx, sentence) in cleanedSentences.enumerated() {
                if sentence.lowercased().contains("if ") || sentence.lowercased().contains("when ") {
                    conditions.append(sentence)
                }
            }
        }
        
        // 7. Title Generation
        let title = generateTitle(from: cleanedSentences, raw: sanitized)
        
        // 8. Summary Generation
        let summary = generateSummary(sentences: cleanedSentences, requirements: requirements, conditions: conditions)
        
        // 9. Tag Discovery
        let tags = extractTags(from: sanitized)

        // 10. Rule-based `.full` output is always Design-Doc-shaped -- template selection needs
        //     an LLM to do reliably, which this deterministic fallback doesn't have.
        var sections: [TemplateSectionContent] = []
        if !requirements.isEmpty {
            sections.append(TemplateSectionContent(title: NoteTemplate.designDoc.sections[0].title, style: .bullet, items: requirements))
        }
        if !conditions.isEmpty {
            sections.append(TemplateSectionContent(title: NoteTemplate.designDoc.sections[1].title, style: .numbered, items: conditions))
        }
        if !actionItems.isEmpty {
            sections.append(TemplateSectionContent(title: NoteTemplate.designDoc.sections[2].title, style: .checklist, items: actionItems))
        }
        if !generalPoints.isEmpty {
            sections.append(TemplateSectionContent(title: "📝 Polished Transcript & Notes", style: .paragraph, items: generalPoints))
        }

        // 11. Assemble Rich Markdown Layout
        let markdown = assembleMarkdown(title: title, summary: summary, sections: sections)

        return LLMProcessingResult(
            title: title,
            summary: summary,
            requirements: requirements,
            conditions: conditions,
            actionItems: actionItems,
            cleanedMarkdown: markdown,
            tags: tags,
            engine: CleanupEngineLabel.ruleBased,
            sections: sections,
            templateId: NoteTemplate.designDoc.id,
            templateName: NoteTemplate.designDoc.name
        )
    }
    
    /// Strips WhisperKit's bracketed non-speech annotations (e.g. "[Laughter]",
    /// "[ Inaudible Remark ]", "[Music]", "[BLANK_AUDIO]") -- these are audio-event tags the ASR
    /// model emits, not spoken words. Light Cleanup otherwise preserves the transcript verbatim,
    /// so these need removing explicitly rather than being kept as if they were content.
    private func stripASRSpecialTokens(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "\\[[^\\[\\]]*\\]") else { return text }
        var result = regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: text.utf16.count),
            withTemplate: ""
        )
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Light-mode counterpart to `transformLocally`: fixes typos, filler words, and tech-term
    /// capitalization but never buckets sentences into requirements/conditions/action items --
    /// the output stays in the transcript's original order as plain prose.
    private func transformLocallyLight(rawTranscript: String) -> LLMProcessingResult {
        let sanitized = stripASRSpecialTokens(sanitizeSpeechTranscript(rawTranscript))
        let cleanedSentences = splitIntoSentences(sanitized).map { cleanAndFormatSentence($0) }.filter { !$0.isEmpty }

        let title = generateTitle(from: cleanedSentences, raw: sanitized)
        let summary = generateSummary(sentences: cleanedSentences, requirements: [], conditions: [])
        let tags = extractTags(from: sanitized)
        let cleanedText = cleanedSentences.joined(separator: " ")

        return LLMProcessingResult(
            title: title,
            summary: summary,
            requirements: [],
            conditions: [],
            actionItems: [],
            cleanedMarkdown: cleanedText,
            tags: tags,
            engine: CleanupEngineLabel.ruleBased
        )
    }

    // MARK: - Linguistic Pattern Detectors
    
    private func isRequirement(_ sentence: String) -> Bool {
        let lower = sentence.lowercased()
        let patterns = [
            "need to", "must have", "requirement", "require",
            "make sure", "ensure", "essential", "should have",
            "have to", "is required", "mandatory"
        ]
        return patterns.contains { lower.contains($0) }
    }
    
    private func isConditionOrSequential(_ sentence: String) -> Bool {
        let lower = sentence.lowercased()
        let conditionCues = [
            "condition", "if ", "provided that", "in case",
            "first,", "firstly", "second,", "secondly", "third,",
            "step 1", "step 2", "step 3", "then ", "finally,"
        ]
        return conditionCues.contains { lower.contains($0) }
    }
    
    private func isActionItem(_ sentence: String) -> Bool {
        let lower = sentence.lowercased()
        let actionCues = [
            "todo", "action item", "remember to", "don't forget",
            "follow up", "assign to", "check on", "verify with"
        ]
        return actionCues.contains { lower.contains($0) }
    }
    
    // MARK: - Cleaning & Normalization
    
    private func sanitizeSpeechTranscript(_ text: String) -> String {
        var result = text
        
        // Remove speech filler words
        let fillers = [
            "\\bum\\b", "\\buh\\b", "\\byou know\\b", "\\blike, you know\\b",
            "\\bsort of\\b", "\\bkind of\\b", "\\bso basically\\b", "\\bso um\\b"
        ]
        for filler in fillers {
            if let regex = try? NSRegularExpression(pattern: filler, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: NSRange(location: 0, length: result.utf16.count),
                    withTemplate: ""
                )
            }
        }
        
        // Correct common tech terminology and capitalization
        let techReplacements: [String: String] = [
            "\\bios\\b": "iOS",
            "\\bwatchos\\b": "watchOS",
            "\\bmacos\\b": "macOS",
            "\\basr\\b": "ASR",
            "\\bllm\\b": "LLM",
            "\\bapi\\b": "API",
            "\\bui\\b": "UI",
            "\\bux\\b": "UX",
            "\\bswiftui\\b": "SwiftUI",
            "\\bxcode\\b": "Xcode",
            "\\bcoreml\\b": "CoreML",
            "\\bwifi\\b": "Wi-Fi",
            "\\bapple watch\\b": "Apple Watch",
            "\\blive activity\\b": "Live Activity"
        ]
        
        for (pattern, replacement) in techReplacements {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: NSRange(location: 0, length: result.utf16.count),
                    withTemplate: replacement
                )
            }
        }
        
        // Collapse multiple spaces
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func splitIntoSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.bySentences]) { substring, _, _, _ in
            if let s = substring?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                sentences.append(s)
            }
        }
        if sentences.isEmpty && !text.isEmpty {
            sentences = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        return sentences
    }
    
    private func cleanAndFormatSentence(_ sentence: String) -> String {
        var s = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }
        
        // Capitalize first character
        let first = s.prefix(1).uppercased()
        s = first + s.dropFirst()
        
        // Ensure ends with a period if not punctuation
        if let last = s.last, !".!?:;".contains(last) {
            s.append(".")
        }
        return s
    }
    
    private func stripLeadingMarkers(from sentence: String, markers: [String]) -> String {
        var result = sentence
        let lower = result.lowercased()
        for marker in markers {
            if lower.hasPrefix(marker) {
                let dropCount = marker.count
                let index = result.index(result.startIndex, offsetBy: dropCount)
                result = String(result[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return cleanAndFormatSentence(result)
    }
    
    // MARK: - Title, Summary & Tag Extraction
    
    private func generateTitle(from sentences: [String], raw: String) -> String {
        guard let first = sentences.first else { return "Voice Note" }
        var candidate = first
            .replacingOccurrences(of: "We need to build ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "We need to ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "So basically ", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "This is a note about ", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?:; \n"))
        
        let words = candidate.components(separatedBy: .whitespaces)
        if words.count > 7 {
            candidate = words.prefix(6).joined(separator: " ") + "..."
        }
        
        let firstCap = candidate.prefix(1).uppercased()
        return firstCap + candidate.dropFirst()
    }
    
    private func generateSummary(sentences: [String], requirements: [String], conditions: [String]) -> String {
        if let first = sentences.first {
            return first
        }
        return "Voice memo captured and structured with on-device LLM cleanup."
    }
    
    private func extractTags(from text: String) -> [String] {
        var tags: Set<String> = []
        let lower = text.lowercased()
        
        if lower.contains("watch") || lower.contains("apple watch") { tags.insert("#watchOS") }
        if lower.contains("ios") || lower.contains("iphone") { tags.insert("#iOS") }
        if lower.contains("asr") || lower.contains("speech") || lower.contains("transcript") { tags.insert("#ASR") }
        if lower.contains("llm") || lower.contains("model") || lower.contains("ai") { tags.insert("#AI") }
        if lower.contains("requirement") || lower.contains("spec") { tags.insert("#Requirements") }
        if lower.contains("meeting") || lower.contains("discuss") { tags.insert("#Meeting") }
        if lower.contains("todo") || lower.contains("task") || lower.contains("action item") { tags.insert("#Tasks") }
        if lower.contains("idea") || lower.contains("concept") { tags.insert("#Idea") }
        
        if tags.isEmpty {
            tags.insert("#QuickCapture")
        }
        
        return Array(tags).sorted()
    }
    
    // MARK: - Markdown Assembly
    
    /// Generalized over an arbitrary template's sections instead of three fixed
    /// requirements/conditions/actionItems blocks -- the Design Doc template's section titles
    /// match the original hardcoded strings exactly, so output for that template is byte-
    /// identical to before this generalized. `internal` for direct unit testing.
    func assembleMarkdown(title: String, summary: String, sections: [TemplateSectionContent]) -> String {
        var md = "# \(title)\n\n"
        md += "> \(summary)\n\n"

        for section in sections where !section.items.isEmpty {
            md += "### \(section.title)\n"
            switch section.style {
            case .bullet:
                for item in section.items {
                    md += "- \(item)\n"
                }
            case .numbered:
                for (index, item) in section.items.enumerated() {
                    md += "\(index + 1). \(item)\n"
                }
            case .checklist:
                for item in section.items {
                    md += "- [ ] \(item)\n"
                }
            case .paragraph:
                md += section.items.joined(separator: " ") + "\n"
            }
            md += "\n"
        }

        return md.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Optional Local LLM (e.g. Ollama / Local Server) Call
    
    private func callLocalLLMEndpoint(url: URL, transcript: String, mode: RewriteMode, dictionary: [DictionaryEntry], templates: [NoteTemplate]) async throws -> LLMProcessingResult {
        switch mode {
        case .full:
            return try await callLocalLLMEndpointFull(url: url, transcript: transcript, dictionary: dictionary, templates: templates)
        case .light:
            return try await callLocalLLMEndpointLight(url: url, transcript: transcript, dictionary: dictionary)
        }
    }

    /// Raw POST-and-extract-`"response"` mechanics shared by every Ollama call below.
    private func postToOllama(prompt: String, url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0
        let body: [String: Any] = [
            "model": "llama3.2:1b",
            "prompt": prompt,
            "stream": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let responseText = json["response"] as? String else {
            throw URLError(.cannotParseResponse)
        }
        let trimmed = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw URLError(.zeroByteResource)
        }
        return trimmed
    }

    private func callLocalLLMEndpointLight(url: URL, transcript: String, dictionary: [DictionaryEntry]) async throws -> LLMProcessingResult {
        let prompt = """
        Lightly proofread the following raw voice transcript: fix typos, grammar, and remove \
        filler words (um, uh, you know, sort of). Also remove any bracketed non-speech \
        annotations the speech recognizer inserted, such as [Laughter], [Music], or \
        [Inaudible Remark] -- these are the recognizer's own audio-event tags, not spoken \
        words. Keep the original wording, sentence order, and level of detail for everything \
        actually spoken -- do not restructure it into lists or sections, and do not add \
        commentary. Return only the corrected transcript as plain prose.\(dictionaryInstructionBlock(dictionary))

        Transcript:
        \(transcript)
        """
        let trimmedResponse = try await postToOllama(prompt: prompt, url: url)
        let structured = transformLocallyLight(rawTranscript: trimmedResponse)
        return LLMProcessingResult(
            title: structured.title,
            summary: structured.summary,
            requirements: [],
            conditions: [],
            actionItems: [],
            cleanedMarkdown: stripASRSpecialTokens(trimmedResponse),
            tags: structured.tags,
            engine: CleanupEngineLabel.ollama
        )
    }

    /// Same classify-then-generate flow as the on-device path, over HTTP instead of MLX -- needed
    /// (not just for consistency) because the old prose-instructed approach can only ever bucket
    /// into requirements/conditions/actionItems via `transformLocally`, never into Email/Tweet/
    /// custom template fields. Falls back to `legacyOllamaFullRewrite` if the JSON flow fails,
    /// since an arbitrary user-configured Ollama model is more likely to ignore JSON-formatting
    /// instructions than the bundled on-device one -- keeps that failure mode exactly as
    /// recoverable as it was before multi-template support existed.
    private func callLocalLLMEndpointFull(url: URL, transcript: String, dictionary: [DictionaryEntry], templates: [NoteTemplate]) async throws -> LLMProcessingResult {
        let availableTemplates = templates.isEmpty ? NoteTemplate.builtIns : templates
        do {
            let classificationPrompt = buildClassificationSystemPrompt(templates: availableTemplates) + "\n\nTranscript:\n\(transcript)"
            let classificationRaw = try await postToOllama(prompt: classificationPrompt, url: url)
            let chosenTemplate = resolveTemplate(fromClassificationRaw: classificationRaw, candidates: availableTemplates, fallback: NoteTemplate.fallbackDefault)

            let generationPrompt = buildGenerationSystemPrompt(template: chosenTemplate, dictionary: dictionary) + "\n\nTranscript:\n\(transcript)"
            let generationRaw = try await postToOllama(prompt: generationPrompt, url: url)
            let parsed = try parseGenerationResponse(generationRaw, template: chosenTemplate)

            let title: String
            if let candidate = parsed.title?.trimmingCharacters(in: .whitespacesAndNewlines), !candidate.isEmpty {
                title = candidate
            } else {
                title = generateTitle(from: splitIntoSentences(sanitizeSpeechTranscript(transcript)), raw: transcript)
            }

            let summary: String
            if let candidate = parsed.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !candidate.isEmpty {
                summary = candidate
            } else {
                summary = "Voice memo captured and structured via Ollama."
            }

            let tags = (parsed.tags?.isEmpty == false) ? parsed.tags! : extractTags(from: transcript)
            let (requirements, conditions, actionItems) = Self.legacyFields(from: parsed.sections)
            let markdown = assembleMarkdown(title: title, summary: summary, sections: parsed.sections)

            return LLMProcessingResult(
                title: title,
                summary: summary,
                requirements: requirements,
                conditions: conditions,
                actionItems: actionItems,
                cleanedMarkdown: markdown,
                tags: tags,
                engine: CleanupEngineLabel.ollama,
                sections: parsed.sections,
                templateId: chosenTemplate.id,
                templateName: chosenTemplate.name
            )
        } catch {
            print("[LLMCopywriterService] Ollama JSON template flow failed, falling back to legacy prose rewrite: \(error)")
            return try await legacyOllamaFullRewrite(url: url, transcript: transcript, dictionary: dictionary)
        }
    }

    /// Today's original Ollama `.full` behavior (prose instructions, then reusing the rule-based
    /// extractor on the model's own raw output) -- kept as a fallback for when a user-configured
    /// Ollama model doesn't cooperate with the JSON-schema flow above, preserving the exact
    /// robustness floor Ollama had before multi-template support existed.
    private func legacyOllamaFullRewrite(url: URL, transcript: String, dictionary: [DictionaryEntry]) async throws -> LLMProcessingResult {
        let prompt = """
        You are an on-device executive copywriter. Transform the following raw voice transcript into clean, structured Markdown:
        1. Requirements must be converted into bullet points.
        2. Enumerated conditions must use numbered formatting (1., 2., ...).
        3. Fix all grammar and typos.\(dictionaryInstructionBlock(dictionary))

        Transcript:
        \(transcript)
        """
        let trimmedResponse = try await postToOllama(prompt: prompt, url: url)
        let structured = transformLocally(rawTranscript: trimmedResponse)
        return LLMProcessingResult(
            title: structured.title,
            summary: structured.summary,
            requirements: structured.requirements,
            conditions: structured.conditions,
            actionItems: structured.actionItems,
            cleanedMarkdown: trimmedResponse,
            tags: structured.tags,
            engine: CleanupEngineLabel.ollama
        )
    }
}
