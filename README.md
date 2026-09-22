# Voxbrief: iOS & watchOS Voice Idea Capture & On-Device AI Cleanup

[![Unit Tests](https://github.com/tianhaoz95/voxbrief/actions/workflows/unit-tests.yml/badge.svg)](https://github.com/tianhaoz95/voxbrief/actions/workflows/unit-tests.yml)
[![Release to TestFlight](https://github.com/tianhaoz95/voxbrief/actions/workflows/testflight.yml/badge.svg)](https://github.com/tianhaoz95/voxbrief/actions/workflows/testflight.yml)
[![Release (macOS)](https://github.com/tianhaoz95/voxbrief/actions/workflows/release-mac.yml/badge.svg)](https://github.com/tianhaoz95/voxbrief/actions/workflows/release-mac.yml)
[![Deploy Landing Page to GitHub Pages](https://github.com/tianhaoz95/voxbrief/actions/workflows/deploy_pages.yml/badge.svg)](https://github.com/tianhaoz95/voxbrief/actions/workflows/deploy_pages.yml)

**Voxbrief** is a companion product for iOS and Apple Watch designed to effortlessly capture thoughts and ideas on the go.

The primary capture surface is the **Apple Watch**, allowing instant one-tap recordings from watch face complications or Smart Stack Live Activities. Recordings are saved locally on the watch immediately, and synced to the iPhone in the background when connectivity or background tasks run. 

Once synced, the iOS companion app processes each memo through a **two-stage pipeline**:
1. **Stage 1 (ASR)**: On-device Whisper (via WhisperKit) converts voice into a raw transcript.
2. **Stage 2 (On-Device LLM Cleanup & Copywriting)**: An on-device language model refines the transcript:
   - Requirements are converted into bullet points (`•`).
   - Enumerated conditions use numbered formatting (`1.`, `2.`, ...).
   - Layout is structured into Markdown, and typos or grammar issues are corrected.

---

## 🏗️ Architecture & Data Flow

```mermaid
flowchart TD
    subgraph Apple Watch
        WC["Watch Face Complications\n(Circular, Corner, Rectangular, Inline)"] -->|One-Tap Record| REC["WatchAudioRecorder\n(AAC .m4a @ 32kHz Mono)"]
        LA["Smart Stack Live Activity\n(Timer & Waveform)"] -->|Stop & Save| REC
        REC -->|Save Audio Immediately| WSTORE["Watch Local Storage\n(Documents/WatchRecordings)"]
        WSTORE -->|Background Fetch /\nPeriodic Refresh| WSYNC["WatchSyncService\n(WCSession.transferFile)"]
    end

    WSYNC -->|WatchConnectivity\nBackground Transfer| IOS_SYNC["iOS WatchSyncService\n(WCSessionDelegate)"]

    subgraph iOS Companion App
        IOS_SYNC -->|Receive .m4a & Metadata| STORE["AudioFileManager &\nNoteRepository"]
        STORE --> PIPELINE["NoteProcessingPipeline"]
        
        subgraph Two-Stage Processing
            PIPELINE -->|Stage 1| ASR["ASRService\n(Whisper via WhisperKit, On-Device)"]
            ASR -->|Raw Transcript| LLM["LLMCopywriterService\n(On-Device NLP & LLM Engine)"]
            LLM -->|Formatted Markdown,\nBullets & Numbers| READY["Final Cleaned Note"]
        end
        
        READY --> UI["SwiftUI Note List & Detail Views\n(Cleaned vs Raw, Audio Player, Tags)"]
    end
```

---

## ⌚ Apple Watch Companion (`VoxbriefWatch`)

### 1. Complications & Live Activities
- **Watch Face Complications**: Built using `WidgetKit` with support for `.accessoryCircular`, `.accessoryCorner`, `.accessoryRectangular`, and `.accessoryInline`. Tapping any complication instantly launches the recording flow via deep link `voxbrief://record?source=watch_complication`.
- **Live Activities**: Configured via `ActivityKit` (`VoiceNoteActivityAttributes`). Ongoing recordings display a real-time elapsed timer, pulsing audio waveform meter, and a one-tap **Stop & Save** button in the Smart Stack.

### 2. Instant Local Capture (No Immediate Conversion)
- Recording uses `AVAudioRecorder` configured with high-efficiency AAC (`.m4a`) at 32kHz mono.
- Audio is saved directly to local flash storage (`Documents/WatchRecordings/<UUID>.m4a`).
- Metadata is tracked in `WatchStorage` (`noteId`, `createdAt`, `duration`, `source`, `syncState = .pending`).
- **Zero heavy processing on watch**: Preserves battery and guarantees instant, friction-free voice capture even when completely offline or away from the iPhone.

### 3. Background Sync & Periodic Fetch
- **Automatic Transfer**: Uses `WCSession.default.transferFile(fileURL, metadata: metadata)` which Apple's OS daemon executes in the background even if the watch app suspends or screen sleeps.
- **Background Tasks**: Conforms to `WKExtensionDelegate` with `WKApplicationRefreshBackgroundTask`. Schedules periodic wakeups every 15–30 minutes to sweep pending recordings and ensure reliable delivery to iOS.

---

## 📱 iOS Companion App (`VoxbriefApp`)

### 1. Two-Stage Processing Pipeline

#### Stage 1: Speech-to-Text (ASR)
- Handled by `ASRService`, backed by [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) running OpenAI's Whisper (`base.en`) fully on-device via CoreML.
- No OS-level speech-recognition permission required (only microphone access) -- the model is downloaded once on first use and cached locally, after which transcription needs no network at all.
- Extracts speech from `.m4a` files into verbatim text.

#### Stage 2: On-Device LLM Cleanup & Copywriting
- Handled by `LLMCopywriterService`, backed by a real on-device LLM (Qwen3, via [MLX Swift](https://github.com/ml-explore/mlx-swift-examples)) rather than the rule-based transformer used in earlier builds.
- **Two model tiers**: `Qwen3-0.6B-4bit` ships bundled inside the app (~350 MB) so cleanup works immediately, fully offline, with no setup. `Qwen3-4B-4bit` (~2.3 GB) is an optional, higher-quality model downloaded on demand from Settings — once downloaded, it's used automatically in place of the bundled model. Both run entirely on-device via CoreML/Metal; only the 4B download itself needs network.
- **Structured extraction**: the model is prompted to return JSON (title, summary, requirements, conditions, action items, tags), which is then rendered into the app's own consistent Markdown layout — bulleted requirements, numbered conditions, task-list action items, and domain tags (`#watchOS`, `#iOS`, `#architecture`, `#security`).
- **Local LLM Endpoint Support**: users can instead toggle a local LLM endpoint (such as Ollama `http://127.0.0.1:11434/api/generate`) in Settings to use a more powerful model running on their own machine — off by default.
- **Fallback chain**: Ollama (if enabled) → downloaded Qwen3-4B (if present) → bundled Qwen3-0.6B → a deterministic rule-based transformer as the last-resort, zero-dependency fallback if on-device generation fails for any reason.

### 2. User Experience & Features
- **Cleaned Note vs Raw Transcript**: Segmented switcher allows users to toggle between the polished Markdown note, the verbatim ASR transcript, and the 2-Stage Pipeline diagnostics.
- **Integrated Audio Player**: Audio player card with waveform scrubber, current time, total duration, and play/pause controls.
- **Watch Sync Diagnostics**: Real-time status sheet displaying paired state, reachability, total transferred memos received, and ping diagnostics.
- **Search & Tag Filtering**: Instant search across titles, summaries, transcripts, and tags with dynamic filter pills.
- **iPhone Direct Recording**: Floating record sheet for recording voice notes directly on the iPhone with real-time audio level metering rings.
- **Simulation Tool**: Settings includes a simulator tool to inject realistic test voice memos to verify the complete two-stage pipeline on demand.

---

## 🧪 Project Targets & Verification

The project is structured with clean modular targets:

| Target | Platform | Type | Description |
|---|---|---|---|
| `Voxbrief` | iOS 17.0+ | Application | Main iOS companion app & pipeline runner |
| `VoxbriefWatch` | watchOS 10.0+ | Application | Apple Watch companion app for quick capture |
| `VoxbriefWidgets` | iOS 17.0+ | App Extension | WidgetKit Live Activity widget |
| `VoxbriefWatchWidgets` | watchOS 10.0+ | App Extension | Watch face complications (Circular, Corner, Rectangular, Inline) |
| `VoxbriefTests` | iOS 17.0+ | Unit Tests | Automated test suite verifying ASR, LLM, sync, and storage |

### Running the Unit Tests
```bash
xcodebuild test \
  -project Voxbrief.xcodeproj \
  -scheme Voxbrief \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:VoxbriefTests
```

### Regenerating Project from Spec
```bash
xcodegen generate
```
