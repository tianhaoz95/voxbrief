import Foundation

@MainActor
public final class NoteProcessingPipeline: ObservableObject {
    public static let shared = NoteProcessingPipeline()
    
    private let asrService: ASRServiceProtocol
    private let llmService: LLMCopywriterServiceProtocol
    private let repository: NoteRepository
    private let audioFileManager: AudioFileManager
    private let dictionaryStore: PersonalDictionaryStore
    private let templateStore: TemplateStore

    @Published public private(set) var activeProcessingCount: Int = 0

    /// Notes currently mid-pipeline. Guards against double-processing the same note when a
    /// retry, a pull-to-refresh, and the original sync-triggered run could otherwise overlap.
    private var inFlightNoteIds: Set<UUID> = []

    /// User-facing opt-out (Settings / Preferences) for the Stage 2 "light" rewrite. Even when
    /// this is on, the light pass is never run eagerly -- see `generateLightCleanup`, which is
    /// the only thing that ever generates it, called lazily when something actually needs to
    /// display it. Defaults to on (matches this feature's behavior before the setting existed).
    public static let lightCleanupEnabledKey = "light_cleanup_enabled"
    /// `nonisolated` since it only touches `UserDefaults` (thread-safe) -- referenced from
    /// `NoteDetailViewModel.DetailTab`, a nested but non-actor-isolated type.
    public nonisolated static var isLightCleanupEnabled: Bool {
        (UserDefaults.standard.object(forKey: lightCleanupEnabledKey) as? Bool) ?? true
    }

    public init(
        asrService: ASRServiceProtocol = ASRService.shared,
        llmService: LLMCopywriterServiceProtocol = LLMCopywriterService.shared,
        repository: NoteRepository = .shared,
        audioFileManager: AudioFileManager = .shared,
        dictionaryStore: PersonalDictionaryStore = .shared,
        templateStore: TemplateStore = .shared
    ) {
        self.asrService = asrService
        self.llmService = llmService
        self.repository = repository
        self.audioFileManager = audioFileManager
        self.dictionaryStore = dictionaryStore
        self.templateStore = templateStore
    }

    /// Starts warming Stage 1 (ASR) and Stage 2 (on-device LLM) the moment a recording begins,
    /// so a call already in flight by the time the user stops talking doesn't pay a full cold-load
    /// cost inline with that note's processing. Fire-and-forget by design: callers
    /// (`RecordingCoordinator.beginRecording`/`CaptureCoordinator.beginCapture`) call this without
    /// awaiting it, racing it against however long the recording lasts; errors are swallowed by
    /// the underlying services' own `warmUp()` implementations, which are always safe no-ops if
    /// something isn't applicable (Ollama routing, Simulator, already warm).
    @discardableResult
    public func warmUp() -> Task<Void, Never> {
        Task { [asrService, llmService] in
            async let asr: Void = asrService.warmUp()
            async let llm: Void = llmService.warmUp()
            _ = await (asr, llm)
        }
    }

    /// Executes the two-stage processing pipeline for a given voice note
    public func process(note: VoiceNote) async {
        guard !inFlightNoteIds.contains(note.id) else { return }

        guard let audioFileName = note.audioFileName else {
            repository.updateStatus(for: note.id, status: .failed, errorMessage: "Missing audio file.")
            return
        }

        let audioURL = audioFileManager.url(for: audioFileName)
        inFlightNoteIds.insert(note.id)
        activeProcessingCount += 1
        defer {
            inFlightNoteIds.remove(note.id)
            activeProcessingCount -= 1
        }
        
        do {
            // Personal dictionary (jargon/proper nouns) -- fetched once and threaded through
            // both stages: it biases ASR decoding, deterministically corrects known mishearings,
            // and tells the LLM which terms to preserve verbatim.
            let dictionaryEntries = dictionaryStore.entries

            // Stage 1: ASR Speech-to-Text
            repository.updateStatus(for: note.id, status: .transcribingASR)
            let asrTranscript = try await asrService.transcribeAudio(at: audioURL, vocabulary: dictionaryEntries.map(\.term))
            let rawTranscript = DictionaryCorrector.apply(to: asrTranscript, entries: dictionaryEntries)

            // Stage 2: On-device LLM cleanup / copywriting. Only the "full" structured rewrite
            // runs here -- the "light" rewrite is never generated eagerly (it used to run
            // concurrently with this one on every single capture, which on a bundled on-device
            // model quietly doubled the Stage 2 GPU work behind every note). See
            // `generateLightCleanup`, called lazily the first time something actually needs to
            // display it.
            repository.updateStatus(for: note.id, status: .cleaningLLM)
            let llmResult = try await llmService.processTranscript(rawTranscript, mode: .full, dictionary: dictionaryEntries, templates: templateStore.allTemplates)

            // Build completed note
            var updatedNote = note
            updatedNote.rawTranscript = rawTranscript
            updatedNote.segments = [
                NoteSegment(
                    id: note.id,
                    audioFileName: audioFileName,
                    createdAt: note.createdAt,
                    duration: note.duration,
                    source: note.source,
                    rawTranscript: rawTranscript
                )
            ]
            updatedNote.title = llmResult.title
            updatedNote.summary = llmResult.summary
            updatedNote.cleanedNote = llmResult.cleanedMarkdown
            updatedNote.requirements = llmResult.requirements
            updatedNote.conditions = llmResult.conditions
            updatedNote.actionItems = llmResult.actionItems
            updatedNote.tags = llmResult.tags
            updatedNote.status = .ready
            updatedNote.errorMessage = nil
            updatedNote.cleanupEngine = llmResult.engine
            updatedNote.templateSections = llmResult.sections
            updatedNote.templateId = llmResult.templateId
            updatedNote.templateName = llmResult.templateName.isEmpty ? nil : llmResult.templateName
            // Deliberately left nil -- see generateLightCleanup, called lazily on demand.
            updatedNote.lightCleanedNote = nil
            updatedNote.lightCleanupEngine = nil

            repository.save(updatedNote)
            
            print("[NoteProcessingPipeline] Successfully processed note: \(note.id) -> '\(llmResult.title)'")
        } catch {
            print("[NoteProcessingPipeline] Processing failed for note \(note.id): \(error)")
            var failedNote = note
            failedNote.status = .failed
            failedNote.errorMessage = error.localizedDescription
            if failedNote.title == "Processing Voice Note..." {
                failedNote.title = "Processing Failed"
                failedNote.summary = error.localizedDescription
            }
            repository.save(failedNote)
        }
    }
    
    /// Re-runs Stage 2 (LLM copywriting) on an existing note's raw transcript. For a multi-segment
    /// note this reprocesses the full accumulated transcript, not just the newest segment.
    public func reprocessWithLLM(noteId: UUID) async {
        guard let note = repository.note(withId: noteId), !note.rawTranscript.isEmpty else { return }

        activeProcessingCount += 1
        defer { activeProcessingCount -= 1 }

        await reprocessStage2(for: noteId)
    }

    /// Appends a freshly-recorded segment's audio to an existing note: runs Stage 1 (ASR) on just
    /// the new audio (older segments already have their own transcripts, so they're never
    /// re-transcribed), then re-runs Stage 2 over *all* of the note's segments together so the
    /// LLM always sees the note's full history, not just the newest snippet.
    public func appendRecording(
        segmentId: UUID,
        audioFileName: String,
        duration: TimeInterval,
        source: NoteSource,
        toNoteId noteId: UUID
    ) async {
        guard repository.note(withId: noteId) != nil, !inFlightNoteIds.contains(noteId) else { return }

        inFlightNoteIds.insert(noteId)
        activeProcessingCount += 1
        defer {
            inFlightNoteIds.remove(noteId)
            activeProcessingCount -= 1
        }

        repository.updateStatus(for: noteId, status: .transcribingASR)
        do {
            let dictionaryEntries = dictionaryStore.entries
            let audioURL = audioFileManager.url(for: audioFileName)
            let asrTranscript = try await asrService.transcribeAudio(at: audioURL, vocabulary: dictionaryEntries.map(\.term))
            let correctedTranscript = DictionaryCorrector.apply(to: asrTranscript, entries: dictionaryEntries)

            guard var note = repository.note(withId: noteId) else { return }
            let segment = NoteSegment(
                id: segmentId,
                audioFileName: audioFileName,
                createdAt: Date(),
                duration: duration,
                source: source,
                rawTranscript: correctedTranscript
            )
            note.segments = (note.segments.isEmpty ? [Self.legacySegment(from: note)] : note.segments) + [segment]
            note.audioFileName = segment.audioFileName
            note.duration = segment.duration
            repository.save(note)

            await reprocessStage2(for: noteId)
        } catch {
            repository.updateStatus(for: noteId, status: .failed, errorMessage: error.localizedDescription)
        }
    }

    /// Folds `sourceId`'s recording(s) into `targetId`: moves its segment(s) onto the target,
    /// deletes the source note's *record* (its audio files are kept -- the target's segments now
    /// reference them, see `NoteRepository.removeRecordOnly`), and re-runs Stage 2 over the
    /// combined transcript. Both notes must already be `.ready` (i.e. have a transcript to merge).
    public func mergeNote(sourceId: UUID, intoTargetId targetId: UUID) async {
        guard sourceId != targetId,
              let source = repository.note(withId: sourceId),
              var target = repository.note(withId: targetId),
              !source.rawTranscript.isEmpty,
              !inFlightNoteIds.contains(targetId), !inFlightNoteIds.contains(sourceId) else { return }

        inFlightNoteIds.insert(targetId)
        inFlightNoteIds.insert(sourceId)
        activeProcessingCount += 1
        defer {
            inFlightNoteIds.remove(targetId)
            inFlightNoteIds.remove(sourceId)
            activeProcessingCount -= 1
        }

        let incomingSegments = source.segments.isEmpty ? [Self.legacySegment(from: source)] : source.segments
        target.segments = (target.segments.isEmpty ? [Self.legacySegment(from: target)] : target.segments) + incomingSegments
        if let latest = incomingSegments.max(by: { $0.createdAt < $1.createdAt }) {
            target.audioFileName = latest.audioFileName
            target.duration = latest.duration
        }
        repository.save(target)
        repository.removeRecordOnly(id: sourceId)

        await reprocessStage2(for: targetId)
    }

    // MARK: - Stage 2 Reprocessing (shared by reprocessWithLLM / appendRecording / mergeNote)

    /// Rebuilds `rawTranscript` as the concatenation of every segment (re-applying dictionary
    /// correction to each, so a newly-added dictionary alias retroactively fixes older segments
    /// too), then re-runs the "full" Stage 2 rewrite over that combined text and saves the
    /// result. Does not touch `activeProcessingCount`/`inFlightNoteIds` -- callers own that.
    ///
    /// Any previously-generated light rewrite is invalidated (set back to nil) rather than
    /// regenerated here -- the transcript just changed underneath it, so the old light text would
    /// be stale, and regenerating it eagerly would defeat the point of it being lazy. It
    /// regenerates the next time something actually displays it (see `generateLightCleanup`).
    private func reprocessStage2(for noteId: UUID) async {
        guard var note = repository.note(withId: noteId) else { return }
        let dictionaryEntries = dictionaryStore.entries

        var segments = note.segments.isEmpty ? [Self.legacySegment(from: note)] : note.segments
        for index in segments.indices {
            segments[index].rawTranscript = DictionaryCorrector.apply(to: segments[index].rawTranscript, entries: dictionaryEntries)
        }
        note.segments = segments

        let mergedTranscript = Self.concatenatedTranscript(for: segments)
        note.rawTranscript = mergedTranscript

        repository.updateStatus(for: noteId, status: .cleaningLLM)
        do {
            let llmResult = try await llmService.processTranscript(mergedTranscript, mode: .full, dictionary: dictionaryEntries, templates: templateStore.allTemplates)
            note.title = llmResult.title
            note.summary = llmResult.summary
            note.cleanedNote = llmResult.cleanedMarkdown
            note.requirements = llmResult.requirements
            note.conditions = llmResult.conditions
            note.actionItems = llmResult.actionItems
            note.tags = llmResult.tags
            note.status = .ready
            note.errorMessage = nil
            note.cleanupEngine = llmResult.engine
            note.templateSections = llmResult.sections
            note.templateId = llmResult.templateId
            note.templateName = llmResult.templateName.isEmpty ? nil : llmResult.templateName
            note.lightCleanedNote = nil
            note.lightCleanupEngine = nil
            repository.save(note)
        } catch {
            repository.updateStatus(for: noteId, status: .failed, errorMessage: error.localizedDescription)
        }
    }

    /// Generates Stage 2's "light" rewrite on demand. Unlike the full rewrite, this is never run
    /// eagerly by `process`/`appendRecording`/`mergeNote`/`reprocessWithLLM` -- it's deferred
    /// until something actually needs to display it (see `NoteDetailViewModel.
    /// ensureLightCleanupGenerated`), since a note's full structured rewrite is what gets read far
    /// more often, and the on-device model only has one GPU command queue to share: running both
    /// eagerly on every capture paid for two full generations even for notes whose light tab a
    /// user might never open. A no-op if the setting is off, the note isn't ready yet, or a light
    /// rewrite already exists (call `reprocessWithLLM`/edit the note to invalidate it first).
    public func generateLightCleanup(noteId: UUID) async {
        guard Self.isLightCleanupEnabled,
              let note = repository.note(withId: noteId),
              note.status == .ready,
              note.lightCleanedNote == nil,
              !inFlightNoteIds.contains(noteId) else { return }

        inFlightNoteIds.insert(noteId)
        activeProcessingCount += 1
        defer {
            inFlightNoteIds.remove(noteId)
            activeProcessingCount -= 1
        }

        do {
            let lightResult = try await llmService.processTranscript(note.rawTranscript, mode: .light, dictionary: dictionaryStore.entries, templates: [])
            guard var updated = repository.note(withId: noteId) else { return }
            updated.lightCleanedNote = lightResult.cleanedMarkdown
            updated.lightCleanupEngine = lightResult.engine
            repository.save(updated)
        } catch {
            // Best-effort: leave lightCleanedNote nil so the UI can offer to retry, without
            // touching the note's overall status -- a failed light pass shouldn't read as the
            // whole note having failed.
            print("[NoteProcessingPipeline] Light cleanup generation failed for note \(noteId): \(error)")
        }
    }

    /// Reconstructs a single `NoteSegment` from a note's top-level fields, for a note persisted
    /// before `segments` existed (see `VoiceNote.segments`'s doc comment).
    private static func legacySegment(from note: VoiceNote) -> NoteSegment {
        NoteSegment(
            id: note.id,
            audioFileName: note.audioFileName ?? "",
            createdAt: note.createdAt,
            duration: note.duration,
            source: note.source,
            rawTranscript: note.rawTranscript
        )
    }

    /// Joins segment transcripts in chronological order. A single segment (the common case) is
    /// returned verbatim with no markers, so today's one-recording notes are byte-identical to
    /// before this feature existed; multiple segments get a per-segment "[Update — ...]" header so
    /// a small on-device model has a temporal cue that later text adds to/revises earlier text
    /// rather than necessarily contradicting it.
    static func concatenatedTranscript(for segments: [NoteSegment]) -> String {
        let sorted = segments.sorted(by: { $0.createdAt < $1.createdAt })
        guard sorted.count > 1 else { return sorted.first?.rawTranscript ?? "" }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        return sorted.map { segment in
            "[Update — \(formatter.string(from: segment.createdAt))]\n\(segment.rawTranscript)"
        }.joined(separator: "\n\n---\n\n")
    }
}
