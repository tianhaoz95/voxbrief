import Foundation

/// Deterministic, non-LLM post-ASR correction: replaces known ASR mishearings
/// (`DictionaryEntry.aliases`) with each entry's canonical `term`. Uses the same
/// case-insensitive, whole-word `NSRegularExpression` substitution
/// `LLMCopywriterService.sanitizeSpeechTranscript` uses for its hardcoded `techReplacements`
/// table, generalized to user-editable data. Runs once, right after Stage 1 ASR and before
/// Stage 2, so both `.full` and `.light` LLM passes already see corrected proper nouns/jargon.
///
/// Idempotent: once an alias is replaced by its canonical term, the alias no longer matches, so
/// re-running this on already-corrected text (e.g. on `reprocessWithLLM`) is a no-op.
public enum DictionaryCorrector {
    public static func apply(to transcript: String, entries: [DictionaryEntry]) -> String {
        var result = transcript
        for entry in entries {
            for alias in entry.aliases {
                let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedAlias.isEmpty else { continue }
                let pattern = "\\b\(NSRegularExpression.escapedPattern(for: trimmedAlias))\\b"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: NSRange(location: 0, length: result.utf16.count),
                    withTemplate: escapedReplacementTemplate(entry.term)
                )
            }
        }
        return result
    }

    /// `NSRegularExpression` replacement templates treat "$" as a backreference and "\" as an
    /// escape -- escape both so a term containing either is inserted literally.
    private static func escapedReplacementTemplate(_ term: String) -> String {
        term
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "$", with: "\\$")
    }
}
