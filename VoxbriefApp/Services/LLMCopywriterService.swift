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
    public let requirements: [String]
    public let conditions: [String]
    public let actionItems: [String]
    public let cleanedMarkdown: String
    public let tags: [String]
    public let engine: String

    public init(
        title: String,
        summary: String,
        requirements: [String],
        conditions: [String],
        actionItems: [String],
        cleanedMarkdown: String,
        tags: [String],
        engine: String
    ) {
        self.title = title
        self.summary = summary
        self.requirements = requirements
        self.conditions = conditions
        self.actionItems = actionItems
        self.cleanedMarkdown = cleanedMarkdown
        self.tags = tags
        self.engine = engine
    }
}

public protocol LLMCopywriterServiceProtocol: Sendable {
    /// `dictionary` is the user's personal jargon/proper-noun list (see `DictionaryEntry`),
    /// injected into the LLM prompt as terms to preserve verbatim. Pass `[]` for none.
    func processTranscript(_ rawTranscript: String, mode: RewriteMode, dictionary: [DictionaryEntry]) async throws -> LLMProcessingResult
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
    
    /// Processes a raw speech transcript through Stage 2 LLM cleanup and copywriting.
    /// `mode` defaults to `.full` and `dictionary` defaults to `[]` (today's behavior) so
    /// existing call sites on the concrete type don't need to change; callers through
    /// `LLMCopywriterServiceProtocol` must pass both explicitly since protocol requirements
    /// can't carry default argument values.
    public func processTranscript(_ rawTranscript: String, mode: RewriteMode = .full, dictionary: [DictionaryEntry] = []) async throws -> LLMProcessingResult {
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
                return try await callLocalLLMEndpoint(url: endpointURL, transcript: trimmed, mode: mode, dictionary: dictionary)
            } catch {
                print("[LLMCopywriterService] Local LLM endpoint failed, falling back: \(error)")
            }
        }

        // 2. On-device LLM via MLX Swift -- the bundled Qwen3-0.6B model is always available;
        //    the larger downloaded Qwen3-4B model (see Settings) is used automatically once ready.
        do {
            return try await processWithOnDeviceLLM(transcript: trimmed, mode: mode, dictionary: dictionary)
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

    private struct OnDeviceLLMJSONResult: Decodable {
        var title: String?
        var summary: String?
        var requirements: [String]?
        var conditions: [String]?
        var actionItems: [String]?
        var tags: [String]?
    }

    private struct OnDeviceLLMLightJSONResult: Decodable {
        var title: String?
        var summary: String?
        var cleanedText: String?
        var tags: [String]?
    }

    private func processWithOnDeviceLLM(transcript: String, mode: RewriteMode, dictionary: [DictionaryEntry]) async throws -> LLMProcessingResult {
        switch mode {
        case .full:
            return try await processWithOnDeviceLLMFull(transcript: transcript, dictionary: dictionary)
        case .light:
            return try await processWithOnDeviceLLMLight(transcript: transcript, dictionary: dictionary)
        }
    }

    private func processWithOnDeviceLLMFull(transcript: String, dictionary: [DictionaryEntry]) async throws -> LLMProcessingResult {
        let systemPrompt = """
        You convert a rough spoken voice-memo transcript into structured notes. Respond with ONLY \
        one valid JSON object -- no markdown code fences, no commentary before or after -- using \
        exactly these keys: "title" (string, 8 words or fewer), "summary" (one sentence string), \
        "requirements" (array of strings), "conditions" (array of strings describing sequential \
        steps or if/then logic), "actionItems" (array of strings), "tags" (array of short hashtags \
        starting with #). Use an empty array for any category with nothing to report. Fix grammar \
        and remove filler words in every string.\(dictionaryInstructionBlock(dictionary))
        """

        let raw = try await OnDeviceLLMService.shared.generate(systemPrompt: systemPrompt, userPrompt: transcript)

        guard let jsonSubstring = Self.extractJSONObject(from: raw) else {
            throw LLMCopywriterError.unparsableResponse
        }
        let decoded = try JSONDecoder().decode(OnDeviceLLMJSONResult.self, from: Data(jsonSubstring.utf8))

        let title: String
        if let candidate = decoded.title?.trimmingCharacters(in: .whitespacesAndNewlines), !candidate.isEmpty {
            title = candidate
        } else {
            title = generateTitle(from: splitIntoSentences(sanitizeSpeechTranscript(transcript)), raw: transcript)
        }

        let summary: String
        if let candidate = decoded.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !candidate.isEmpty {
            summary = candidate
        } else {
            summary = "Voice memo captured and structured on-device."
        }

        let requirements = decoded.requirements ?? []
        let conditions = decoded.conditions ?? []
        let actionItems = decoded.actionItems ?? []
        let tags = (decoded.tags?.isEmpty == false) ? decoded.tags! : extractTags(from: transcript)

        let markdown = assembleMarkdown(
            title: title,
            summary: summary,
            requirements: requirements,
            conditions: conditions,
            actionItems: actionItems,
            generalPoints: []
        )

        return LLMProcessingResult(
            title: title,
            summary: summary,
            requirements: requirements,
            conditions: conditions,
            actionItems: actionItems,
            cleanedMarkdown: markdown,
            tags: tags,
            engine: CleanupEngineLabel.onDeviceLLM(model: await OnDeviceLLMService.shared.activeModelDisplayName)
        )
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
    /// model's limited context window on every Stage-2 call, twice per note (.full and .light).
    static let maxDictionaryTermsInPrompt = 50

    /// Renders the dictionary as a "preserve verbatim" instruction block appended to a system
    /// prompt. Returns "" for an empty dictionary so callers can unconditionally interpolate it
    /// without branching. `internal` (not `private`) so it's directly unit-testable.
    func dictionaryInstructionBlock(_ dictionary: [DictionaryEntry]) -> String {
        guard !dictionary.isEmpty else { return "" }
        let terms = dictionary.prefix(Self.maxDictionaryTermsInPrompt).map(\.term).joined(separator: ", ")
        return "\n\nThe speaker uses these specific proper nouns and jargon terms -- if you see a "
            + "close variant of one in the transcript, use this exact spelling and capitalization "
            + "verbatim rather than correcting, translating, or genericizing it: \(terms)."
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
        
        // 10. Assemble Rich Markdown Layout
        let markdown = assembleMarkdown(
            title: title,
            summary: summary,
            requirements: requirements,
            conditions: conditions,
            actionItems: actionItems,
            generalPoints: generalPoints
        )
        
        return LLMProcessingResult(
            title: title,
            summary: summary,
            requirements: requirements,
            conditions: conditions,
            actionItems: actionItems,
            cleanedMarkdown: markdown,
            tags: tags,
            engine: CleanupEngineLabel.ruleBased
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
    
    private func assembleMarkdown(
        title: String,
        summary: String,
        requirements: [String],
        conditions: [String],
        actionItems: [String],
        generalPoints: [String]
    ) -> String {
        var md = "# \(title)\n\n"
        md += "> \(summary)\n\n"
        
        // (a) Requirements converted into bullet points
        if !requirements.isEmpty {
            md += "### 🎯 Requirements\n"
            for req in requirements {
                md += "- \(req)\n"
            }
            md += "\n"
        }
        
        // (b) Enumerated conditions using numbered formatting
        if !conditions.isEmpty {
            md += "### 🔢 Enumerated Conditions & Workflow\n"
            for (index, cond) in conditions.enumerated() {
                md += "\(index + 1). \(cond)\n"
            }
            md += "\n"
        }
        
        // Action Items
        if !actionItems.isEmpty {
            md += "### ✅ Action Items\n"
            for action in actionItems {
                md += "- [ ] \(action)\n"
            }
            md += "\n"
        }
        
        // (c) Cleaned Layout & General Notes
        if !generalPoints.isEmpty {
            md += "### 📝 Polished Transcript & Notes\n"
            for point in generalPoints {
                md += "\(point) "
            }
            md += "\n"
        }
        
        return md.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Optional Local LLM (e.g. Ollama / Local Server) Call
    
    private func callLocalLLMEndpoint(url: URL, transcript: String, mode: RewriteMode, dictionary: [DictionaryEntry]) async throws -> LLMProcessingResult {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0

        let prompt: String
        switch mode {
        case .full:
            prompt = """
            You are an on-device executive copywriter. Transform the following raw voice transcript into clean, structured Markdown:
            1. Requirements must be converted into bullet points.
            2. Enumerated conditions must use numbered formatting (1., 2., ...).
            3. Fix all grammar and typos.\(dictionaryInstructionBlock(dictionary))

            Transcript:
            \(transcript)
            """
        case .light:
            prompt = """
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
        }

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
        
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let responseText = json["response"] as? String {
            let trimmedResponse = responseText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedResponse.isEmpty else {
                throw URLError(.zeroByteResource)
            }

            // Reuse the local extraction engine to derive title/summary/tags (and, in full mode,
            // requirements/conditions/action items) from the local LLM's own output, while keeping
            // its markdown verbatim as the primary cleaned note content (rather than discarding it).
            switch mode {
            case .full:
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
            case .light:
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
        }

        throw URLError(.cannotParseResponse)
    }
}
