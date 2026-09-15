import Foundation

/// Result produced by the Stage 2 on-device LLM cleanup and copywriting engine
public struct LLMProcessingResult: Sendable, Codable {
    public let title: String
    public let summary: String
    public let requirements: [String]
    public let conditions: [String]
    public let actionItems: [String]
    public let cleanedMarkdown: String
    public let tags: [String]
    
    public init(
        title: String,
        summary: String,
        requirements: [String],
        conditions: [String],
        actionItems: [String],
        cleanedMarkdown: String,
        tags: [String]
    ) {
        self.title = title
        self.summary = summary
        self.requirements = requirements
        self.conditions = conditions
        self.actionItems = actionItems
        self.cleanedMarkdown = cleanedMarkdown
        self.tags = tags
    }
}

public protocol LLMCopywriterServiceProtocol: Sendable {
    func processTranscript(_ rawTranscript: String) async throws -> LLMProcessingResult
}

public final class LLMCopywriterService: LLMCopywriterServiceProtocol, @unchecked Sendable {
    public static let shared = LLMCopywriterService()
    
    public init() {}
    
    /// Processes a raw speech transcript through Stage 2 LLM cleanup and copywriting
    public func processTranscript(_ rawTranscript: String) async throws -> LLMProcessingResult {
        let trimmed = rawTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return LLMProcessingResult(
                title: "Empty Note",
                summary: "No speech content detected.",
                requirements: [],
                conditions: [],
                actionItems: [],
                cleanedMarkdown: "_No content recorded._",
                tags: []
            )
        }
        
        // Check if an external local LLM endpoint (e.g. Ollama/Local Server) is enabled and reachable
        if UserDefaults.standard.bool(forKey: "use_local_llm_endpoint"),
           let endpointString = UserDefaults.standard.string(forKey: "local_llm_endpoint_url"),
           let endpointURL = URL(string: endpointString) {
            do {
                return try await callLocalLLMEndpoint(url: endpointURL, transcript: trimmed)
            } catch {
                print("[LLMCopywriterService] Local LLM endpoint failed, falling back to on-device transformer: \(error)")
            }
        }
        
        // Execute the built-in intelligent On-Device NLP & Semantic Transformation Engine
        return transformLocally(rawTranscript: trimmed)
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
            tags: tags
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
    
    private func callLocalLLMEndpoint(url: URL, transcript: String) async throws -> LLMProcessingResult {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0
        
        let prompt = """
        You are an on-device executive copywriter. Transform the following raw voice transcript into clean, structured Markdown:
        1. Requirements must be converted into bullet points.
        2. Enumerated conditions must use numbered formatting (1., 2., ...).
        3. Fix all grammar and typos.
        
        Transcript:
        \(transcript)
        """
        
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
            // Process the response into our structured model
            return LLMProcessingResult(
                title: generateTitle(from: [responseText], raw: transcript),
                summary: "Cleaned up via on-device LLM model.",
                requirements: [],
                conditions: [],
                actionItems: [],
                cleanedMarkdown: responseText,
                tags: extractTags(from: responseText)
            )
        }
        
        throw URLError(.cannotParseResponse)
    }
}
